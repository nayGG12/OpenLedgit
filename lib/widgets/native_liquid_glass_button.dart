import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'liquid_glass.dart';

/// Enveloppe un bouton Material (ElevatedButton, FilledButton, OutlinedButton,
/// TextButton, IconButton, y compris les variantes `.icon`) et l'affiche en
/// "liquid glass".
///
/// Le texte et les icônes sont de vrais widgets Flutter : ils s'affichent
/// toujours, quel que soit le bouton d'origine. Plus aucune vue native, donc
/// plus de plantage au clic. Le nom de la classe est conservé pour ne pas avoir
/// à modifier les écrans existants.
class NativeLiquidGlassButton extends StatelessWidget {
  const NativeLiquidGlassButton({required this.button, super.key});

  final Widget button;

  @override
  Widget build(BuildContext context) {
    final b = button;

    if (b is IconButton) {
      final fg = b.color ?? AppColors.textPrimary;
      return Tooltip(
        message: b.tooltip ?? '',
        child: GlassButtonShell(
          onPressed: b.onPressed,
          radius: 22,
          minHeight: 44,
          minWidth: 44,
          padding: const EdgeInsets.all(8),
          child: IconTheme.merge(
            data: IconThemeData(color: fg, size: b.iconSize ?? 22),
            child: b.icon,
          ),
        ),
      );
    }

    if (b is ButtonStyleButton) {
      final style = b.style;
      final resolvedFg = style?.foregroundColor?.resolve(const {});
      final resolvedBg = style?.backgroundColor?.resolve(const {});
      final resolvedSide = style?.side?.resolve(const {});
      final isFilled = b is ElevatedButton || b is FilledButton;
      final isText = b is TextButton;
      final isOutlined = b is OutlinedButton;

      // Couleurs : vert néon + texte sombre pour l'action principale.
      final Color? tint = isFilled
          ? (resolvedBg ?? AppColors.green)
          : (isOutlined && resolvedSide != null && resolvedSide.color.a > 0
                ? resolvedSide.color
                : null);
      final double tintOpacity = isFilled ? 0.88 : (tint != null ? 0.10 : 0);
      final Color fg =
          resolvedFg ??
          (isFilled
              ? AppColors.background
              : isText
              ? AppColors.green
              : AppColors.textPrimary);

      final enabled = b.onPressed != null;

      return LayoutBuilder(
        builder: (context, constraints) {
          // Pleine largeur seulement si le parent l'impose (SizedBox, Expanded…).
          final fill = constraints.hasBoundedWidth && constraints.hasTightWidth;
          return GlassButtonShell(
            onPressed: b.onPressed,
            fill: fill,
            radius: isText ? 16 : 18,
            minHeight: isText ? 44 : 52,
            padding: EdgeInsets.symmetric(
              horizontal: isText ? 14 : 20,
              vertical: 10,
            ),
            tint: isText ? null : tint,
            tintOpacity: isText ? 0 : tintOpacity,
            child: Opacity(
              opacity: enabled ? 1 : 0.9,
              child: DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: fg, size: 20),
                  child: b.child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          );
        },
      );
    }

    // Autre widget : on l'affiche tel quel plutôt que de planter.
    return b;
  }

}
