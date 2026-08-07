import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _initializeApp();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _SplashBackground(animation: _backgroundController),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: MediaQuery.of(context).size.width * 0.28,
                  height: MediaQuery.of(context).size.width * 0.28,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.green, width: 2),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.account_balance_wallet,
                      size: MediaQuery.of(context).size.width * 0.16,
                      color: AppColors.green,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'OPENLEDGER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'v5.2.5',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 36),
                const CircularProgressIndicator(color: AppColors.green),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashBackground extends StatefulWidget {
  final Animation<double> animation;
  const _SplashBackground({required this.animation});

  @override
  State<_SplashBackground> createState() => _SplashBackgroundState();
}

class _SplashBackgroundState extends State<_SplashBackground> {
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _initializeParticles();
  }

  void _initializeParticles() {
    final random = math.Random(42);
    _particles.clear();
    for (var i = 0; i < 28; i++) {
      _particles.add(
        _Particle(
          x: random.nextDouble(),
          size: 2 + random.nextDouble() * 4,
          delay: random.nextDouble(),
          duration: 6 + random.nextDouble() * 6,
          color: random.nextBool() ? AppColors.green : AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(offset: widget.animation.value),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _ScanlinePainter(progress: widget.animation.value),
              ),
            ),
            ..._particles.map((particle) {
              final progress =
                  ((widget.animation.value + particle.delay) % 1.0) /
                  (particle.duration / 8.0);
              final normalized = progress.clamp(0.0, 1.0);
              return Positioned(
                left: particle.x * size.width,
                top: size.height * (1.1 - normalized * 1.4),
                child: Opacity(
                  opacity: 0.6 - normalized * 0.5,
                  child: Container(
                    width: particle.size,
                    height: particle.size,
                    decoration: BoxDecoration(
                      color: particle.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: particle.color.withOpacity(0.8),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final double offset;
  const _GridPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.green.withOpacity(0.08)
      ..strokeWidth = 1;

    const step = 42.0;
    final dx = (offset * step) % step;
    final dy = (offset * step) % step;

    for (var x = -step; x < size.width + step; x += step) {
      canvas.drawLine(Offset(x + dx, 0), Offset(x + dx, size.height), paint);
    }
    for (var y = -step; y < size.height + step; y += step) {
      canvas.drawLine(Offset(0, y + dy), Offset(size.width, y + dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.offset != offset;
  }
}

class _ScanlinePainter extends CustomPainter {
  final double progress;
  const _ScanlinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final scanHeight = 140.0;
    final top = (size.height + scanHeight) * progress - scanHeight;
    final rect = Rect.fromLTWH(0, top, size.width, scanHeight);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          AppColors.green.withOpacity(0.08),
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.drawRect(rect, paint);

    final linePaint = Paint()
      ..color = AppColors.green.withOpacity(0.18)
      ..strokeWidth = 0.8;

    canvas.drawLine(
      Offset(0, top + scanHeight * 0.35),
      Offset(size.width, top + scanHeight * 0.35),
      linePaint,
    );
    canvas.drawLine(
      Offset(0, top + scanHeight * 0.65),
      Offset(size.width, top + scanHeight * 0.65),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _Particle {
  final double x;
  final double size;
  final double delay;
  final double duration;
  final Color color;

  _Particle({
    required this.x,
    required this.size,
    required this.delay,
    required this.duration,
    required this.color,
  });
}
