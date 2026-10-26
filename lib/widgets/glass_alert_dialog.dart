import 'package:flutter/material.dart';

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
    return AlertDialog(
      title: title,
      content: content,
      actions: actions,
      backgroundColor: backgroundColor,
      scrollable: scrollable,
      insetPadding: insetPadding,
    );
  }
}
