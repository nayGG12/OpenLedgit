import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../screens/add_transaction_screen.dart';
import '../theme/app_theme.dart';

class ScanTicketScreen extends StatefulWidget {
  const ScanTicketScreen({
    super.key,
    required this.accounts,
    this.returnScannedData = false,
  });

  final List<Account> accounts;
  final bool returnScannedData;

  @override
  State<ScanTicketScreen> createState() => _ScanTicketScreenState();
}

class _ScanTicketScreenState extends State<ScanTicketScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  ScannedTicketData? _ticket;
  String? _error;
  bool _isProcessing = false;
  String? _capturedImagePath;

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // Prendre une photo du ticket avec la caméra
  Future<void> _captureAndProcessTicket() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (pickedFile == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
      _capturedImagePath = pickedFile.path;
    });

    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      // Analyse du texte extrait par l'IA locale
      final parsedData = _parseRecognizedText(recognizedText);

      setState(() {
        _ticket = parsedData;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur lors de l\'analyse locale du ticket : $e';
        _isProcessing = false;
      });
    }
  }

  // Algorithme d'extraction intelligent basé sur le texte brut du ticket
  ScannedTicketData _parseRecognizedText(RecognizedText recognizedText) {
    double? amount;
    DateTime? date;
    String? category;
    String title = 'Ticket magasin';

    List<String> lines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        lines.add(line.text);
      }
    }

    // Le nom du magasin se trouve souvent sur les premières lignes du ticket
    if (lines.isNotEmpty) {
      for (var line in lines.take(3)) {
        if (line.length > 2 && !RegExp(r'^\d+').hasMatch(line)) {
          title = line.trim();
          break;
        }
      }
    }

    // Recherche globale dans toutes les lignes du ticket
    for (String line in lines) {
      final cleanLine = line.toLowerCase();

      // Recherche du montant total (ex: "TOTAL", "TOTAL TTC", "EUR", etc.)
      if (amount == null &&
          (cleanLine.contains('total') ||
              cleanLine.contains('eur') ||
              cleanLine.contains('€'))) {
        final extracted = _extractNumber(line);
        if (extracted != null && extracted < 10000) {
          // Évite de prendre un numéro de téléphone ou siret
          amount = extracted;
        }
      }

      // Recherche de date (ex: JJ/MM/AAAA ou JJ-MM-AA)
      if (date == null) {
        date = _parseDate(line);
      }
    }

    // Si aucun "TOTAL" explicite n'a été trouvé, on cherche le plus grand prix du ticket
    if (amount == null) {
      double maxVal = 0.0;
      for (String line in lines) {
        final val = _extractNumber(line);
        if (val != null && val > maxVal && val < 5000) {
          maxVal = val;
        }
      }
      if (maxVal > 0) amount = maxVal;
    }

    return ScannedTicketData(
      title: title,
      amount: amount,
      date: date ?? DateTime.now(),
      category:
          category ??
          kCategories.firstWhere(
            (item) => item == 'Alimentation',
            orElse: () => kCategories.last,
          ),
    );
  }

  double? _extractNumber(String text) {
    // Cherche un format de type 12.34 ou 12,34
    final regExp = RegExp(r'(\d+[\.,]\d{2})');
    final match = regExp.firstMatch(text.replaceAll(' ', ''));
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    return null;
  }

  DateTime? _parseDate(String text) {
    final regExp = RegExp(r'(\d{2})[./-](\d{2})[./-](\d{2,4})');
    final match = regExp.firstMatch(text);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      var year = int.parse(match.group(3)!);
      if (year < 100) year += 2000;
      try {
        return DateTime(year, month, day);
      } catch (_) {}
    }
    return null;
  }

  void _returnScannedData() {
    if (_ticket == null) return;
    Navigator.pop(context, _ticket);
  }

  void _openPrefilledEntry() {
    if (_ticket == null) return;
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          accounts: widget.accounts,
          initialTitle: _ticket!.title,
          initialAmount: _ticket!.amount,
          initialCategory: _ticket!.category,
          initialDate: _ticket!.date,
          initialReceiptImagePath: _capturedImagePath,
        ),
      ),
    ).then((saved) {
      if (saved == true && mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner un ticket (IA Locale)')),
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _isProcessing
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.green),
                          SizedBox(height: 16),
                          Text(
                            'Analyse du ticket par l\'IA locale...',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : _ticket != null
                  ? _buildPreviewCard()
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.document_scanner_outlined,
                            size: 64,
                            color: AppColors.green,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Prends en photo ton ticket de caisse.\nL\'IA extraira automatiquement le nom, le montant et la date.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _captureAndProcessTicket,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Prendre en photo le ticket'),
                          ),
                        ],
                      ),
                    ),
            ),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.red)),
              const SizedBox(height: 12),
            ],
            if (_ticket != null) ...[
              ElevatedButton.icon(
                onPressed: _captureAndProcessTicket,
                icon: const Icon(Icons.refresh),
                label: const Text('Refaire une photo'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: widget.returnScannedData
                    ? _returnScannedData
                    : _openPrefilledEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                ),
                icon: const Icon(Icons.check),
                label: const Text('Utiliser ces informations'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final ticket = _ticket!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informations détectées :',
            style: TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          _buildPreviewRow('Nom / Titre', ticket.title),
          _buildPreviewRow(
            'Montant',
            ticket.amount != null
                ? '${ticket.amount?.toStringAsFixed(2)} €'
                : 'Non détecté',
          ),
          _buildPreviewRow(
            'Date',
            ticket.date != null
                ? '${ticket.date?.day.toString().padLeft(2, '0')}/${ticket.date?.month.toString().padLeft(2, '0')}/${ticket.date?.year}'
                : 'Non détectée',
          ),
          _buildPreviewRow('Catégorie', ticket.category ?? 'Autre'),
          const Spacer(),
          const Text(
            'Vérifie les données. Tu pourras les modifier à l\'étape suivante si besoin.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ScannedTicketData {
  final String title;
  final DateTime? date;
  final double? amount;
  final String? category;

  const ScannedTicketData({
    required this.title,
    this.date,
    this.amount,
    this.category,
  });
}
