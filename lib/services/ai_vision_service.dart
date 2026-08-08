import 'dart:convert';
import 'dart:io';
import '../models/scanned_ticket_data.dart';
import '../models/transaction.dart';

/// Analyse un ticket de caisse via un modèle de vision hébergé sur Groq.
///
/// Le modèle qwen/qwen3.6-27b supporte un vrai "JSON mode" côté Groq
/// (response_format: json_object) : la réponse est garantie d'être un JSON
/// syntaxiquement valide, ce qui élimine la quasi-totalité des erreurs de
/// parsing qu'on avait avant (texte parasite, balises ```json, phrases
/// d'excuse du modèle, etc.).
///
/// Note : Groq documente ce modèle comme "preview" (évaluation), pas encore
/// garanti "production" à long terme — à surveiller si Groq le remplace.
class AIVisionService {
  static const String _model = 'qwen/qwen3.6-27b';
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';

  /// Instructions système : schéma JSON strict et fermé.
  /// Le champ "readable" évite l'ancien piège du texte libre "Ticket illisible"
  /// (qui cassait le parsing JSON) : on reste TOUJOURS dans un JSON valide,
  /// y compris quand le ticket n'est pas exploitable.
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

  /// Lance l'analyse avec un retry automatique : si la première réponse
  /// n'est pas un JSON exploitable, on retente une fois avant d'abandonner
  /// (l'appelant bascule alors sur l'analyse locale).
  static Future<ScannedTicketData> analyze({
    required String imagePath,
    required String apiKey,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await _requestOnce(base64Image: base64Image, apiKey: apiKey);
      } catch (e) {
        lastError = e;
        // On ne retente que si ça vaut le coup (erreur de format/parsing) ;
        // pas la peine de retenter sur un ticket explicitement illisible.
        if (e is _UnreadableTicketException) rethrow;
      }
    }
    throw Exception('Échec de l\'analyse IA après 2 tentatives : $lastError');
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
        // Force une sortie JSON syntaxiquement valide côté Groq.
        'response_format': {'type': 'json_object'},
      };

      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close().timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw Exception('Délai dépassé (pas de réponse de Groq)'),
          );

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Erreur API Groq (${response.statusCode}) : $responseBody');
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

  /// Parse et valide strictement la réponse du modèle selon le schéma attendu.
  /// Lève une exception explicite si un champ obligatoire est incohérent,
  /// pour que l'appelant puisse retenter ou basculer en local plutôt que
  /// d'enregistrer une transaction avec des données fausses.
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

    // Validation stricte : un montant qui n'est ni num ni null est un signe
    // que le modèle n'a pas respecté le schéma -> on préfère échouer proprement
    // (et retenter / basculer en local) plutôt que de deviner.
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

  /// Filet de sécurité : même avec le JSON mode de Groq, on isole strictement
  /// le contenu entre la première { et la dernière } au cas où un modèle
  /// ajouterait malgré tout des balises ```json autour.
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

/// Exception dédiée pour un ticket explicitement jugé illisible par l'IA
/// (par opposition à une simple erreur technique/réseau).
class _UnreadableTicketException implements Exception {
  @override
  String toString() => 'Ticket jugé illisible par l\'IA';
}