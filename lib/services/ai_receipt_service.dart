import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

class AiReceiptService {
  // Récupère ta clé API (idéalement depuis une variable d'environnement ou un fichier de config)
  static const String _apiKey = 'TA_CLE_API_GEMINI';

  Future<Map<String, dynamic>?> processReceiptWithAI() async {
    // 1. Sélectionner l'image (ticket de caisse ou facture)
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) return null;

    // 2. Charger l'image en mémoire sous forme d'octets
    final imageBytes = await image.readAsBytes();

    // 3. Initialiser le modèle Gemini Flash (ultra rapide et multimodal)
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      // Forçage absolu de la réponse au format JSON valide
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );

    // 4. Prompt structuré pour guider l'IA
    final prompt = TextPart('''
Analyse ce reçu ou ticket de caisse. Extrais les informations de manière rigoureuse et retourne **uniquement** un objet JSON valide respectant strictement ce schéma :
{
  "merchant_name": "Nom du commerce (String ou null)",
  "date": "Date de la transaction au format YYYY-MM-DD (String ou null)",
  "total_amount": 0.00 (Montant total en nombre décimal/float, ou null),
  "currency": "EUR",
  "items": [
    {
      "name": "Nom de l'article",
      "price": 0.00
    }
  ]
}
''');

    // 5. Envoi de l'image et du prompt au modèle
    final response = await model.generateContent([
      Content.multi([
        prompt,
        DataPart('image/jpeg', imageBytes),
      ]),
    ]);

    final jsonString = response.text;
    if (jsonString != null) {
      // Décodage du JSON propre garanti par Gemini
      return jsonDecode(jsonString) as Map<String, dynamic>;
    }

    return null;
  }
}