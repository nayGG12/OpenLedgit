import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/scanned_ticket_data.dart';
import '../models/transaction.dart';

/// Analyse un ticket de caisse avec une vraie IA visuelle en ligne (Google Gemini).
///
/// Pourquoi Gemini : c'est le seul grand modèle multimodal avec un tier gratuit
/// utilisable sans carte bancaire (contrairement à OpenAI/Anthropic qui demandent
/// un paiement dès le départ). Attention : "gratuit" ne veut pas dire "illimité" —
/// Google applique des quotas (un certain nombre de requêtes par minute/jour).
/// Pour un usage personnel (scanner quelques tickets par jour), c'est largement
/// suffisant et ne coûte rien, mais ce n'est pas un usage professionnel/intensif.
///
/// Clé API : chaque utilisateur crée la sienne (gratuite) sur
/// https://aistudio.google.com/apikey et la renseigne dans les paramètres
/// d'OpenLedger. Elle reste stockée en local sur son appareil.
class AIVisionService {
  static const String _model = 'gemini-2.0-flash';

  static const String _prompt = '''
Tu es un assistant qui extrait les informations d'un ticket de caisse à partir d'une photo.
Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, sans balises markdown, sans commentaire, au format EXACT suivant :

{
  "title": "Nom de l'enseigne/du magasin, proprement formaté, ex: Carrefour, Leclerc, Fnac, Pharmacie du Centre",
  "amount": 12.34,
  "category": "Une valeur parmi exactement : Salaire, Alimentation, Transport, Logement, Loisirs, Santé, Shopping, Abonnements, Virement, Autre",
  "date": "AAAA-MM-JJ",
  "location": "Ville visible sur le ticket, ou null si absente"
}

Règles impératives :
- "amount" doit être le MONTANT TOTAL TTC réellement payé (jamais le sous-total, jamais la TVA, jamais un acompte). C'est un nombre, sans texte ni symbole €.
- "title" doit être le nom de l'enseigne/du commerce (regarde le logo et l'en-tête), jamais une ligne d'adresse ni un numéro de ticket.
- Déduis "category" à partir du type de commerce reconnu (ex: supermarché → Alimentation, station essence → Transport, pharmacie → Santé).
- Si une information est totalement absente du ticket, mets null pour ce champ (sauf "title", toujours renseigné du mieux possible).
- Ne renvoie rien d'autre que ce JSON, aucune phrase avant ou après.
''';

  /// Lance l'analyse. Lève une exception explicite en cas d'échec
  /// (pas de connexion, clé invalide, quota dépassé, réponse illisible...)
  /// afin que l'appelant puisse basculer sur l'analyse locale.
  static Future<ScannedTicketData> analyze({
    required String imagePath,
    required String apiKey,
  }) async {
    final model = GenerativeModel(model: _model, apiKey: apiKey);
    final bytes = await File(imagePath).readAsBytes();

    final response = await model.generateContent([
      Content.multi([
        TextPart(_prompt),
        DataPart('image/jpeg', bytes),
      ]),
    ]).timeout(
      const Duration(seconds: 25),
      onTimeout: () => throw Exception('Délai dépassé (pas de réponse de l\'IA en ligne)'),
    );

    final rawText = response.text;
    if (rawText == null || rawText.trim().isEmpty) {
      throw Exception('Réponse vide de l\'IA en ligne');
    }

    final jsonStr = _extractJson(rawText);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final category = (data['category'] as String?)?.trim();
    final title = (data['title'] as String?)?.trim();

    return ScannedTicketData(
      title: (title != null && title.isNotEmpty) ? title : 'Ticket magasin',
      amount: (data['amount'] as num?)?.toDouble(),
      date: _parseIsoDate(data['date'] as String?),
      category: kCategories.contains(category) ? category : 'Autre',
      location: (data['location'] as String?)?.trim(),
      source: TicketSource.ai,
    );
  }

  /// Le modèle ajoute parfois des balises ```json ... ``` autour du JSON : on les retire,
  /// puis on isole strictement le contenu entre la première { et la dernière }.
  static String _extractJson(String text) {
    var cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      throw Exception('Format de réponse IA invalide : $text');
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