import 'package:flutter/material.dart';

import '../main.dart' show RootNavigation;
import '../screens/app_lock_gate.dart';
import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/native_liquid_glass_button.dart';
import '../widgets/pin_keypad.dart';

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  int _pinLength = 4;
  int _keypadSession = 0;
  String? _newPin;
  String? _errorMessage;
  bool _confirmingPin = false;
  bool _busy = false;

  Future<void> _continueWithoutPin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await AppLockService.skipSetup();
      await _openApp(withPin: false);
    } on Exception {
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossible d’enregistrer votre choix. Réessayez.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPinCompleted(String pin) async {
    if (_busy) return;
    if (!_confirmingPin) {
      setState(() {
        _newPin = pin;
        _confirmingPin = true;
        _errorMessage = null;
        _keypadSession++;
      });
      return;
    }

    if (_newPin != pin) {
      setState(() {
        _newPin = null;
        _confirmingPin = false;
        _errorMessage = 'Les codes PIN ne correspondent pas. Recommencez.';
        _keypadSession++;
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await AppLockService.savePin(pin);
      await _openApp(withPin: true);
    } on Exception {
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossible d’enregistrer le code PIN. Réessayez.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openApp({required bool withPin}) async {
    if (!mounted) return;
    await Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AppLockGate(
          initiallyUnlocked: withPin,
          child: const RootNavigation(),
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 72,
                      color: AppColors.green,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Protégez votre application',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Vous pouvez ajouter un code PIN pour sécuriser vos données. Cette étape est facultative.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 4, label: Text('4 chiffres')),
                        ButtonSegment(value: 6, label: Text('6 chiffres')),
                      ],
                      selected: {_pinLength},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) {
                              setState(() {
                                _pinLength = selection.first;
                                _newPin = null;
                                _confirmingPin = false;
                                _errorMessage = null;
                                _keypadSession++;
                              });
                            },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _confirmingPin
                          ? 'Confirmez votre code PIN'
                          : 'Choisissez votre code PIN',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    PinKeypad(
                      key: ValueKey(_keypadSession),
                      length: _pinLength,
                      enabled: !_busy,
                      onCompleted: _onPinCompleted,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.red),
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.green,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    NativeLiquidGlassButton(
                      button: TextButton(
                        onPressed: _busy ? null : _continueWithoutPin,
                        child: const Text('Continuer sans code PIN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
