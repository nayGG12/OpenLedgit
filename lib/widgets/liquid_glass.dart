import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Surface "liquid glass" 100 % Flutter : flou, reflet, bordure lumineuse.
/// Fonctionne sur iOS, Android et web, sans code natif (donc sans crash).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.blur = 18,
    this.tint,
    this.tintOpacity = 0.0,
    this.padding,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final double blur;

  /// Teinte du verre (ex. vert de l'app pour un bouton principal).
  final Color? tint;
  final double tintOpacity;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final base = tint;

    final fill = base == null
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.13),
              Colors.white.withValues(alpha: 0.05),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withValues(alpha: tintOpacity),
              base.withValues(alpha: tintOpacity * 0.72),
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: (base ?? Colors.black).withValues(
                    alpha: base == null ? 0.28 : 0.22,
                  ),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: _GlassRimPainter(radius: radius),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(gradient: fill),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordure fine + reflet spéculaire sur le bord haut, comme le verre d'Apple.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.22),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, rim);

    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.5), sheen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter old) => old.radius != radius;
}

/// Bouton verre avec retour tactile (léger "rebond" + vibration).
class GlassButtonShell extends StatefulWidget {
  const GlassButtonShell({
    super.key,
    required this.onPressed,
    required this.child,
    this.radius = 18,
    this.minHeight = 48,
    this.minWidth = 48,
    this.tint,
    this.tintOpacity = 0.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    this.fill = false,
    this.blur = 14,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double radius;
  final double minHeight;
  final double minWidth;
  final Color? tint;
  final double tintOpacity;
  final EdgeInsetsGeometry padding;

  /// true : le bouton prend toute la largeur disponible.
  final bool fill;
  final double blur;

  @override
  State<GlassButtonShell> createState() => _GlassButtonShellState();
}

class _GlassButtonShellState extends State<GlassButtonShell> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: widget.minHeight,
        minWidth: widget.minWidth,
      ),
      child: Padding(
        padding: widget.padding,
        child: Center(
          widthFactor: widget.fill ? null : 1,
          heightFactor: 1,
          child: widget.child,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: _enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _enabled ? 1 : 0.45,
            duration: const Duration(milliseconds: 150),
            child: GlassSurface(
              radius: widget.radius,
              blur: widget.blur,
              tint: widget.tint,
              tintOpacity: widget.tintOpacity,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre de navigation flottante en verre.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
        child: GlassSurface(
          radius: 34,
          blur: 26,
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () {
                      if (i != currentIndex) HapticFeedback.selectionClick();
                      onTap(i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: selected
                ? AppColors.green.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? AppColors.green.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? item.activeIcon : item.icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
