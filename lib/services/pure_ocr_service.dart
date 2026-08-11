import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scanned_ticket_data.dart';
import '../models/transaction.dart';

class PureOcrService {
  // Instance du détecteur de texte natif Google ML Kit (latin)
  static final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Méthode clé en main pour scanner une image et retourner un objet structuré basique
  static Future<ScannedTicketData?> scanRawText() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    
    if (image == null) return null;

    final inputImage = InputImage.fromFilePath(image.path);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Rassemble toutes les lignes détectées
    final List<String> lines = [];
    for (var block in recognizedText.blocks) {
      for (var line in block.lines) {
        lines.add(line.text.trim());
      }
    }

    final String fullRawText = lines.join('\n');

    // Tentative de détection basique d'un montant (ex: cherche un prix à la fin ou le plus grand)
    double? detectedAmount;
    final amountRegex = RegExp(r'\b\d+[\.,]\d{2}\b');
    for (var line in lines.reversed) {
      final match = amountRegex.firstMatch(line);
      if (match != null) {
        detectedAmount = double.tryParse(match.group(0)!.replaceAll(',', '.'));
        if (detectedAmount != null) break;
      }
    }

    return ScannedTicketData(
      title: lines.isNotEmpty ? lines.first : 'Ticket scanné',
      amount: detectedAmount,
      date: DateTime.now(),
      category: 'Autre',
      location: fullRawText, // On stocke tout le texte brut ici pour l'inspecter si besoin
      source: TicketSource.local,
    );
  }

  static void dispose() {
    _textRecognizer.close();
  }
}