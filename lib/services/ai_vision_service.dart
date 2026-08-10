import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;
import '../models/scanned_ticket_data.dart';
import '../models/transaction.dart';

class AIVisionService {
  // Remplace l'ancien modèle par le modèle actif sur Groq :
  static const String _model = 'qwen/qwen3.6-27b';
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';

  static String? lastRawResponse;

  static const int _maxImageWidth = 900;
  static const int _jpegQuality = 60;
  static const int _fallbackImageWidth = 650;
  static const int _fallbackJpegQuality = 45;

  static const Duration _minDelayBetweenCalls = Duration(seconds: 5);
  static DateTime? _lastCallAt;

static const String _systemPrompt = '''
IDENTITÉ ET RÔLE

Tu n'es pas un assistant conversationnel. Tu es un moteur d'extraction de données,
branché directement sur un parseur JSON automatique (fonction jsonDecode()).
Personne ne lit ta réponse avant elle : elle part directement dans un programme
qui tente de la décoder comme du JSON strict. Il n'y a aucune tolérance humaine,
aucune relecture, aucune correction possible après coup.

CONTRAT DE SORTIE (NON NÉGOCIABLE)

Ta réponse ENTIÈRE doit être un unique objet JSON valide, et RIEN d'autre.
- Le premier caractère de ta réponse doit être { (accolade ouvrante).
- Le dernier caractère de ta réponse doit être } (accolade fermante).
- Aucun caractère, aucun espace, aucun saut de ligne avant le { ou après le }.
- Aucune phrase d'introduction ("Voici le résultat :", "D'accord, j'analyse...", etc.).
- Aucune phrase de conclusion ("J'espère que ça aide", "N'hésite pas si...", etc.).
- Aucune balise markdown (pas de ```json, pas de ```, pas de **gras**, rien).
- Aucun commentaire, aucune note, aucune explication, même courte, même entre parenthèses.

CE QUI SE PASSE SI TU NE RESPECTES PAS CE CONTRAT

Le parseur JSON qui reçoit ta réponse ne comprend AUCUN texte en dehors des
accolades. Si tu ajoutes ne serait-ce qu'un seul mot avant ou après le JSON,
même une phrase polie ou une clarification utile, le parseur plante immédiatement
et TOUTE ta réponse est perdue et inutilisable — y compris si les données que tu
as extraites étaient par ailleurs parfaitement correctes. Il n'existe pas de
version "presque conforme" : soit c'est du JSON pur et exploitable, soit c'est
un échec complet de la tâche.

EXEMPLE DE RÉPONSE INTERDITE (à ne jamais produire, même en partie) :
D'accord, voici les informations extraites du ticket :
{"readable": true, "title": "Carrefour", "amount": 24.5, "category": "Alimentation", "date": "2026-08-10", "location": "Paris"}
J'espère que ça t'aide !

Pourquoi c'est interdit : il y a du texte avant et après le JSON. Le parseur
plante avant même d'atteindre la première accolade.

EXEMPLE DE RÉPONSE INTERDITE (variante markdown) :
```json
{"readable": true, "title": "Carrefour", "amount": 24.5, "category": "Alimentation", "date": "2026-08-10", "location": "Paris"}
```*/

Pourquoi c'est interdit : les balises ```json et ``` sont des caractères en
plus, hors du JSON lui-même.

SEULE RÉPONSE ACCEPTÉE (exemple pour un ticket Carrefour de 24,50€) :
{"readable": true, "title": "Carrefour", "amount": 24.5, "category": "Alimentation", "date": "2026-08-10", "location": "Paris"}

Rien avant. Rien après. Une seule ligne ou plusieurs, peu importe, mais rien
en dehors des deux accolades extérieures.

SCHÉMA EXACT À REMPLIR

{
  "readable": true,
  "title": "Nom de l'enseigne/du magasin, ex: Carrefour, Leclerc, Fnac",
  "amount": 12.34,
  "category": "Salaire, Alimentation, Transport, Logement, Loisirs, Santé, Shopping, Abonnements, Virement ou Autre",
  "date": "AAAA-MM-JJ",
  "location": "Ville visible sur le ticket, ou null"
}

RÈGLES DE REMPLISSAGE, CHAMP PAR CHAMP

1. "readable" (booléen, obligatoire)
   - true si le ticket est exploitable, même partiellement.
   - false UNIQUEMENT si l'image n'est clairement pas un ticket de caisse
     exploitable (flou total, image sans rapport, texte totalement illisible).
   - Si false : mets "title" à "Ticket illisible" et TOUS les autres champs
     (amount, date, location) à null. category reste "Autre".

2. "title" (string, obligatoire)
   - Le nom du commerce/de l'enseigne, regardé sur le logo ou l'en-tête.
   - Jamais une ligne d'adresse, jamais un numéro de ticket, jamais un SIRET.

3. "amount" (nombre ou null)
   - Le MONTANT TOTAL TTC réellement payé par le client.
   - Jamais le sous-total, jamais la seule ligne de TVA, jamais un acompte partiel.
   - Un nombre pur, avec un point décimal (12.34), jamais de virgule, jamais
     de symbole €, jamais de texte autour.
   - Si aucun total n'est identifiable avec certitude : null (ne jamais deviner).

4. "category" (string, obligatoire)
   - Exactement une des 10 valeurs listées dans le schéma, aucune autre valeur,
     aucune variante d'orthographe, aucune traduction, aucune invention.
   - Déduite du type de commerce reconnu (ex: supermarché → Alimentation,
     station essence → Transport, pharmacie → Santé, magasin de vêtements → Shopping).

5. "date" (string au format AAAA-MM-JJ, ou null)
   - Si absente ou illisible sur le ticket : null.

6. "location" (string ou null)
   - La ville si elle est visible sur le ticket (souvent près du code postal).
   - Sinon : null.

7. Principe général : ne jamais inventer une donnée absente. null est toujours
   préférable à une valeur devinée. Une donnée fausse est pire qu'une donnée
   manquante.

DERNIER RAPPEL AVANT DE RÉPONDRE

Relis mentalement ta réponse avant de l'envoyer : est-ce que le tout premier
caractère est { ? Est-ce que le tout dernier caractère est } ? Y a-t-il un seul
mot, un seul espace, une seule balise en dehors de ces deux accolades ? Si oui,
supprime-le avant de répondre. Ta réponse finale ne contient RIEN d'autre que
l'objet JSON.
''';

  static const String _userInstruction = 'Analyse ce ticket de caisse et renvoie uniquement le JSON demandé.';

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
          rethrow;
        case RateLimitScope.perMinuteOrUnknown:
          final smallerImage = _encode(decoded, bytes, _fallbackImageWidth, _fallbackJpegQuality);
          if (e.retryAfterSeconds != null && e.retryAfterSeconds! <= 8) {
            await Future.delayed(Duration(seconds: e.retryAfterSeconds!));
          }
          _lastCallAt = DateTime.now();
          return await _requestOnce(base64Image: smallerImage, apiKey: apiKey);
      }
    } on _UnreadableTicketException {
      rethrow;
    } catch (e) {
      _lastCallAt = DateTime.now();
      return await _requestOnce(base64Image: normalImage, apiKey: apiKey);
    }
  }

  static Future<void> _respectLocalCooldown() async {
    final last = _lastCallAt;
    if (last == null) return;
    final elapsed = DateTime.now().difference(last);
    if (elapsed < _minDelayBetweenCalls) {
      await Future.delayed(_minDelayBetweenCalls - elapsed);
    }
  }

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
        'max_completion_tokens': 500,
        // Force l'API à renvoyer du JSON structuré si supporté par le endpoint
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
          retryAfterSeconds: int.tryParse(retryAfterHeader ?? '') ?? _parseWaitSecondsFromMessage(groqMessage),
          groqMessage: groqMessage,
          scope: _detectScope(groqMessage),
        );
      }

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Erreur API Groq (${response.statusCode}) : ${_extractGroqErrorMessage(responseBody) ?? responseBody}');
      }

      final jsonResponse = jsonDecode(responseBody);
      final rawText = jsonResponse['choices']?[0]?['message']?['content'];

      if (rawText == null || (rawText as String).trim().isEmpty) {
        throw Exception('Réponse vide de l\'IA Groq');
      }

      lastRawResponse = rawText;
      _logRawResponse(rawText);

      return _parseModelResponse(rawText);
    } finally {
      httpClient.close();
    }
  }

  static void _logRawResponse(String rawText) {
    const chunkSize = 800;
    debugPrint('┌── [AIVisionService] RÉPONSE BRUTE GROQ (${rawText.length} caractères) ──');
    for (var i = 0; i < rawText.length; i += chunkSize) {
      final end = (i + chunkSize < rawText.length) ? i + chunkSize : rawText.length;
      debugPrint(rawText.substring(i, end));
    }
    debugPrint('└── FIN RÉPONSE BRUTE GROQ ──');
  }

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
    final match = RegExp(r'try again in\s+([\d.]+)s', caseSensitive: false).firstMatch(message);
    if (match == null) return null;
    final seconds = double.tryParse(match.group(1)!);
    return seconds?.ceil();
  }

  static String? _extractGroqErrorMessage(String responseBody) {
    if (responseBody.trim().isEmpty) return null;
    try {
      final parsed = jsonDecode(responseBody);
      if (parsed is! Map) return null;
      final message = parsed['error']?['message'];
      return message is String ? message : null;
    } catch (_) {
      return null;
    }
  }

  static ScannedTicketData _parseModelResponse(String rawText) {
    final jsonStr = _extractJson(rawText);
    late final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw AIResponseFormatException(
        rawResponse: rawText,
        reason: 'Impossible de décoder le JSON extrait : $e',
      );
    }

    final readable = data['readable'];
    if (readable == false) {
      throw _UnreadableTicketException();
    }

    final title = (data['title'] as String?)?.trim();
    final category = (data['category'] as String?)?.trim();
    final rawAmount = data['amount'];

    if (rawAmount != null && rawAmount is! num) {
      throw AIResponseFormatException(
        rawResponse: rawText,
        reason: 'Champ "amount" invalide dans la réponse IA : $rawAmount',
      );
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

  /// Isole le premier objet JSON complet dans la réponse. En cas d'échec
  /// (aucune accolade, JSON tronqué), on lève une AIResponseFormatException
  /// AVEC le texte brut à l'intérieur — jamais de fallback silencieux qui
  /// fabriquerait une fausse donnée "propre" : ça masquerait le problème
  /// et empêcherait le bouton "voir la réponse brute" de s'afficher côté UI.
  static String _extractJson(String text) {
    final cleaned = text.replaceAll('```json', '').replaceAll('```', '');
    final startIndex = cleaned.indexOf('{');

    if (startIndex == -1) {
      throw AIResponseFormatException(
        rawResponse: text,
        reason: 'Aucune accolade ouvrante "{" trouvée dans la réponse',
      );
    }

    var depth = 0;
    var inString = false;
    var escapeNext = false;

    for (var i = startIndex; i < cleaned.length; i++) {
      final char = cleaned[i];
      if (escapeNext) {
        escapeNext = false;
        continue;
      }
      if (char == '\\') {
        escapeNext = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return cleaned.substring(startIndex, i + 1);
        }
      }
    }

    throw AIResponseFormatException(
      rawResponse: text,
      reason: 'Accolade fermante "}" jamais trouvée (JSON tronqué ?)',
    );
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

class RateLimitException implements Exception {
  final int? retryAfterSeconds;
  final String? groqMessage;
  final RateLimitScope scope;

  RateLimitException({this.retryAfterSeconds, this.groqMessage, this.scope = RateLimitScope.perMinuteOrUnknown});

  String get friendlyMessage {
    if (scope == RateLimitScope.perDay) return 'Quota gratuit Groq atteint pour aujourd\'hui.';
    if (retryAfterSeconds != null) return 'Trop de requêtes, réessaie dans ${retryAfterSeconds}s.';
    return 'Limite de requêtes Groq atteinte.';
  }

  @override
  String toString() => 'RateLimitException(${groqMessage ?? friendlyMessage})';
}

class _UnreadableTicketException implements Exception {
  @override
  String toString() => 'Ticket jugé illisible par l\'IA';
}

class AIResponseFormatException implements Exception {
  final String rawResponse;
  final String reason;

  AIResponseFormatException({required this.rawResponse, required this.reason});

  String get detailedMessage => 'Erreur de formatage IA : $reason';

  @override
  String toString() => 'AIResponseFormatException($reason)';
}