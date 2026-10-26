import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PinKeypad extends StatefulWidget {
  const PinKeypad({
    required this.length,
    required this.onCompleted,
    this.enabled = true,
    super.key,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final bool enabled;

  @override
  State<PinKeypad> createState() => _PinKeypadState();
}

class _PinKeypadState extends State<PinKeypad> {
  String _value = '';

  void _addDigit(String digit) {
    if (!widget.enabled || _value.length >= widget.length) return;
    final nextValue = '$_value$digit';
    setState(() => _value = nextValue);
    if (nextValue.length == widget.length) {
      widget.onCompleted(nextValue);
    }
  }

  void _removeDigit() {
    if (!widget.enabled || _value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${_value.length} chiffre(s) sur ${widget.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.length, (index) {
              final entered = index < _value.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: entered ? AppColors.green : Colors.transparent,
                  border: Border.all(
                    color: entered ? AppColors.green : AppColors.textSecondary,
                    width: 1.5,
                  ),
                  boxShadow: entered
                      ? [
                          BoxShadow(
                            color: AppColors.green.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: 264,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var digit = 1; digit <= 9; digit++)
                _digitButton('$digit', () => _addDigit('$digit')),
              const SizedBox.shrink(),
              _digitButton('0', () => _addDigit('0')),
              _digitButton(
                '',
                _removeDigit,
                icon: Icons.backspace_outlined,
                semanticLabel: 'Effacer un chiffre',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _digitButton(
    String digit,
    VoidCallback onPressed, {
    IconData? icon,
    String? semanticLabel,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel ?? digit,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: widget.enabled ? onPressed : null,
          customBorder: const CircleBorder(),
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card.withValues(alpha: 0.75),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: icon == null
                  ? Text(
                      digit,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 25,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Icon(icon, color: AppColors.textSecondary, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
