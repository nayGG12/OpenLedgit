// [source: 5]// [source: 7, 28]
import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/native_liquid_glass_button.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../models/scanned_ticket_data.dart';
import '../screens/add_transaction_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_alert_dialog.dart';
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

  ScannedTicketData? _ticket;
  String? _error;
  bool _isProcessing = false;
  bool _isPickingImage = false;
  String? _capturedImagePath;
  String? _geminiApiKey;

  // Utilisation de l'énumération des trois méthodes
  ScanMethod _selectedMethod = ScanMethod.aiGroq;

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
        // Si aucune clé n'est enregistrée, bascule par défaut sur l'IA locale
        if (key == null || key.isEmpty) {
          _selectedMethod = ScanMethod.aiLocal;
        }
      });
    }
  }

  Future<void> _openApiKeyDialog() async {
    final controller = TextEditingController(text: _geminiApiKey ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'IA visuelle en ligne (Groq)',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Renseigne ta clé API Groq personnelle et gratuite pour une analyse '
              'beaucoup plus fiable (marque, montant, catégorie).',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Clé API Groq'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Clé gratuite à obtenir sur console.groq.com/keys',
              style: TextStyle(color: AppColors.green, fontSize: 12),
            ),
          ],
        ),
        actions: [
          NativeLiquidGlassButton(button: TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          )),
          NativeLiquidGlassButton(button: TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Enregistrer',
              style: TextStyle(color: AppColors.green),
            ),
          )),
        ],
      ),
    );

    if (saved == true) {
      await AISettingsService.setGeminiApiKey(controller.text);
      await _loadApiKey();
    }
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

    try {
      // Appel unifié via AIVisionService avec la méthode choisie
      final result = await AIVisionService.analyzeWithMethod(
        imagePath: pickedFile.path,
        apiKey: _geminiApiKey ?? '',
        method: _selectedMethod,
      );

      if (!mounted) return;
      setState(() {
        _ticket = result;
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint(
        '❌ [ScanTicketScreen] Erreur lors de l\'analyse ($_selectedMethod) : $e',
      );
      if (!mounted) return;
      setState(() {
        _error = 'Erreur d\'analyse : $e';
        _isProcessing = false;
      });
    }
  }

  void _showRawResponsePopup(String rawResponse) {
    showDialog(
      context: context,
      builder: (context) => GlassAlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Détails et réponse brute',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  const Text(
                    'Message d\'erreur :',
                    style: TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Réponse brute / Texte extrait :',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  rawResponse.isEmpty
                      ? 'Aucune donnée brute disponible.'
                      : rawResponse,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          NativeLiquidGlassButton(button: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Fermer',
              style: TextStyle(color: AppColors.green),
            ),
          )),
        ],
      ),
    );
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
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(accounts: widget.accounts),
      ),
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
          NativeLiquidGlassButton(button: IconButton(
            tooltip: 'Configurer la clé API Groq',
            icon: Icon(
              Icons.key,
              color: hasKey ? AppColors.green : AppColors.textSecondary,
            ),
            onPressed: _openApiKeyDialog,
          )),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- SÉLECTEUR DES 3 MÉTHODES (Groq / Local AI / OCR Pur) ---
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // 1. AI Groq
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!hasKey) {
                          _openApiKeyDialog();
                        } else {
                          setState(() => _selectedMethod = ScanMethod.aiGroq);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedMethod == ScanMethod.aiGroq
                              ? AppColors.green.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'AI Groq',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            if (!hasKey) ...[
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.lock,
                                size: 12,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 2. AI Locale
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedMethod = ScanMethod.aiLocal),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedMethod == ScanMethod.aiLocal
                              ? AppColors.green.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'AI Locale',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 3. OCR Pur
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedMethod = ScanMethod.ocrOnly),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedMethod == ScanMethod.ocrOnly
                              ? AppColors.green.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'OCR Brut',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
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
                            _selectedMethod == ScanMethod.aiGroq
                                ? 'Mode IA Groq activé.\nPrends en photo ton ticket.'
                                : _selectedMethod == ScanMethod.aiLocal
                                ? 'Mode IA Locale activé.\nPrends en photo ton ticket.'
                                : 'Mode OCR Brut activé.\nExtraction directe du texte.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          NativeLiquidGlassButton(button: ElevatedButton.icon(
                            onPressed: _captureAndProcessTicket,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Prendre en photo le ticket'),
                          )),
                          const SizedBox(height: 12),
                          NativeLiquidGlassButton(button: OutlinedButton.icon(
                            onPressed: _pickFromGalleryAndProcessTicket,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Importer depuis la galerie'),
                          )),
                          const SizedBox(height: 12),
                          NativeLiquidGlassButton(button: TextButton.icon(
                            onPressed: _openManualEntry,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Ajouter manuellement'),
                          )),
                        ],
                      ),
                    ),
            ),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    NativeLiquidGlassButton(button: TextButton.icon(
                      onPressed: () => _showRawResponsePopup(
                        AIVisionService.lastRawResponse ?? '',
                      ),
                      icon: const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.green,
                      ),
                      label: const Text(
                        'Voir plus de détails (Réponse brute)',
                        style: TextStyle(color: AppColors.green),
                      ),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_ticket != null) ...[
              NativeLiquidGlassButton(button: ElevatedButton.icon(
                onPressed: _captureAndProcessTicket,
                icon: const Icon(Icons.refresh),
                label: const Text('Refaire une photo'),
              )),
              const SizedBox(height: 10),
              NativeLiquidGlassButton(button: ElevatedButton.icon(
                onPressed: widget.returnScannedData
                    ? _returnScannedData
                    : _openPrefilledEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                ),
                icon: const Icon(Icons.check),
                label: const Text('Utiliser ces informations'),
              )),
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
                  color: AppColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedMethod == ScanMethod.aiGroq
                      ? 'IA Groq'
                      : _selectedMethod == ScanMethod.aiLocal
                      ? 'IA Locale'
                      : 'OCR Brut',
                  style: const TextStyle(
                    color: AppColors.green,
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
