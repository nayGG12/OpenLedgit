import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'liquid_glass.dart';

/// Pop-up en verre dépoli (remplace AlertDialog, même API).
/// `backgroundColor` est accepté pour compatibilité mais le verre reste
/// translucide ; on s'en sert seulement comme teinte très légère.
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.backgroundColor,
    this.scrollable = false,
    this.insetPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool scrollable;
  final EdgeInsets? insetPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget? body = content == null
        ? null
        : DefaultTextStyle.merge(
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.35,
            ),
            child: content!,
          );
    if (body != null && scrollable) {
      body = SingleChildScrollView(child: body);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassSurface(
          radius: 30,
          blur: 30,
          tint: AppColors.card,
          tintOpacity: 0.72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleLarge!.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    child: title!,
                  ),
                if (title != null && body != null) const SizedBox(height: 14),
                if (body != null) Flexible(child: body),
                if (actions != null && actions!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
