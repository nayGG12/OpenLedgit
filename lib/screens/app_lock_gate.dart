import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/native_liquid_glass_button.dart';
import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_keypad.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.child,
    this.initiallyUnlocked = false,
    super.key,
  });

  final Widget child;
  final bool initiallyUnlocked;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

enum _GateState { loading, setup, locked, unlocked, error }

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  _GateState _gateState = _GateState.loading;
  int _pinLength = 4;
  bool _hasPin = false;
  bool _hasBiometrics = false;
  bool _authenticating = false;
  bool _lockOnResume = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initiallyUnlocked) {
      _hasPin = true;
      _gateState = _GateState.unlocked;
    } else {
      unawaited(_initialize());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _gateState = _GateState.loading;
      _errorMessage = null;
    });
    try {
      final pin = await AppLockService.getPin();
      if (!mounted) return;
      if (pin == null) {
        setState(() {
          _hasPin = false;
          _gateState = _GateState.unlocked;
        });
        return;
      }

      setState(() {
        _hasPin = true;
        _pinLength = pin.length;
        _gateState = _GateState.locked;
      });

      try {
        final hasBiometrics = await AppLockService.hasBiometrics();
        if (!mounted) return;
        setState(() => _hasBiometrics = hasBiometrics);
      } on Exception {
        if (mounted) {
          setState(
            () => _errorMessage =
                'Biométrie indisponible. Entrez votre code PIN.',
          );
        }
      }
      if (!mounted) return;
      if (_hasBiometrics) await _authenticateBiometrics();
    } on Exception {
      if (!mounted) return;
      setState(() {
        _gateState = _GateState.error;
        _errorMessage = 'Impossible d’accéder au stockage sécurisé. Réessayez.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_hasPin && _gateState == _GateState.unlocked && !_authenticating) {
        _lockOnResume = true;
        setState(() => _gateState = _GateState.locked);
      }
      return;
    }

    if (state == AppLifecycleState.resumed && _lockOnResume) {
      _lockOnResume = false;
      unawaited(_refreshPinAfterResume());
    }
  }

  Future<void> _refreshPinAfterResume() async {
    try {
      final pin = await AppLockService.getPin();
      if (!mounted) return;
      if (pin == null) {
        setState(() {
          _hasPin = false;
          _gateState = _GateState.unlocked;
          _errorMessage = null;
        });
        return;
      }
      setState(() => _pinLength = pin.length);
      if (_hasBiometrics) await _authenticateBiometrics();
    } on Exception {
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossible de vérifier le code PIN enregistré.';
        });
      }
    }
  }

  Future<void> _authenticateBiometrics() async {
    if (_authenticating || _gateState != _GateState.locked) return;
    setState(() {
      _authenticating = true;
      _errorMessage = null;
    });
    try {
      final authenticated = await AppLockService.authenticateBiometrics();
      if (mounted && authenticated) {
        setState(() => _gateState = _GateState.unlocked);
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _hasBiometrics = false;
          _errorMessage = 'Biométrie indisponible. Entrez votre code PIN.';
        });
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  Future<void> _saveNewPin(String pin) async {
    try {
      await AppLockService.savePin(pin);
      if (!mounted) return;
      setState(() {
        _pinLength = pin.length;
        _errorMessage = null;
        _gateState = _GateState.unlocked;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossible d’enregistrer le code PIN. Réessayez.';
        });
      }
    }
  }

  Future<void> _verifyPin(String pin) async {
    try {
      final result = await AppLockService.verifyPin(pin);
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (result) {
          PinVerificationResult.success => null,
          PinVerificationResult.incorrect => 'Code PIN incorrect.',
          PinVerificationResult.lockedOut =>
            'Trop de tentatives. Réessayez dans 30 secondes.',
        };
        if (result == PinVerificationResult.success) {
          _gateState = _GateState.unlocked;
        }
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossible de vérifier le code PIN. Réessayez.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_gateState) {
      _GateState.unlocked => widget.child,
      _GateState.loading => const _LockScaffold(
        child: CircularProgressIndicator(color: AppColors.green),
      ),
      _GateState.error => _LockScaffold(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: AppColors.green, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Une erreur est survenue.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            NativeLiquidGlassButton(
              button: FilledButton(
                onPressed: _initialize,
                child: const Text('Réessayer'),
              ),
            ),
          ],
        ),
      ),
      _GateState.setup || _GateState.locked => _PinAccessScreen(
        key: ValueKey(_gateState),
        isSetup: _gateState == _GateState.setup,
        pinLength: _pinLength,
        hasBiometrics: _hasBiometrics,
        isAuthenticating: _authenticating,
        errorMessage: _errorMessage,
        onSavePin: _saveNewPin,
        onVerifyPin: _verifyPin,
        onBiometric: _authenticateBiometrics,
      ),
    };
  }
}

class _LockScaffold extends StatelessWidget {
  const _LockScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: child),
    );
  }
}

class _PinAccessScreen extends StatefulWidget {
  const _PinAccessScreen({
    required this.isSetup,
    required this.pinLength,
    required this.hasBiometrics,
    required this.isAuthenticating,
    required this.errorMessage,
    required this.onSavePin,
    required this.onVerifyPin,
    required this.onBiometric,
    super.key,
  });

  final bool isSetup;
  final int pinLength;
  final bool hasBiometrics;
  final bool isAuthenticating;
  final String? errorMessage;
  final Future<void> Function(String pin) onSavePin;
  final Future<void> Function(String pin) onVerifyPin;
  final Future<void> Function() onBiometric;

  @override
  State<_PinAccessScreen> createState() => _PinAccessScreenState();
}

class _PinAccessScreenState extends State<_PinAccessScreen> {
  int _keypadSession = 0;
  String? _newPin;
  String? _setupError;
  int _pinLength = 4;
  bool _confirmingPin = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pinLength = widget.pinLength;
  }

  Future<void> _submit(String pin) async {
    if (_busy) return;

    if (widget.isSetup && !_confirmingPin) {
      setState(() {
        _newPin = pin;
        _confirmingPin = true;
        _setupError = null;
        _keypadSession++;
      });
      return;
    }

    if (widget.isSetup && _newPin != pin) {
      setState(() {
        _newPin = null;
        _confirmingPin = false;
        _setupError = 'Les codes PIN ne correspondent pas. Réessayez.';
        _keypadSession++;
      });
      return;
    }

    setState(() => _busy = true);
    try {
      if (widget.isSetup) {
        await widget.onSavePin(pin);
      } else {
        await widget.onVerifyPin(pin);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _newPin = null;
          _confirmingPin = false;
          _keypadSession++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LockScaffold(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: AppColors.green,
                    size: 56,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.isSetup ? 'Créer votre code PIN' : 'Code PIN',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isSetup
                        ? _confirmingPin
                              ? 'Confirmez votre nouveau code PIN.'
                              : 'Choisissez un code de 4 ou 6 chiffres.'
                        : 'Entrez votre code pour déverrouiller OpenLedger.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (widget.isSetup) ...[
                    const SizedBox(height: 24),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 4, label: Text('4 chiffres')),
                        ButtonSegment(value: 6, label: Text('6 chiffres')),
                      ],
                      selected: {_pinLength},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _pinLength = selection.first;
                          _newPin = null;
                          _confirmingPin = false;
                          _setupError = null;
                          _keypadSession++;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  PinKeypad(
                    key: ValueKey(_keypadSession),
                    length: _pinLength,
                    enabled: !_busy && !widget.isAuthenticating,
                    onCompleted: _submit,
                  ),
                  if (widget.isSetup && _confirmingPin) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _newPin = null;
                              _confirmingPin = false;
                              _keypadSession++;
                            }),
                      child: const Text('Recommencer'),
                    ),
                  ],
                  if (_setupError != null || widget.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _setupError ?? widget.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ],
                  if (!widget.isSetup && widget.hasBiometrics) ...[
                    const SizedBox(height: 12),
                    NativeLiquidGlassButton(
                      button: TextButton.icon(
                        onPressed: _busy || widget.isAuthenticating
                            ? null
                            : widget.onBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Utiliser la biométrie'),
                      ),
                    ),
                  ],
                  if (_busy || widget.isAuthenticating) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(color: AppColors.green),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
