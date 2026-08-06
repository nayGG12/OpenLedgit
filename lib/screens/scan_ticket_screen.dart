import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/account.dart';
import '../screens/add_transaction_screen.dart';
import '../theme/app_theme.dart';

class ScanTicketScreen extends StatefulWidget {
  const ScanTicketScreen({super.key, required this.accounts});

  final List<Account> accounts;

  @override
  State<ScanTicketScreen> createState() => _ScanTicketScreenState();
}

class _ScanTicketScreenState extends State<ScanTicketScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  ScannedTicketData? _ticket;
  String? _error;
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || _ticket != null) return;
    final barcode = capture.barcodes.firstWhere(
      (item) => item.rawValue != null,
      orElse: () => Barcode(rawValue: null),
    );
    final payload = barcode.rawValue;
    if (payload == null || payload.trim().isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final parsed = _parseTicketPayload(payload);
      setState(() {
        _ticket = parsed;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error =
            'Impossible de lire ce ticket. Essaie à nouveau ou saisis les informations manuellement.';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  ScannedTicketData _parseTicketPayload(String payload) {
    final normalized = payload.replaceAll(RegExp(r'[\r\n]+'), ';').trim();

    String? city;
    DateTime? date;
    double? amount;
    String? category;
    String title = 'Ticket';

    // JSON structured payload
    if (normalized.startsWith('{') || normalized.startsWith('[')) {
      final dynamic json = jsonDecode(normalized);
      if (json is Map<String, dynamic>) {
        city = _extractString(json, ['ville', 'city', 'location', 'lieu']);
        category = _extractString(json, ['categorie', 'category', 'type']);
        amount = _extractNumber(json, ['montant', 'amount', 'total', 'price']);
        date = _extractDate(json, ['date']);
      }
    }

    for (final part in normalized.split(RegExp(r'[;|,]'))) {
      final item = part.trim();
      if (item.isEmpty) continue;

      if (city == null &&
          RegExp(r'^(ville|city)\s*[:\-=]').hasMatch(item.toLowerCase())) {
        city = item.split(RegExp(r'[:\-=]'))[1].trim();
        continue;
      }
      if (category == null &&
          RegExp(
            r'^(categorie|category|type)\s*[:\-=]',
          ).hasMatch(item.toLowerCase())) {
        category = item.split(RegExp(r'[:\-=]'))[1].trim();
        continue;
      }
      if (amount == null &&
          RegExp(
            r'^(montant|amount|total|price)\s*[:\-=]',
          ).hasMatch(item.toLowerCase())) {
        final value = _extractNumberFromString(item);
        if (value != null) amount = value;
        continue;
      }
      if (date == null &&
          RegExp(r'^(date)\s*[:\-=]').hasMatch(item.toLowerCase())) {
        final value = item.split(RegExp(r'[:\-=]'))[1].trim();
        date = _parseDate(value);
        continue;
      }

      if (city == null && _looksLikeCity(item)) {
        city = item;
        continue;
      }
      if (date == null) {
        final maybeDate = _parseDate(item);
        if (maybeDate != null) {
          date = maybeDate;
          continue;
        }
      }
      if (amount == null) {
        final maybeAmount = _extractNumberFromString(item);
        if (maybeAmount != null) {
          amount = maybeAmount;
          continue;
        }
      }
      if (category == null) {
        final maybeCategory = _matchKnownCategory(item);
        if (maybeCategory != null) {
          category = maybeCategory;
          continue;
        }
      }
    }

    if (amount != null) {
      title = 'Ticket ${city ?? ''}'.trim();
    } else {
      title = 'Nouveau ticket';
    }

    return ScannedTicketData(
      title: title,
      location: city,
      date: date,
      amount: amount,
      category: category,
    );
  }

  String? _extractString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  double? _extractNumber(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  DateTime? _extractDate(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String) {
        final date = _parseDate(value);
        if (date != null) return date;
      }
    }
    return null;
  }

  DateTime? _parseDate(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s\ufffd]'), '').trim();
    try {
      return DateTime.parse(cleaned);
    } catch (_) {}

    final regex = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$');
    final match = regex.firstMatch(cleaned);
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

  double? _extractNumberFromString(String raw) {
    final regex = RegExp(r'([0-9]+[.,][0-9]{2})');
    final match = regex.firstMatch(raw.replaceAll(' ', ''));
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    return null;
  }

  bool _looksLikeCity(String text) {
    return RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ\s\-]{3,}$').hasMatch(text) &&
        text.length < 40;
  }

  String? _matchKnownCategory(String text) {
    final lower = text.toLowerCase();
    for (final category in kCategories) {
      if (lower.contains(category.toLowerCase())) return category;
    }
    return null;
  }

  void _openManualEntry() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(accounts: widget.accounts.cast()),
      ),
    ).then((saved) {
      if (saved == true && mounted) Navigator.pop(context, true);
    });
  }

  void _openPrefilledEntry() {
    if (_ticket == null) return;
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          accounts: widget.accounts.cast(),
          initialTitle: _ticket!.title,
          initialLocation: _ticket!.location,
          initialAmount: _ticket!.amount,
          initialCategory: _ticket!.category,
          initialDate: _ticket!.date,
        ),
      ),
    ).then((saved) {
      if (saved == true && mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un ticket'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Redémarrer le scanner',
            onPressed: () {
              setState(() {
                _ticket = null;
                _error = null;
              });
              _scannerController.start();
            },
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: _ticket != null
                ? _buildPreviewCard()
                : MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_ticket == null) ...[
                  const Text(
                    'Place un QR/code-barres contenant les informations du ticket dans le cadre, ou appuie sur "Saisir manuellement".',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.red)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _openManualEntry,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Saisir manuellement'),
                ),
                if (_ticket != null) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _openPrefilledEntry,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Importer les infos du ticket'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    final ticket = _ticket!;
    return Container(
      width: double.infinity,
      color: AppColors.card,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ticket repéré',
            style: TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildPreviewRow('Titre', ticket.title),
          _buildPreviewRow('Ville', ticket.location ?? 'Non détectée'),
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
          _buildPreviewRow('Catégorie', ticket.category ?? 'Non détectée'),
          const SizedBox(height: 24),
          const Text(
            'Tu peux corriger les valeurs avant d’enregistrer la transaction.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Text(value, style: const TextStyle(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class ScannedTicketData {
  final String title;
  final String? location;
  final DateTime? date;
  final double? amount;
  final String? category;

  const ScannedTicketData({
    required this.title,
    this.location,
    this.date,
    this.amount,
    this.category,
  });
}
