import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../screens/scan_ticket_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../models/scanned_ticket_data.dart';

class AddTransactionScreen extends StatefulWidget {
  final List<Account> accounts;
  final LedgerTransaction? initialTransaction;
  final String? initialTitle;
  final double? initialAmount;
  final String? initialCategory;
  final DateTime? initialDate;
  final String? initialNote;
  final String? initialLocation;
  final String? initialReceiptImagePath;

  const AddTransactionScreen({
    super.key,
    required this.accounts,
    this.initialTransaction,
    this.initialTitle,
    this.initialAmount,
    this.initialCategory,
    this.initialDate,
    this.initialNote,
    this.initialLocation,
    this.initialReceiptImagePath,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isIncome = false;
  late String _category;
  Account? _selectedAccount;
  DateTime _date = DateTime.now();
  String? _receiptImagePath;
  bool _isPickingImage = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedAccount = widget.accounts.isNotEmpty
        ? widget.accounts.first
        : null;
    _category = widget.initialCategory ?? kCategories.last;
    _receiptImagePath = widget.initialReceiptImagePath;
    final transaction = widget.initialTransaction;
    if (transaction != null) {
      _titleController.text = transaction.title;
      _amountController.text = transaction.amount.abs().toStringAsFixed(2);
      _isIncome = transaction.amount >= 0;
      _category = transaction.category;
      _date = transaction.date;
      _noteController.text = transaction.note ?? '';
      _locationController.text = transaction.location ?? '';
      _receiptImagePath = transaction.receiptImagePath;
      _selectedAccount = widget.accounts.isNotEmpty
    ?   widget.accounts.firstWhere(
          (a) => a.id == transaction.accountId,
          orElse: () => widget.accounts.first,
      )
    : null;
    } else {
      if (widget.initialTitle != null) {
        _titleController.text = widget.initialTitle!;
      }
      if (widget.initialAmount != null) {
        final amount = widget.initialAmount!;
        _isIncome = amount >= 0;
        _amountController.text = amount.abs().toStringAsFixed(2);
      }
      if (widget.initialDate != null) {
        _date = widget.initialDate!;
      }
      if (widget.initialNote != null) {
        _noteController.text = widget.initialNote!;
      }
      if (widget.initialLocation != null) {
        _locationController.text = widget.initialLocation!;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('fr', 'FR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.green,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          timePickerTheme: TimePickerThemeData(
            dialHandColor: AppColors.green,
            hourMinuteColor: AppColors.card,
            dayPeriodColor: AppColors.card,
          ),
          colorScheme: const ColorScheme.dark(
            primary: AppColors.green,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedTime == null) return;

    setState(() {
      _date = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime date) {
    return DateFormat("dd MMMM yyyy 'à' HH:mm", 'fr_FR').format(date);
  }

  Future<void> _openScanTicketForPrefill() async {
    final scanned = await Navigator.push<ScannedTicketData?>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanTicketScreen(
          accounts: widget.accounts,
          returnScannedData: true,
        ),
      ),
    );
    if (scanned == null) return;

    setState(() {
      _titleController.text = scanned.title;
      if (scanned.amount != null) {
        _amountController.text = scanned.amount!.abs().toStringAsFixed(2);
      }
      _date = scanned.date ?? _date;
      _category = scanned.category ?? _category;
      _isIncome = false;
    });
  }

  Future<String> _copyReceiptFile(File source, String name) async {
    final directory = await getApplicationDocumentsDirectory();
    final extension = name.contains('.')
        ? name.substring(name.lastIndexOf('.'))
        : '.jpg';
    final destination = File(
      '${directory.path}/${StorageService.newId()}$extension',
    );
    return (await source.copy(destination.path)).path;
  }

  Future<void> _setReceiptImage(XFile? file) async {
    if (file == null) return;
    try {
      final savedPath = await _copyReceiptFile(File(file.path), file.name);
      if (!mounted) return;
      if (_receiptImagePath != null && _receiptImagePath != savedPath) {
        final oldFile = File(_receiptImagePath!);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }
      setState(() {
        _receiptImagePath = savedPath;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ajouter la photo du reçu.'),
        ),
      );
    }
  }

  Future<void> _pickReceiptFromGallery() async {
    if (_isPickingImage) return;
    _isPickingImage = true;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      await _setReceiptImage(picked);
    } finally {
      _isPickingImage = false;
    }
  }

  Future<void> _captureReceiptPhoto() async {
    if (_isPickingImage) return;
    _isPickingImage = true;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      await _setReceiptImage(picked);
    } finally {
      _isPickingImage = false;
    }
  }

  Future<void> _showReceiptPicker() async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ajouter un reçu',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.green),
              title: const Text(
                'Prendre une photo',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: AppColors.green),
              title: const Text(
                'Importer depuis la galerie',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == ImageSource.camera) {
      await _captureReceiptPhoto();
    } else if (source == ImageSource.gallery) {
      await _pickReceiptFromGallery();
    }
  }

  Future<void> _clearReceipt() async {
    if (_receiptImagePath == null) return;
    final file = File(_receiptImagePath!);
    if (await file.exists()) {
      await file.delete();
    }
    setState(() {
      _receiptImagePath = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccount == null) return;

    final rawAmount = double.parse(_amountController.text.replaceAll(',', '.'));
    final amount = _isIncome ? rawAmount.abs() : -rawAmount.abs();

    final noteText = _noteController.text.trim();
    final note = noteText.isEmpty ? null : noteText;

    final locationText = _locationController.text.trim();
    final location = locationText.isEmpty ? null : locationText;

    final tx = LedgerTransaction(
      id: widget.initialTransaction?.id ?? StorageService.newId(),
      title: _titleController.text.trim(),
      amount: amount,
      category: _category,
      accountId: _selectedAccount!.id,
      date: _date,
      note: note,
      location: location,
      receiptImagePath: _receiptImagePath,
    );

    if (widget.initialTransaction == null) {
      await StorageService.addTransaction(tx);
    } else {
      await StorageService.updateTransaction(tx);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    // Correction : si aucun compte n'existe, on affiche un message au lieu de
    // planter sur le formulaire (DropdownButtonFormField + widget.accounts.first).
    if (widget.accounts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nouvelle transaction')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 48,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Aucun compte disponible.\nCrée d'abord un compte avant d'ajouter une transaction.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Retour'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialTransaction == null
              ? 'Nouvelle transaction'
              : 'Modifier la transaction',
        ),
        actions: [
          if (widget.accounts.isNotEmpty)
            IconButton(
              onPressed: _openScanTicketForPrefill,
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: 'Scanner un ticket',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Toggle revenu / dépense
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _ToggleButton(
                      label: 'Dépense',
                      color: AppColors.red,
                      selected: !_isIncome,
                      onTap: () => setState(() => _isIncome = false),
                    ),
                  ),
                  Expanded(
                    child: _ToggleButton(
                      label: 'Revenu',
                      color: AppColors.green,
                      selected: _isIncome,
                      onTap: () => setState(() => _isIncome = true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Titre
            TextFormField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Titre',
                hintText: 'Restaurant, Salaire...',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
            ),
            const SizedBox(height: 12),

            // Montant
            TextFormField(
              controller: _amountController,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Montant (€)',
                prefixIcon: Icon(Icons.euro_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Montant requis';
                final parsed = double.tryParse(v.replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Catégorie
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: kCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),

            // Compte
            DropdownButtonFormField<Account>(
              value: _selectedAccount,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Compte'),
              items: widget.accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a,
                      child: Text('${a.type.name}  ${a.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedAccount = v),
            ),
            const SizedBox(height: 12),

            // Date / heure
            ListTile(
              tileColor: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(
                Icons.calendar_today_outlined,
                color: AppColors.green,
              ),
              title: const Text(
                'Date et heure',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _formatDateTime(_date),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 12),

            // Localisation
            TextFormField(
              controller: _locationController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Localisation',
                hintText: 'Ville ou lieu de l\'achat',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Note
            TextFormField(
              controller: _noteController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Référence, commentaire...',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),

            // Reçu (compact)
            _ReceiptSection(
              receiptImagePath: _receiptImagePath,
              onShowPicker: _showReceiptPicker,
              onClear: _clearReceipt,
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                widget.initialTransaction == null
                    ? 'Enregistrer'
                    : 'Modifier',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ReceiptSection extends StatelessWidget {
  final String? receiptImagePath;
  final VoidCallback onShowPicker;
  final VoidCallback onClear;

  const _ReceiptSection({
    this.receiptImagePath,
    required this.onShowPicker,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (receiptImagePath != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(receiptImagePath!),
              fit: BoxFit.cover,
              height: 160,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onShowPicker,
                  icon: const Icon(Icons.photo_camera, size: 18),
                  label: const Text('Changer'),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: onShowPicker,
      icon: const Icon(Icons.photo_camera_back_outlined, size: 20),
      label: const Text('Ajouter un reçu'),
    );
  }
}
