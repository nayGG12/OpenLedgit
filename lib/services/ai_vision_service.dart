import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/scanned_ticket_data.dart';
import '../models/transaction.dart';

enum ScanMethod { aiGroq, aiLocal, ocrOnly }

class AIVisionService {
  static const String _model = 'qwen/qwen3.6-27b';
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';

  static String? lastRawResponse;
  static final TextRecognizer _mlKitRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static const String _systemPrompt = '''
IDENTITÉ ET RÔLE : Moteur d'extraction de données pour tickets de caisse.
CONTRAT : Réponds UNIQUEMENT en JSON valide, sans texte autour, sans markdown (pas de ```json).
SCHÉMA EXACT :
{
  "readable": true,
  "title": "Nom de l'enseigne",
  "amount": 12.34,
  "category": "Alimentation, Transport, Logement, Loisirs, Santé, Shopping, Abonnements, Virement, Salaire ou Autre",
  "date": "AAAA-MM-JJ",
  "location": "Ville ou null"
}
''';

  /// Point d'entrée principal permettant de choisir la méthode souhaitée
  static Future<ScannedTicketData> analyzeWithMethod({
    required String imagePath,
    required String apiKey,
    required ScanMethod method,
  }) async {
    switch (method) {
      case ScanMethod.aiGroq:
        return await _analyzeWithGroq(imagePath: imagePath, apiKey: apiKey);
      case ScanMethod.aiLocal:
        return await _analyzeWithLocalAI(imagePath: imagePath);
      case ScanMethod.ocrOnly:
        return await _analyzeWithOcrOnly(imagePath: imagePath);
    }
  }

  // --- MÉTHODE 1 : IA GROQ (Distante, puissante, format JSON natif) ---
  static Future<ScannedTicketData> _analyzeWithGroq({
    required String imagePath,
    required String apiKey,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    final base64Image = _encode(decoded, bytes, 900, 60);

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
              {'type': 'text', 'text': 'Analyse ce ticket de caisse et renvoie uniquement le JSON.'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
            ],
          },
        ],
        'temperature': 0,
        'max_completion_tokens': 500,
        'response_format': {'type': 'json_object'},
      };

      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Erreur Groq (${response.statusCode}) : $responseBody');
      }

      final jsonResponse = jsonDecode(responseBody);
      final rawText = jsonResponse['choices']?[0]?['message']?['content'];
      lastRawResponse = rawText;

      return _parseModelResponse(rawText);
    } finally {
      httpClient.close();
    }
  }

  // --- MÉTHODE 2 : IA LOCALE (ML Kit + Analyse heuristique locale) ---
  static Future<ScannedTicketData> _analyzeWithLocalAI({
    required String imagePath,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _mlKitRecognizer.processImage(inputImage);
    final text = recognizedText.text;
    lastRawResponse = text;

    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    
    String title = lines.isNotEmpty ? lines.first : 'Ticket local';
    double? amount;
    
    final amountRegex = RegExp(r'\b\d+[\.,]\d{2}\b');
    for (var line in lines.reversed) {
      final match = amountRegex.firstMatch(line);
      if (match != null) {
        amount = double.tryParse(match.group(0)!.replaceAll(',', '.'));
        if (amount != null) break;
      }
    }

    return ScannedTicketData(
      title: title.length > 25 ? title.substring(0, 25) : title,
      amount: amount,
      date: DateTime.now(),
      category: 'Autre',
      location: null,
      source: TicketSource.ai,
    );
  }

  // --- MÉTHODE 3 : OCR PUR (Extraction brute sans transformation intelligente) ---
  static Future<ScannedTicketData> _analyzeWithOcrOnly({
    required String imagePath,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _mlKitRecognizer.processImage(inputImage);
    
    final rawText = recognizedText.text; 
    lastRawResponse = rawText;

    return ScannedTicketData(
      title: 'Scan OCR Brut',
      amount: null,
      date: DateTime.now(),
      category: 'Autre',
      location: rawText.isNotEmpty ? 'Texte extrait disponible' : null,
      source: TicketSource.ai,
    );
  }

  static String _encode(img.Image? decoded, Uint8List originalBytes, int maxWidth, int quality) {
    if (decoded == null) return base64Encode(originalBytes);
    final resized = decoded.width > maxWidth ? img.copyResize(decoded, width: maxWidth) : decoded;
    return base64Encode(img.encodeJpg(resized, quality: quality));
  }

  static ScannedTicketData _parseModelResponse(String rawText) {
    final jsonStr = _extractJson(rawText);
    final Map<String, dynamic> data = jsonDecode(jsonStr) as Map<String, dynamic>;

    if (data['readable'] == false) {
      throw Exception('Ticket jugé illisible');
    }

    return ScannedTicketData(
      title: data['title'] ?? 'Ticket magasin',
      amount: (data['amount'] as num?)?.toDouble(),
      date: data['date'] != null ? DateTime.tryParse(data['date']) : null,
      category: data['category'] ?? 'Autre',
      location: data['location'],
      source: TicketSource.ai,
    );
  }

  static String _extractJson(String text) {
    final cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return cleaned.substring(start, end + 1);
    }
    return cleaned;
  }
}