import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../screens/scan_ticket_screen.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

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

  bool _isIncome = false;
  late String _category;
  Account? _selectedAccount;
  DateTime _date = DateTime.now();
  String? _receiptImagePath;
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
      _receiptImagePath = transaction.receiptImagePath;
      _selectedAccount = widget.accounts.firstWhere(
        (a) => a.id == transaction.accountId,
        orElse: () => widget.accounts.first,
      );
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
      } else if (widget.initialLocation != null) {
        _noteController.text = 'Ville : ${widget.initialLocation!}';
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
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
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    await _setReceiptImage(picked);
  }

  Future<void> _captureReceiptPhoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    await _setReceiptImage(picked);
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
    final note = noteText.isEmpty && widget.initialLocation != null
        ? 'Ville : ${widget.initialLocation!}'
        : noteText.isEmpty
        ? null
        : noteText;

    final tx = LedgerTransaction(
      id: widget.initialTransaction?.id ?? StorageService.newId(),
      title: _titleController.text.trim(),
      amount: amount,
      category: _category,
      accountId: _selectedAccount!.id,
      date: _date,
      note: note,
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
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Toggle revenu / dépense
            _StaggeredFadeIn(
              index: 0,
              child: Container(
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
            ),
            const SizedBox(height: 20),
            _StaggeredFadeIn(
              index: 1,
              child: TextFormField(
                controller: _titleController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Titre (ex: Restaurant, Salaire...)',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 2,
              child: TextFormField(
                controller: _amountController,
                style: const TextStyle(color: AppColors.textPrimary),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Montant (€)'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Montant requis';
                  final parsed = double.tryParse(v.replaceAll(',', '.'));
                  if (parsed == null || parsed <= 0) return 'Montant invalide';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 3,
              child: ElevatedButton.icon(
                onPressed: _openScanTicketForPrefill,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scanner un ticket pour pré-remplir'),
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 4,
              child: DropdownButtonFormField<String>(
                value: _category,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: kCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 5,
              child: DropdownButtonFormField<Account>(
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
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 6,
              child: ListTile(
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
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 7,
              child: TextFormField(
                controller: _noteController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Note (optionnel)',
                  hintText: 'Par exemple Ville, référence du ticket...',
                ),
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Reçu',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_receiptImagePath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          File(_receiptImagePath!),
                          fit: BoxFit.cover,
                          height: 180,
                          width: double.infinity,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _clearReceipt,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Supprimer'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _captureReceiptPhoto,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Prendre une photo'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const Text(
                        'Ajoute une photo de ton ticket pour garder une trace visuelle.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickReceiptFromGallery,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Importer'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _captureReceiptPhoto,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Photo'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            _StaggeredFadeIn(
              index: 9,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(
                  widget.initialTransaction == null
                      ? 'Enregistrer'
                      : 'Modifier',
                ),
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

/// Animation d'apparition en cascade : flou qui se dissipe, zoom élastique
/// avec léger rebond, petite rotation de "pose", et glissement vers le haut.
class _StaggeredFadeIn extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredFadeIn({required this.index, required this.child});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slideY;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;
  late final Animation<double> _blur;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _slideY = Tween<double>(
      begin: 46,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _scale = Tween<double>(
      begin: 0.72,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _rotation = Tween<double>(
      begin: -0.05,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _blur = Tween<double>(begin: 8.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );

    final delay = Duration(milliseconds: 90 * widget.index.clamp(0, 24));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        Widget content = child!;
        if (_blur.value > 0.05) {
          content = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _blur.value,
              sigmaY: _blur.value,
            ),
            child: content,
          );
        }
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, _slideY.value),
            child: Transform.rotate(
              angle: _rotation.value,
              child: Transform.scale(scale: _scale.value, child: content),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
