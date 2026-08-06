import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/export_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmWipe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Tout effacer ?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Toutes tes données locales (comptes et transactions) seront définitivement supprimées. '
          'Pense à exporter une sauvegarde avant si besoin.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Tout effacer',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _run(
        StorageService.wipeAll,
        successMessage: 'Données réinitialisées.',
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Se déconnecter ?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Tu devras te reconnecter pour retrouver ton compte. Tes données locales restent sur cet appareil.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Se déconnecter',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _run(FirebaseAuth.instance.signOut);
      // Un StreamBuilder<User?> sur FirebaseAuth.instance.authStateChanges()
      // à la racine de l'app doit basculer automatiquement vers l'écran de
      // connexion une fois la déconnexion effectuée. Si ce n'est pas le cas
      // dans ton projet, remplace la ligne ci-dessus par un Navigator vers
      // ton écran de login, par ex. :
      // Navigator.of(context).pushAndRemoveUntil(
      //   MaterialPageRoute(builder: (_) => const LoginScreen()),
      //   (route) => false,
      // );
    }
  }

  Future<void> _editDisplayName() async {
    final currentName = await StorageService.getUserFullName() ?? '';
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Modifier le nom',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(labelText: 'Nom complet'),
            validator: (value) {
              if (value == null || value.trim().isEmpty)
                return 'Le nom complet est requis.';
              if (value.trim().split(' ').length < 2)
                return 'Entrer nom et prénom.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text(
              'Enregistrer',
              style: TextStyle(color: AppColors.green),
            ),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final newName = controller.text.trim();
    await _run(() async {
      await StorageService.saveUserFullName(newName);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(newName);
      }
    }, successMessage: 'Nom mis à jour.');
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Changer le mot de passe',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Nouveau mot de passe',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty)
                return 'Mot de passe requis.';
              if (value.trim().length < 6) return 'Au moins 6 caractères.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text(
              'Modifier',
              style: TextStyle(color: AppColors.green),
            ),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    final newPassword = controller.text.trim();
    await _run(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Aucun utilisateur connecté.';
      await user.updatePassword(newPassword);
    }, successMessage: 'Mot de passe modifié.');
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Supprimer le compte ?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Ton compte OpenLedger sera supprimé de Firebase et toutes les données locales seront effacées.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _run(() async {
      await StorageService.wipeAll();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.delete();
      }
    }, successMessage: 'Compte supprimé.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('PARAMÈTRES'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AnimatedBackdrop()),
          AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _StaggeredFadeIn(
                  index: 0,
                  child: const _SectionTitle('Mes données, mon choix'),
                ),
                _StaggeredFadeIn(
                  index: 1,
                  child: _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.download_outlined,
                        title: 'Exporter en JSON',
                        subtitle:
                            'Sauvegarde complète (comptes + transactions)',
                        onTap: () =>
                            _run(() => ExportService.exportJson(context)),
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.table_chart_outlined,
                        title: 'Exporter en CSV',
                        subtitle: 'Transactions, compatible tableur',
                        onTap: () =>
                            _run(() => ExportService.exportCsv(context)),
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.upload_outlined,
                        title: 'Importer une sauvegarde',
                        subtitle:
                            'Restaure un fichier JSON exporté depuis OpenLedger',
                        onTap: () => _run(() async {
                          final ok = await ExportService.importJsonFromPicker();
                          if (!ok) throw 'Import annulé ou fichier invalide';
                        }, successMessage: 'Sauvegarde importée avec succès.'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _StaggeredFadeIn(
                  index: 2,
                  child: const _SectionTitle('Confidentialité'),
                ),
                _StaggeredFadeIn(
                  index: 3,
                  child: _SettingsCard(
                    children: [
                      const _SettingsTile(
                        icon: Icons.wifi_off_outlined,
                        title: 'Mode hors ligne',
                        subtitle:
                            'Toutes tes données restent sur cet appareil, aucun serveur requis',
                        onTap: null,
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.delete_forever_outlined,
                        title: 'Réinitialiser toutes les données',
                        subtitle: 'Efface comptes et transactions',
                        danger: true,
                        onTap: _confirmWipe,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _StaggeredFadeIn(
                  index: 4,
                  child: const _SectionTitle('Compte'),
                ),
                _StaggeredFadeIn(
                  index: 5,
                  child: _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.person_outline,
                        title: 'Modifier le nom',
                        subtitle: 'Changer le nom qui s\'affiche dans l\'app',
                        onTap: _editDisplayName,
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.lock_outline,
                        title: 'Changer le mot de passe',
                        subtitle: 'Mets à jour le mot de passe de connexion',
                        onTap: _changePassword,
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.delete_outline,
                        title: 'Supprimer mon compte',
                        subtitle:
                            'Supprime ton compte Firebase et les données locales',
                        danger: true,
                        onTap: _confirmDeleteAccount,
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.logout,
                        title: 'Se déconnecter',
                        subtitle: 'Ferme la session en cours sur cet appareil',
                        danger: true,
                        onTap: _confirmLogout,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _StaggeredFadeIn(
                  index: 6,
                  child: const _SectionTitle('À propos'),
                ),
                _StaggeredFadeIn(
                  index: 7,
                  child: _SettingsCard(
                    children: [
                      const _SettingsTile(
                        icon: Icons.info_outline,
                        title: 'OpenLedger',
                        subtitle:
                            '"Your money. Your data." — v1.0.0 · Licence MIT',
                        onTap: null,
                      ),
                      const Divider(height: 1),
                      _SettingsTile(
                        icon: Icons.code,
                        title: 'Code source',
                        subtitle: 'github.com/OpenLedger-App',
                        onTap: () => launchUrl(
                          Uri.parse('https://github.com/OpenLedger-App'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 24),
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.green),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(child: Column(children: children));
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : AppColors.green;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: onTap != null
          ? const Icon(Icons.chevron_right, color: AppColors.textSecondary)
          : null,
      onTap: onTap,
    );
  }
}

/// Animation d'apparition en fondu et glissement en cascade
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
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Délai progressif pour chaque bloc/option
    final delay = Duration(milliseconds: 60 * widget.index.clamp(0, 20));
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
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
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

class _AnimatedBackdropState extends State<_AnimatedBackdrop>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  static final List<_BlobSpec> _specs = [
    _BlobSpec(
      size: 200,
      seed: 1,
      color: AppColors.green.withOpacity(0.16),
      durationMs: 5200,
      ampX: 70,
      ampY: 50,
      freqY: 1.6,
      top: -50,
      left: -60,
    ),
    _BlobSpec(
      size: 150,
      seed: 2,
      color: AppColors.green.withOpacity(0.12),
      durationMs: 6400,
      ampX: 55,
      ampY: 65,
      freqY: 0.8,
      top: 100,
      right: -40,
    ),
    _BlobSpec(
      size: 230,
      seed: 3,
      color: AppColors.green.withOpacity(0.10),
      durationMs: 7600,
      ampX: 60,
      ampY: 45,
      freqY: 1.3,
      bottom: -70,
      left: 0,
    ),
    _BlobSpec(
      size: 130,
      seed: 4,
      color: AppColors.green.withOpacity(0.14),
      durationMs: 4600,
      ampX: 45,
      ampY: 55,
      freqY: 1.9,
      bottom: 60,
      right: -20,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = _specs
        .map(
          (s) => AnimationController(
            vsync: this,
            duration: Duration(milliseconds: s.durationMs),
          )..repeat(),
        )
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
                  child: _OrganicBlob(
                    size: spec.size,
                    seed: spec.seed,
                    color: spec.color,
                  ),
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
  const _OrganicBlob({
    required this.size,
    required this.seed,
    required this.color,
  });

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
      points.add(
        Offset(
          center.dx + radiusVariance * math.cos(angle),
          center.dy + radiusVariance * math.sin(angle),
        ),
      );
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
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
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
