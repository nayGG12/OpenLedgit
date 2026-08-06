import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class TransactionDetailScreen extends StatefulWidget {
  final LedgerTransaction transaction;
  final String accountName;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    required this.accountName,
  });

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _blur;
  late final Animation<double> _rotation;
  bool _deleting = false;

  static const List<String> _days = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche',
  ];
  static const List<String> _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _blur = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );
    _rotation = Tween<double>(begin: -0.03, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final day = _days[d.weekday - 1];
    final month = _months[d.month - 1];
    return '$day ${d.day} $month ${d.year}';
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Supprimer cette transaction ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          widget.transaction.title,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _deleting = true);
      await StorageService.deleteTransaction(widget.transaction.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final isIncome = tx.amount >= 0;
    final color = isIncome ? AppColors.green : AppColors.red;
    final formatter = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Détail de la transaction'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
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
              child: Transform.rotate(
                angle: _rotation.value,
                child: Transform.scale(scale: _scale.value, child: content),
              ),
            );
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.4, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) => Transform.scale(
                      scale: value,
                      child: child,
                    ),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: color,
                        size: 38,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: tx.amount),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Text(
                      formatter.format(value),
                      style: TextStyle(
                        color: color,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    tx.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _DetailCard(children: [
                  _StaggeredFadeIn(
                    index: 0,
                    child: _DetailRow(icon: Icons.category_outlined, label: 'Catégorie', value: tx.category),
                  ),
                  _StaggeredFadeIn(
                    index: 1,
                    child: _DetailRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Compte',
                      value: widget.accountName,
                    ),
                  ),
                  _StaggeredFadeIn(
                    index: 2,
                    child: _DetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date',
                      value: _formatDate(tx.date),
                    ),
                  ),
                  if (tx.note != null && tx.note!.isNotEmpty)
                    _StaggeredFadeIn(
                      index: 3,
                      child: _DetailRow(icon: Icons.notes_outlined, label: 'Note', value: tx.note!),
                    ),
                ]),
                const SizedBox(height: 40),
                _StaggeredFadeIn(
                  index: 4,
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _deleting ? null : _confirmDelete,
                      icon: _deleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.red),
                            )
                          : const Icon(Icons.delete_outline, color: AppColors.red),
                      label: Text(
                        _deleting ? 'Suppression...' : 'Supprimer la transaction',
                        style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.red, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.green, size: 20),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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

    final delay = Duration(milliseconds: 100 * widget.index.clamp(0, 24));
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