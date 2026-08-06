import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/account_card.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> with TickerProviderStateMixin {
  List<Account> _accounts = [];
  bool _loading = true;

  // Pulsation douce du bouton "+"
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _load();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rawAccounts = await StorageService.getAccounts();
      
      // Filtre les comptes invalides et force le solde à 0 si NaN/Null
      final validAccounts = rawAccounts
          .where((a) => a.name.trim().isNotEmpty)
          .map((a) {
            if (a.balance.isNaN || a.balance.isInfinite) {
              a.balance = 0.0;
            }
            return a;
          }).toList();

      if (!mounted) return;
      setState(() {
        _accounts = validAccounts;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Erreur chargement comptes: $e');
      if (!mounted) return;
      setState(() {
        _accounts = [];
        _loading = false;
      });
    }
  }

  Future<void> _openAddDialog() async {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    AccountType type = AccountType.banque;
    String? nameError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Nouveau compte', style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, val, child) => Opacity(
                  opacity: val,
                  child: Transform.translate(
                    offset: Offset(0, 15 * (1 - val)),
                    child: child,
                  ),
                ),
                child: TextField(
                  controller: nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Nom du compte',
                    errorText: nameError,
                  ),
                  onChanged: (_) {
                    if (nameError != null) {
                      setDialogState(() => nameError = null);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountType>(
                value: type,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Type'),
                items: AccountType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text('${t.emoji} ${t.label}')))
                    .toList(),
                onChanged: (v) => setDialogState(() => type = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(labelText: 'Solde initial (€)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            TextButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  setDialogState(() => nameError = 'Veuillez entrer un nom de compte');
                  return;
                }
                final balance = double.tryParse(balanceController.text.replaceAll(',', '.')) ?? 0;
                await StorageService.upsertAccount(Account(
                  id: StorageService.newId(),
                  name: nameController.text.trim(),
                  type: type,
                  balance: balance,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: const Text('Créer', style: TextStyle(color: AppColors.green)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Account account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Supprimer ce compte ?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${account.name} et toutes ses transactions seront supprimés.',
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
      await StorageService.deleteAccount(account.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('COMPTES'),
      ),
      floatingActionButton: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.elasticOut,
        builder: (context, entrance, child) => Transform.scale(scale: entrance, child: child),
        child: ScaleTransition(
          scale: _pulseAnimation,
          child: FloatingActionButton(
            onPressed: _openAddDialog,
            child: const Icon(Icons.add),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AnimatedBackdrop()),
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.green))
              : _accounts.isEmpty
                  ? Center(
                      child: _StaggeredFadeIn(
                        index: 0,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline, color: AppColors.green, size: 32),
                              SizedBox(height: 12),
                              Text(
                                'Aucun compte. Appuie sur + pour en créer un.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.green,
                      backgroundColor: AppColors.card,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _accounts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final account = _accounts[i];
                          return _StaggeredFadeIn(
                            index: i,
                            child: Dismissible(
                              key: ValueKey(account.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.red.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete_outline, color: AppColors.red),
                              ),
                              confirmDismiss: (_) async {
                                await _confirmDelete(account);
                                return false;
                              },
                              child: AccountCard(account: account),
                            ),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}

/// Animation d'apparition en cascade (fondu + glissement)
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

class _BlobSpec {
  final double size;
  final int seed;
  final Color color;
  final int durationMs;
  final double ampX;
  final double ampY;
  final double freqY;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const _BlobSpec({
    required this.size,
    required this.seed,
    required this.color,
    required this.durationMs,
    required this.ampX,
    required this.ampY,
    required this.freqY,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });
}

class _AnimatedBackdrop extends StatefulWidget {
  const _AnimatedBackdrop();

  @override
  State<_AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<_AnimatedBackdrop> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  static final List<_BlobSpec> _specs = [
    _BlobSpec(
      size: 200, seed: 1, color: AppColors.green.withOpacity(0.16),
      durationMs: 5200, ampX: 70, ampY: 50, freqY: 1.6,
      top: -50, left: -60,
    ),
    _BlobSpec(
      size: 150, seed: 2, color: AppColors.green.withOpacity(0.12),
      durationMs: 6400, ampX: 55, ampY: 65, freqY: 0.8,
      top: 100, right: -40,
    ),
    _BlobSpec(
      size: 230, seed: 3, color: AppColors.green.withOpacity(0.10),
      durationMs: 7600, ampX: 60, ampY: 45, freqY: 1.3,
      bottom: -70, left: 0,
    ),
    _BlobSpec(
      size: 130, seed: 4, color: AppColors.green.withOpacity(0.14),
      durationMs: 4600, ampX: 45, ampY: 55, freqY: 1.9,
      bottom: 60, right: -20,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = _specs
        .map((s) => AnimationController(
              vsync: this,
              duration: Duration(milliseconds: s.durationMs),
            )..repeat())
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: List.generate(_specs.length, (i) {
          final spec = _specs[i];
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (context, _) {
              final t = _controllers[i].value * 2 * math.pi;
              final dx = spec.ampX * math.sin(t + spec.seed);
              final dy = spec.ampY * math.sin(t * spec.freqY);
              final rotation = t * 0.2;
              return Positioned(
                top: spec.top != null ? spec.top! + dy : null,
                bottom: spec.bottom != null ? spec.bottom! - dy : null,
                left: spec.left != null ? spec.left! + dx : null,
                right: spec.right != null ? spec.right! - dx : null,
                child: Transform.rotate(
                  angle: rotation,
                  child: _OrganicBlob(size: spec.size, seed: spec.seed, color: spec.color),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class _OrganicBlob extends StatelessWidget {
  final double size;
  final int seed;
  final Color color;
  const _OrganicBlob({required this.size, required this.seed, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: CustomPaint(
          size: Size(size, size),
          painter: _BlobPainter(seed: seed, color: color),
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final int seed;
  final Color color;
  _BlobPainter({required this.seed, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed * 97);
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    const pointCount = 8;

    final points = <Offset>[];
    for (int i = 0; i < pointCount; i++) {
      final angle = (i / pointCount) * 2 * math.pi;
      final radiusVariance = baseRadius * (0.7 + rng.nextDouble() * 0.55);
      points.add(Offset(
        center.dx + radiusVariance * math.cos(angle),
        center.dy + radiusVariance * math.sin(angle),
      ));
    }

    final path = Path();
    final start = Offset(
      (points[0].dx + points[points.length - 1].dx) / 2,
      (points[0].dy + points[points.length - 1].dy) / 2,
    );
    path.moveTo(start.dx, start.dy);
    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final mid = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.close();

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withOpacity(0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.1));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => false;
}