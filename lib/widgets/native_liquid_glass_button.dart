import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NativeLiquidGlassButton extends StatefulWidget {
  const NativeLiquidGlassButton({required this.button, super.key});

  final Widget button;

  @override
  State<NativeLiquidGlassButton> createState() =>
      _NativeLiquidGlassButtonState();
}

class _NativeLiquidGlassButtonState extends State<NativeLiquidGlassButton> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant NativeLiquidGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sendUpdate();
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel(
      'open_ledger/native_liquid_glass_button/$viewId',
    );
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pressed') {
        _buttonDetails(widget.button).onPressed?.call();
      }
    });
    _channel = channel;
    _sendUpdate();
  }

  void _sendUpdate() {
    final channel = _channel;
    if (channel == null) return;
    final details = _buttonDetails(widget.button);
    channel.invokeMethod<void>('update', {
      'title': details.title,
      'systemImage': details.systemImage,
      'prominent': details.prominent,
      'enabled': details.onPressed != null,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) {
      return widget.button;
    }

    final details = _buttonDetails(widget.button);
    return SizedBox(
      height: details.height,
      child: UiKitView(
        viewType: 'open_ledger/native_liquid_glass_button',
        creationParams: {
          'title': details.title,
          'systemImage': details.systemImage,
          'prominent': details.prominent,
          'enabled': details.onPressed != null,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}

class _ButtonDetails {
  const _ButtonDetails({
    required this.title,
    required this.systemImage,
    required this.prominent,
    required this.onPressed,
    required this.height,
  });

  final String title;
  final String? systemImage;
  final bool prominent;
  final VoidCallback? onPressed;
  final double height;
}

_ButtonDetails _buttonDetails(Widget button) {
  if (button is IconButton) {
    final icon = button.icon;
    return _ButtonDetails(
      title: button.tooltip ?? _textAndIcon(icon).$1,
      systemImage: _systemImage(icon),
      prominent: false,
      onPressed: button.onPressed,
      height: 48,
    );
  }

  if (button is ButtonStyleButton) {
    final textAndIcon = _textAndIcon(button.child ?? const SizedBox.shrink());
    return _ButtonDetails(
      title: textAndIcon.$1,
      systemImage: textAndIcon.$2,
      prominent: button is ElevatedButton || button is FilledButton,
      onPressed: button.onPressed,
      height: button is TextButton ? 44 : 52,
    );
  }

  throw ArgumentError.value(
    button,
    'button',
    'Expected an IconButton or Material button.',
  );
}

(String, String?) _textAndIcon(Widget child) {
  if (child is Text) {
    return (child.data ?? child.textSpan?.toPlainText() ?? '', null);
  }
  if (child is Icon) {
    return ('', _systemImage(child));
  }
  if (child is Row || child is Column) {
    final children = child is Row ? child.children : (child as Column).children;
    String? label;
    String? image;
    for (final item in children) {
      final detail = _textAndIcon(item);
      if (detail.$1.isNotEmpty) label ??= detail.$1;
      image ??= detail.$2;
    }
    return (label ?? '', image);
  }
  if (child is Padding) {
    return _textAndIcon(child.child ?? const SizedBox.shrink());
  }
  if (child is Center) {
    return _textAndIcon(child.child ?? const SizedBox.shrink());
  }
  if (child is SizedBox && child.child != null) {
    return _textAndIcon(child.child!);
  }
  if (child is IconTheme) {
    return _textAndIcon(child.child);
  }
  if (child is CircularProgressIndicator) return ('Chargement…', null);
  return ('', null);
}

String? _systemImage(Widget icon) {
  if (icon is! Icon) return null;

  final codePoint = icon.icon?.codePoint;
  if (codePoint == Icons.add.codePoint) return 'plus';
  if (codePoint == Icons.link.codePoint) return 'link';
  if (codePoint == Icons.delete.codePoint ||
      codePoint == Icons.delete_outline.codePoint) {
    return 'trash';
  }
  if (codePoint == Icons.edit.codePoint ||
      codePoint == Icons.edit_outlined.codePoint) {
    return 'pencil';
  }
  if (codePoint == Icons.arrow_back.codePoint ||
      codePoint == Icons.arrow_back_ios_new.codePoint) {
    return 'chevron.left';
  }
  if (codePoint == Icons.fingerprint.codePoint) return 'touchid';
  if (codePoint == Icons.logout.codePoint) {
    return 'rectangle.portrait.and.arrow.right';
  }
  if (codePoint == Icons.download_outlined.codePoint) {
    return 'square.and.arrow.down';
  }
  if (codePoint == Icons.upload_outlined.codePoint) {
    return 'square.and.arrow.up';
  }
  return null;
}
