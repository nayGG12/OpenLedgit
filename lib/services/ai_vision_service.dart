import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/scanned_ticket_data.dart';
import '../models/transaction.dart';

/// Analyse un ticket de caisse via un modèle de vision hébergé sur Groq.
///
/// Le tier gratuit de Groq est limité en TPM/RPM/RPD. Cette version essaie
/// de maximiser les chances qu'une photo passe malgré tout :
/// - image compressée fortement (un ticket reste lisible à basse résolution)
/// - anti-rafale local (évite de déclencher la limite bêtement par double-tap)
/// - retry adaptatif : image encore plus compressée si la limite est "par
///   minute" (souvent ça suffit à repasser sous le quota restant), pas de
///   retry inutile si la limite est "par jour".
class AIVisionService {
  static const String _model = 'qwen/qwen3.6-27b';
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';

  // Taille "normale" d'envoi à l'IA. Ceci ne concerne QUE la copie en mémoire
  // envoyée à Groq : le fichier original du reçu (sauvegardé en local par
  // AddTransactionScreen) n'est jamais modifié ni relu depuis cette classe.
  // Un ticket de caisse reste lisible par l'IA à des tailles très réduites
  // (c'est du texte simple, pas une photo de paysage), donc on compresse fort.
  static const int _maxImageWidth = 900;
  static const int _jpegQuality = 60;

  // Taille de secours, utilisée uniquement en cas de retry après un 429
  // "tokens per minute" : encore plus petite, pour tenter de passer sous
  // le quota restant de la fenêtre en cours.
  static const int _fallbackImageWidth = 650;
  static const int _fallbackJpegQuality = 45;

  // Anti-rafale : on n'autorise pas plus d'un appel toutes les X secondes,
  // pour éviter de déclencher le rate limit à cause d'un double-tap ou
  // d'un enchaînement rapide de scans.
  static const Duration _minDelayBetweenCalls = Duration(seconds: 5);
  static DateTime? _lastCallAt;

  static const String _systemPrompt = '''
Tu es un extracteur strict de données de tickets de caisse à partir d'une photo.
Tu dois répondre UNIQUEMENT avec un objet JSON valide, sans aucun texte autour,
sans balises markdown, sans commentaire, conforme EXACTEMENT à ce schéma :

{
  "readable": true,
  "title": "Nom de l'enseigne/du magasin, ex: Carrefour, Leclerc, Fnac",
  "amount": 12.34,
  "category": "Salaire, Alimentation, Transport, Logement, Loisirs, Santé, Shopping, Abonnements, Virement ou Autre",
  "date": "AAAA-MM-JJ",
  "location": "Ville visible sur le ticket, ou null"
}

Règles impératives, à respecter dans l'ordre :
1. "readable" est un booléen. Mets false UNIQUEMENT si l'image n'est clairement pas un ticket de caisse exploitable (flou total, image sans rapport, texte totalement illisible). Dans ce cas, mets "title" à "Ticket illisible" et tous les autres champs à null.
2. Si "readable" est true : "amount" doit être le MONTANT TOTAL TTC réellement payé par le client — jamais le sous-total, jamais la seule TVA, jamais un acompte partiel. C'est un nombre pur (12.34), sans texte, sans symbole €.
3. "title" doit être le nom du commerce/de l'enseigne (regarde le logo, l'en-tête), jamais une ligne d'adresse, jamais un numéro de ticket ou de SIRET.
4. "category" doit être déduite du type de commerce reconnu et vaut EXACTEMENT une des 10 valeurs listées ci-dessus, aucune autre valeur, aucune variante d'orthographe.
5. "date" est au format AAAA-MM-JJ. Si absente du ticket, mets null.
6. "location" est la ville si elle est visible sur le ticket, sinon null.
7. N'invente jamais une donnée absente : mets null plutôt que de deviner un montant, une date ou une ville.
8. Ne renvoie strictement rien d'autre que cet objet JSON : pas de phrase avant, pas de phrase après, pas d'explication.
''';

  static const String _userInstruction =
      'Voici la photo d\'un ticket de caisse. Analyse-la et réponds avec le JSON demandé, rien d\'autre.';

  /// Lance l'analyse. Applique un anti-rafale, puis gère le rate limit Groq
  /// intelligemment selon son type (minute vs jour) avant, si besoin,
  /// de laisser l'appelant basculer sur l'analyse locale.
  static Future<ScannedTicketData> analyze({
    required String imagePath,
    required String apiKey,
  }) async {
    await _respectLocalCooldown();

    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);

    final normalImage = _encode(decoded, bytes, _maxImageWidth, _jpegQuality);

    try {
      _lastCallAt = DateTime.now();
      return await _requestOnce(base64Image: normalImage, apiKey: apiKey);
    } on RateLimitException catch (e) {
      switch (e.scope) {
        case RateLimitScope.perDay:
          // Aucun retry utile : le quota ne reviendra pas avant le reset journalier.
          rethrow;

        case RateLimitScope.perMinuteOrUnknown:
          // Une image plus petite consomme moins de tokens : on tente de
          // repasser sous le quota restant de la fenêtre en cours.
          final smallerImage =
              _encode(decoded, bytes, _fallbackImageWidth, _fallbackJpegQuality);

          if (e.retryAfterSeconds != null && e.retryAfterSeconds! <= 8) {
            await Future.delayed(Duration(seconds: e.retryAfterSeconds!));
          }

          _lastCallAt = DateTime.now();
          return await _requestOnce(base64Image: smallerImage, apiKey: apiKey);
      }
    } on _UnreadableTicketException {
      rethrow;
    } catch (e) {
      // Erreur ponctuelle de parsing/format : une seule retentative.
      _lastCallAt = DateTime.now();
      return await _requestOnce(base64Image: normalImage, apiKey: apiKey);
    }
  }

  /// Empêche deux appels trop rapprochés (double-tap, scans en rafale) qui
  /// pourraient à eux seuls déclencher la limite par minute côté Groq.
  static Future<void> _respectLocalCooldown() async {
    final last = _lastCallAt;
    if (last == null) return;
    final elapsed = DateTime.now().difference(last);
    if (elapsed < _minDelayBetweenCalls) {
      await Future.delayed(_minDelayBetweenCalls - elapsed);
    }
  }

  /// Prépare l'image pour l'IA : lecture SEULE du fichier (jamais de réécriture),
  /// redimensionnement + recompression en mémoire. Le fichier original du reçu,
  /// utilisé ailleurs dans l'app pour l'affichage/la sauvegarde du reçu, n'est
  /// jamais touché ni recompressé par cette classe.
  static String _encode(img.Image? decoded, Uint8List originalBytes, int maxWidth, int quality) {
    if (decoded == null) return base64Encode(originalBytes);
    final resized = decoded.width > maxWidth ? img.copyResize(decoded, width: maxWidth) : decoded;
    return base64Encode(img.encodeJpg(resized, quality: quality));
  }

  static Future<ScannedTicketData> _requestOnce({
    required String base64Image,
    required String apiKey,
  }) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.postUrl(Uri.parse(_url));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $apiKey');

      final body = {
        'model': _model,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _userInstruction},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        'temperature': 0,
        'top_p': 1,
        'max_completion_tokens': 500,
        'response_format': {'type': 'json_object'},
      };

      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close().timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw Exception('Délai dépassé (pas de réponse de Groq)'),
          );

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 429) {
        final retryAfterHeader = response.headers.value('retry-after');
        final groqMessage = _extractGroqErrorMessage(responseBody);
        throw RateLimitException(
          retryAfterSeconds: int.tryParse(retryAfterHeader ?? '') ??
              _parseWaitSecondsFromMessage(groqMessage),
          groqMessage: groqMessage,
          scope: _detectScope(groqMessage),
        );
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception(
          'Erreur API Groq (${response.statusCode}) : ${_extractGroqErrorMessage(responseBody) ?? responseBody}',
        );
      }

      final jsonResponse = jsonDecode(responseBody);
      final rawText = jsonResponse['choices']?[0]?['message']?['content'];

      if (rawText == null || (rawText as String).trim().isEmpty) {
        throw Exception('Réponse vide de l\'IA Groq');
      }

      return _parseModelResponse(rawText);
    } finally {
      httpClient.close();
    }
  }

  /// Détermine si la limite atteinte est journalière (RPD) — auquel cas
  /// retenter ne sert à rien avant le reset — ou par minute (TPM/RPM),
  /// auquel cas réduire la taille de l'image peut suffire à passer.
  static RateLimitScope _detectScope(String? message) {
    if (message == null) return RateLimitScope.perMinuteOrUnknown;
    final lower = message.toLowerCase();
    if (lower.contains('per day') || lower.contains('rpd') || lower.contains('tpd')) {
      return RateLimitScope.perDay;
    }
    return RateLimitScope.perMinuteOrUnknown;
  }

  static int? _parseWaitSecondsFromMessage(String? message) {
    if (message == null) return null;
    final match = RegExp(r'try again in\s+([\d.]+)s', caseSensitive: false)
        .firstMatch(message);
    if (match == null) return null;
    final seconds = double.tryParse(match.group(1)!);
    if (seconds == null) return null;
    return seconds.ceil();
  }

  static String? _extractGroqErrorMessage(String responseBody) {
    if (responseBody.trim().isEmpty) return null;
    try {
      final parsed = jsonDecode(responseBody);
      // Note : on évite volontairement `parsed is Map ? ... : null` ici.
      // Dart lit `is Map ?` comme le type nullable `Map?` (piège de syntaxe
      // connu), ce qui casse le parsing du ternaire. On sépare donc le test
      // de type dans un `if` distinct.
      if (parsed is! Map) return null;
      final message = parsed['error']?['message'];
      if (message is! String) return null;
      return message;
    } catch (_) {
      return null;
    }
  }

  static ScannedTicketData _parseModelResponse(String rawText) {
    final jsonStr = _extractJson(rawText.trim());
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final readable = data['readable'];
    if (readable == false) {
      throw _UnreadableTicketException();
    }

    final title = (data['title'] as String?)?.trim();
    final category = (data['category'] as String?)?.trim();
    final rawAmount = data['amount'];

    if (rawAmount != null && rawAmount is! num) {
      throw Exception('Champ "amount" invalide dans la réponse IA : $rawAmount');
    }

    return ScannedTicketData(
      title: (title != null && title.isNotEmpty) ? title : 'Ticket magasin',
      amount: (rawAmount as num?)?.toDouble(),
      date: _parseIsoDate(data['date'] as String?),
      category: kCategories.contains(category) ? category! : 'Autre',
      location: (data['location'] as String?)?.trim(),
      source: TicketSource.ai,
    );
  }

  static String _extractJson(String text) {
    var cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      throw Exception('Format de réponse JSON invalide : $text');
    }
    return cleaned.substring(start, end + 1);
  }

  static DateTime? _parseIsoDate(String? value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}

enum RateLimitScope { perMinuteOrUnknown, perDay }

/// Erreur de rate limit Groq (HTTP 429).
class RateLimitException implements Exception {
  final int? retryAfterSeconds;
  final String? groqMessage;
  final RateLimitScope scope;

  RateLimitException({
    this.retryAfterSeconds,
    this.groqMessage,
    this.scope = RateLimitScope.perMinuteOrUnknown,
  });

  /// Message prêt à afficher à l'utilisateur (sans jargon HTTP).
  String get friendlyMessage {
    if (scope == RateLimitScope.perDay) {
      return 'Quota gratuit Groq atteint pour aujourd\'hui. Réessaie demain, ou utilise l\'analyse locale en attendant.';
    }
    if (retryAfterSeconds != null) {
      return 'Trop de requêtes envoyées à l\'IA en ligne, réessaie dans ${retryAfterSeconds}s.';
    }
    return 'Limite de requêtes Groq atteinte pour le moment (quota gratuit dépassé).';
  }

  @override
  String toString() => 'RateLimitException(${groqMessage ?? friendlyMessage})';
}

class _UnreadableTicketException implements Exception {
  @override
  String toString() => 'Ticket jugé illisible par l\'IA';
}