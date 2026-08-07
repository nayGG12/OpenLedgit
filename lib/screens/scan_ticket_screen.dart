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
  bool _isPickingImage = false;
  String? _capturedImagePath;

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // Prendre une photo du ticket avec la caméra
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

  // Importer une photo de ticket depuis la galerie
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

  // Analyse l'image sélectionnée ou capturée via la reconnaissance de texte IA
  Future<void> _processTicketImage(XFile pickedFile) async {
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

  // Dictionnaire marque -> catégorie. Clés en minuscules, sans accents (voir _normalize).
  // Ajoute librement de nouvelles enseignes ici : plus la liste est riche, meilleure est la détection.
  static const Map<String, String> _brandCategories = {
    // Alimentation
    'carrefour': 'Alimentation', 'leclerc': 'Alimentation', 'e.leclerc': 'Alimentation',
    'auchan': 'Alimentation', 'intermarche': 'Alimentation', 'lidl': 'Alimentation',
    'aldi': 'Alimentation', 'monoprix': 'Alimentation', 'casino': 'Alimentation',
    'franprix': 'Alimentation', 'super u': 'Alimentation', 'systeme u': 'Alimentation',
    'u express': 'Alimentation', 'cora': 'Alimentation', 'picard': 'Alimentation',
    'biocoop': 'Alimentation', 'naturalia': 'Alimentation', 'grand frais': 'Alimentation',
    'proxi': 'Alimentation', 'spar': 'Alimentation', 'boulangerie': 'Alimentation',
    'patisserie': 'Alimentation', 'mcdonald': 'Alimentation', 'burger king': 'Alimentation',
    'kfc': 'Alimentation', 'quick': 'Alimentation', 'subway': 'Alimentation',
    'starbucks': 'Alimentation', 'brioche doree': 'Alimentation', 'paul': 'Alimentation',
    // Transport
    'total': 'Transport', 'totalenergies': 'Transport', 'esso': 'Transport',
    'shell': 'Transport', 'bp ': 'Transport', 'avia': 'Transport', 'sncf': 'Transport',
    'ratp': 'Transport', 'uber': 'Transport', 'blablacar': 'Transport',
    'vinci autoroutes': 'Transport', 'aprr': 'Transport', 'sanef': 'Transport',
    'flixbus': 'Transport', 'indigo park': 'Transport', 'europcar': 'Transport',
    // Shopping
    'fnac': 'Shopping', 'darty': 'Shopping', 'boulanger': 'Shopping', 'amazon': 'Shopping',
    'cdiscount': 'Shopping', 'zara': 'Shopping', 'h&m': 'Shopping', 'uniqlo': 'Shopping',
    'decathlon': 'Shopping', 'la redoute': 'Shopping', 'sephora': 'Shopping',
    'zalando': 'Shopping', 'ikea': 'Shopping',
    // Logement
    'leroy merlin': 'Logement', 'castorama': 'Logement', 'brico depot': 'Logement',
    'bricomarche': 'Logement', 'weldom': 'Logement', 'but ': 'Logement',
    'conforama': 'Logement', 'edf': 'Logement', 'engie': 'Logement', 'veolia': 'Logement',
    // Santé
    'pharmacie': 'Santé', 'parapharmacie': 'Santé',
    // Abonnements
    'free mobile': 'Abonnements', 'orange': 'Abonnements', 'sfr': 'Abonnements',
    'bouygues telecom': 'Abonnements', 'netflix': 'Abonnements', 'spotify': 'Abonnements',
    'disney+': 'Abonnements', 'canal+': 'Abonnements',
  };

  // Mots-clés génériques utilisés en secours quand la marque n'est pas reconnue directement.
  static const Map<String, List<String>> _categoryKeywordFallback = {
    'Alimentation': ['supermarche', 'boulangerie', 'boucherie', 'epicerie', 'primeur', 'fromagerie', 'restaurant', 'brasserie', 'traiteur'],
    'Transport': ['essence', 'carburant', 'peage', 'parking', 'gazole', 'sans plomb', 'taxi', 'station service'],
    'Santé': ['pharmacie', 'medecin', 'dentiste', 'opticien', 'mutuelle'],
    'Logement': ['bricolage', 'quincaillerie', 'jardinerie', 'meuble', 'electromenager'],
    'Loisirs': ['cinema', 'theatre', 'concert', 'billetterie', 'musee'],
    'Shopping': ['vetement', 'chaussure', 'pret a porter', 'bijouterie'],
  };

  // Lignes à ignorer lors de la recherche du nom de l'enseigne / du montant
  // (numéros de téléphone, SIRET, TVA...), pour ne pas les confondre avec un prix.
  static final RegExp _noiseLineRegex = RegExp(
    r'siret|siren|rcs|tva\s*intra|n[°o]\s*tva|tel\s*[:.]|t[ée]l[ée]phone|caissier|caisse\s*n|ticket\s*n',
    caseSensitive: false,
  );

  /// Enlève les accents et met en minuscules pour faciliter les comparaisons.
  String _normalize(String text) {
    const withAccents = 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ';
    const withoutAccents = 'aaaeeeeiioouucAAAEEEEIIOOUUC';
    var result = text.toLowerCase();
    for (var i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result.trim();
  }

  /// Détecte la marque/enseigne en scannant tout le ticket (pas seulement l'en-tête,
  /// car le nom du magasin apparaît parfois dans le pied de page "Merci de votre visite chez...").
  /// Retourne le nom affiché (joliment formaté) et la catégorie associée si connue.
  ({String? name, String? category}) _detectBrand(List<String> lines) {
    for (final line in lines) {
      final normalized = _normalize(line);
      for (final entry in _brandCategories.entries) {
        if (normalized.contains(entry.key.trim())) {
          return (name: _toDisplayName(entry.key.trim()), category: entry.value);
        }
      }
    }
    return (name: null, category: null);
  }

  String _toDisplayName(String key) {
    return key
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Repli si aucune marque connue n'est reconnue : on prend la première ligne
  /// exploitable du ticket (généralement le nom du commerçant en haut du reçu).
  String _fallbackTitle(List<String> lines) {
    for (final line in lines.take(5)) {
      final trimmed = line.trim();
      if (trimmed.length > 2 &&
          !RegExp(r'^\d+$').hasMatch(trimmed) &&
          !_noiseLineRegex.hasMatch(trimmed)) {
        return trimmed;
      }
    }
    return 'Ticket magasin';
  }

  /// Devine une catégorie à partir de mots-clés génériques quand la marque est inconnue.
  String _fallbackCategory(List<String> lines) {
    final fullText = _normalize(lines.join(' '));
    for (final entry in _categoryKeywordFallback.entries) {
      if (entry.value.any((kw) => fullText.contains(kw))) {
        return entry.key;
      }
    }
    return 'Autre';
  }

  // Mots-clés du montant total, du plus précis/fiable au plus générique.
  // "sous-total" est explicitement exclu pour ne pas être confondu avec "total".
  static const List<String> _totalKeywordsPriority = [
    'net a payer',
    'montant total',
    'total ttc',
    'total a payer',
    'a payer',
    'total',
  ];

  /// Cherche le montant total en priorisant les libellés les plus fiables,
  /// et en ignorant explicitement les lignes de sous-total, TVA, SIRET, etc.
  double? _extractTotalAmount(List<String> lines) {
    for (final keyword in _totalKeywordsPriority) {
      for (var i = 0; i < lines.length; i++) {
        final normalized = _normalize(lines[i]);
        if (normalized.contains('sous total') ||
            normalized.contains('sous-total') ||
            normalized.contains('soustotal') ||
            _noiseLineRegex.hasMatch(lines[i])) {
          continue;
        }
        if (normalized.contains(keyword)) {
          // Le montant est parfois sur la même ligne, parfois sur la ligne suivante.
          var found = _extractNumber(lines[i]);
          if (found == null && i + 1 < lines.length) {
            found = _extractNumber(lines[i + 1]);
          }
          if (found != null && found > 0 && found < 10000) {
            return found;
          }
        }
      }
    }
    return null;
  }

  /// Repère un code postal + ville (ex: "75001 PARIS") pour identifier la localisation du ticket.
  String? _detectLocation(List<String> lines) {
    final regExp = RegExp(r'\b(\d{5})\s+([A-ZÀ-Ü][A-Za-zÀ-ÿ\-\s]{1,25})\b');
    for (final line in lines) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        return '${match.group(1)} ${match.group(2)!.trim()}';
      }
    }
    return null;
  }

  // Algorithme d'extraction intelligent basé sur le texte brut du ticket
  ScannedTicketData _parseRecognizedText(RecognizedText recognizedText) {
    DateTime? date;

    final List<String> lines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        lines.add(line.text);
      }
    }

    for (final line in lines) {
      date ??= _parseDate(line);
    }

    // 1. On cherche en priorité une marque/enseigne connue -> titre + catégorie fiables.
    final brand = _detectBrand(lines);
    final title = brand.name ?? _fallbackTitle(lines);
    final category = brand.category ?? _fallbackCategory(lines);

    // 2. Montant total : recherche ciblée par mots-clés, avec repli sur le plus gros prix du ticket.
    double? amount = _extractTotalAmount(lines);
    if (amount == null) {
      double maxVal = 0.0;
      for (final line in lines) {
        if (_noiseLineRegex.hasMatch(line)) continue;
        final val = _extractNumber(line);
        if (val != null && val > maxVal && val < 5000) {
          maxVal = val;
        }
      }
      if (maxVal > 0) amount = maxVal;
    }

    // 3. Localisation (facultative, affichée dans l'aperçu pour vérification).
    final location = _detectLocation(lines);

    return ScannedTicketData(
      title: title,
      amount: amount,
      date: date ?? DateTime.now(),
      category: category,
      location: location,
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

  void _openManualEntry() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          accounts: widget.accounts,
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
                           const SizedBox(height: 12),
                           OutlinedButton.icon(
                             onPressed: _pickFromGalleryAndProcessTicket,
                             icon: const Icon(Icons.photo_library_outlined),
                             label: const Text('Importer une photo depuis la galerie'),
                           ),
                           const SizedBox(height: 12),
                           TextButton.icon(
                             onPressed: _openManualEntry,
                             icon: const Icon(Icons.edit_outlined),
                             label: const Text('Ajouter les informations manuellement'),
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
              OutlinedButton.icon(
                onPressed: _pickFromGalleryAndProcessTicket,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Importer une autre photo'),
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
          if (ticket.location != null) _buildPreviewRow('Lieu détecté', ticket.location!),
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
  final String? location;

  const ScannedTicketData({
    required this.title,
    this.date,
    this.amount,
    this.category,
    this.location,
  });
}