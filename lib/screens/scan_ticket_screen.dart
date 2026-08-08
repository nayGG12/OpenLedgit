// [source: 28]
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../models/scanned_ticket_data.dart';
import '../screens/add_transaction_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/ai_settings_service.dart';
import '../services/ai_vision_service.dart';

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
  bool _isPickingImage = false;
  String? _capturedImagePath;
  String? _geminiApiKey;
  
  // Variable pour choisir entre l'IA Gemini en ligne et l'IA locale
  bool _useGemini = true; 

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final key = await AISettingsService.getGeminiApiKey();
    if (mounted) {
      setState(() {
        _geminiApiKey = key;
        // Si aucune clé n'est enregistrée, on force le mode local par défaut
        if (key == null || key.isEmpty) {
          _useGemini = false;
        }
      });
    }
  }

  Future<void> _openApiKeyDialog() async {
    final controller = TextEditingController(text: _geminiApiKey ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('IA visuelle en ligne (Gemini)', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Renseigne ta clé API Gemini personnelle et gratuite pour une analyse '
              'beaucoup plus fiable (marque, montant, catégorie).',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Clé API Gemini'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Clé gratuite à obtenir sur aistudio.google.com/apikey',
              style: TextStyle(color: AppColors.green, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer', style: TextStyle(color: AppColors.green)),
          ),
        ],
      ),
    );

    if (saved == true) {
      await AISettingsService.setGeminiApiKey(controller.text);
      await _loadApiKey();
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _captureAndProcessTicket() async {
    if (_isPickingImage) return;
    _isPickingImage = true;
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (pickedFile == null) return;
      await _processTicketImage(pickedFile);
    } finally {
      _isPickingImage = false;
    }
  }

  Future<void> _pickFromGalleryAndProcessTicket() async {
    if (_isPickingImage) return;
    _isPickingImage = true;
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (pickedFile == null) return;
      await _processTicketImage(pickedFile);
    } finally {
      _isPickingImage = false;
    }
  }

  Future<void> _processTicketImage(XFile pickedFile) async {
    setState(() {
      _isProcessing = true;
      _error = null;
      _capturedImagePath = pickedFile.path;
    });

    // Si l'utilisateur a choisi Gemini et qu'une clé est présente
    if (_useGemini && _geminiApiKey != null && _geminiApiKey!.isNotEmpty) {
      try {
        final aiResult = await AIVisionService.analyze(
          imagePath: pickedFile.path,
          apiKey: _geminiApiKey!,
        );
        if (!mounted) return;
        setState(() {
          _ticket = aiResult;
          _isProcessing = false;
        });
        return;
      } catch (e) {
        debugPrint('IA en ligne indisponible, repli sur l\'analyse locale : $e');
        setState(() {
          _error = 'Erreur IA Gemini : $e (Basculement en local)';
        });
      }
    }

    // Analyse locale (fallback ou choix explicite "IA locale")
    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      final parsedData = _parseRecognizedText(recognizedText);

      if (!mounted) return;
      setState(() {
        _ticket = parsedData;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur lors de l\'analyse locale du ticket : $e';
        _isProcessing = false;
      });
    }
  }

  // (Toutes les fonctions de parsing et _brandCategories restent inchangées ici...)
  static const Map<String, String> _brandCategories = {
    'carrefour': 'Alimentation', 'leclerc': 'Alimentation', 'e.leclerc': 'Alimentation',
    'auchan': 'Alimentation', 'intermarche': 'Alimentation', 'lidl': 'Alimentation',
  };

  static final RegExp _noiseLineRegex = RegExp(
    r'siret|siren|rcs|tva\s*intra|n[°o]\s*tva|tel\s*[:.]|t[ée]l[ée]phone|caissier|caisse\s*n|ticket\s*n',
    caseSensitive: false,
  );

  static const Map<String, String> _accentMap = {
    'à': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
    'œ': 'oe', 'æ': 'ae',
  };

  String _normalize(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_accentMap[char] ?? char);
    }
    return buffer.toString().trim();
  }

  ({String? name, String? category}) _detectBrand(List<String> lines) {
    for (final line in lines) {
      final normalized = _normalize(line);
      for (final entry in _brandCategories.entries) {
        if (normalized.contains(entry.key.trim())) {
          final matchedCategory = kCategories.contains(entry.value) ? entry.value : (kCategories.isNotEmpty ? kCategories.first : 'Autre');
          return (name: _toDisplayName(entry.key.trim()), category: matchedCategory);
        }
      }
    }
    return (name: null, category: null);
  }

  String _toDisplayName(String key) {
    return key.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  String _fallbackTitle(List<String> lines) {
    for (final line in lines.take(5)) {
      final trimmed = line.trim();
      if (trimmed.length > 2 && !RegExp(r'^\d+$').hasMatch(trimmed) && !_noiseLineRegex.hasMatch(trimmed)) {
        return trimmed;
      }
    }
    return 'Ticket magasin';
  }

  String _fallbackCategory(List<String> lines) => kCategories.isNotEmpty ? kCategories.first : 'Autre';

  double? _extractTotalAmount(List<String> lines) {
    for (final line in lines) {
      final val = _extractNumber(line);
      if (val != null && val > 0 && val < 10000) return val;
    }
    return null;
  }

  String? _detectLocation(List<String> lines) => null;

  ScannedTicketData _parseRecognizedText(RecognizedText recognizedText) {
    final List<String> lines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        lines.add(line.text);
      }
    }
    final brand = _detectBrand(lines);
    return ScannedTicketData(
      title: brand.name ?? _fallbackTitle(lines),
      amount: _extractTotalAmount(lines),
      date: DateTime.now(),
      category: brand.category ?? _fallbackCategory(lines),
      location: _detectLocation(lines),
      source: TicketSource.local,
    );
  }

  double? _extractNumber(String text) {
    final regExp = RegExp(r'(\d+[\.,]\d{2})');
    final match = regExp.firstMatch(text.replaceAll(' ', ''));
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
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

  void _openManualEntry() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddTransactionScreen(accounts: widget.accounts)),
    ).then((saved) {
      if (saved == true && mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    bool hasKey = (_geminiApiKey != null && _geminiApiKey!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un ticket'),
        actions: [
          IconButton(
            tooltip: 'Configurer la clé API Gemini',
            icon: Icon(
              Icons.key,
              color: hasKey ? AppColors.green : AppColors.textSecondary,
            ),
            onPressed: _openApiKeyDialog,
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- BOUTON DE SÉLECTION AI LOCAL / AI GEMINI ---
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _useGemini = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_useGemini ? AppColors.green.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'AI Locale',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!hasKey) {
                          _openApiKeyDialog();
                        } else {
                          setState(() => _useGemini = true);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _useGemini ? AppColors.green.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'AI Gemini',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (!hasKey) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.lock, size: 14, color: AppColors.textSecondary),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isProcessing
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.green),
                          SizedBox(height: 16),
                          Text(
                            'Analyse du ticket en cours...',
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
                          Text(
                            _useGemini 
                              ? 'Mode IA Gemini activé.\nPrends en photo ton ticket.'
                              : 'Mode IA Locale activé (Hors-ligne).\nPrends en photo ton ticket.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                           const SizedBox(height: 24),
                           ElevatedButton.icon(
                             onPressed: _captureAndProcessTicket,
                             icon: const Icon(Icons.camera_alt),
                             label: const Text('Prendre en photo le ticket'),
                           ),
                           const SizedBox(height: 12),
                           OutlinedButton.icon(
                             onPressed: _pickFromGalleryAndProcessTicket,
                             icon: const Icon(Icons.photo_library_outlined),
                             label: const Text('Importer depuis la galerie'),
                           ),
                           const SizedBox(height: 12),
                           TextButton.icon(
                             onPressed: _openManualEntry,
                             icon: const Icon(Icons.edit_outlined),
                             label: const Text('Ajouter manuellement'),
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
                onPressed: widget.returnScannedData ? _returnScannedData : _openPrefilledEntry,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Informations détectées :',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (ticket.source == TicketSource.ai ? AppColors.green : AppColors.textSecondary).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ticket.source == TicketSource.ai ? 'IA en ligne' : 'Analyse locale',
                  style: TextStyle(
                    color: ticket.source == TicketSource.ai ? AppColors.green : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPreviewRow('Nom / Titre', ticket.title),
          _buildPreviewRow(
            'Montant',
            ticket.amount != null ? '${ticket.amount?.toStringAsFixed(2)} €' : 'Non détecté',
          ),
          _buildPreviewRow(
            'Date',
            ticket.date != null ? '${ticket.date?.day.toString().padLeft(2, '0')}/${ticket.date?.month.toString().padLeft(2, '0')}/${ticket.date?.year}' : 'Non détectée',
          ),
          _buildPreviewRow('Catégorie', ticket.category ?? 'Autre'),
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