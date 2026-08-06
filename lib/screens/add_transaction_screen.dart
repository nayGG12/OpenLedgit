import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

// Définition de la liste des catégories par défaut si elle n'existe pas ailleurs
const List<String> kCategories = [
  'Alimentation',
  'Loisirs',
  'Logement',
  'Transport',
  'Santé',
  'Revenu',
  'Autre',
];

class AddTransactionScreen extends StatefulWidget {
  final List<Account> accounts;
  const AddTransactionScreen({super.key, required this.accounts});

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

  @override
  void initState() {
    super.initState();
    // Correction : on évite le crash "Bad state: No element" si la liste est vide.
    _selectedAccount = widget.accounts.isNotEmpty ? widget.accounts.first : null;
    _category = kCategories.last; // "Autre" par défaut
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
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
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccount == null) return;

    final rawAmount = double.parse(_amountController.text.replaceAll(',', '.'));
    final amount = _isIncome ? rawAmount.abs() : -rawAmount.abs();

    final tx = LedgerTransaction(
      id: StorageService.newId(),
      title: _titleController.text.trim(),
      amount: amount,
      category: _category,
      accountId: _selectedAccount!.id,
      date: _date,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    await StorageService.addTransaction(tx);
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
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 48, color: AppColors.textSecondary),
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
      appBar: AppBar(title: const Text('Nouvelle transaction')),
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
                decoration: const InputDecoration(labelText: 'Titre (ex: Restaurant, Salaire...)'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 2,
              child: TextFormField(
                controller: _amountController,
                style: const TextStyle(color: AppColors.textPrimary),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              index: 4,
              child: DropdownButtonFormField<Account>(
                value: _selectedAccount,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Compte'),
                items: widget.accounts
                    .map((a) => DropdownMenuItem(value: a, child: Text('${a.type.name}  ${a.name}')))
                    .toList(),
                onChanged: (v) => setState(() => _selectedAccount = v),
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 5,
              child: ListTile(
                tileColor: AppColors.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.calendar_today_outlined, color: AppColors.green),
                title: Text(
                  '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 14),
            _StaggeredFadeIn(
              index: 6,
              child: TextFormField(
                controller: _noteController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Note (optionnel)'),
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 28),
            _StaggeredFadeIn(
              index: 7,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Enregistrer'),
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
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
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

class _StaggeredFadeInState extends State<_StaggeredFadeIn> with SingleTickerProviderStateMixin {
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
    _slideY = Tween<double>(begin: 46, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _rotation = Tween<double>(begin: -0.05, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
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
            imageFilter: ui.ImageFilter.blur(sigmaX: _blur.value, sigmaY: _blur.value),
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