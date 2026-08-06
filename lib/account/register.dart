import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'login.dart';
import 'check.dart'; // Assurez-vous que le fichier s'appelle bien check.dart et contient CheckEmailScreen

// Modèle temporaire stocké en RAM pendant l'attente de la vérification de l'email
class PendingUserCache {
  static String? fullName;
  static String? email;
  static String? password;
  static DateTime? birthDate;

  static void clear() {
    fullName = null;
    email = null;
    password = null;
    birthDate = null;
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _birthDateController = TextEditingController();

  DateTime? _selectedDate;
  bool _isLoading = false;

  bool _hasLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  late final AnimationController _mainController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  late final List<Animation<double>> _itemFades;
  late final List<Animation<Offset>> _itemSlides;

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _itemFades = List.generate(8, (index) {
      final double start = 0.15 + (index * 0.08);
      final double end = (start + 0.4).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _mainController,
        curve: Interval(start, end, curve: Curves.easeOut),
      );
    });

    _itemSlides = List.generate(8, (index) {
      final double start = 0.15 + (index * 0.08);
      final double end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _mainController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _mainController.forward();
    _passwordController.addListener(_validatePasswordRules);
  }

  void _validatePasswordRules() {
    final password = _passwordController.text;
    const specialChars = "!@#\$%^&*(),.?\":{}|<>-_=+~`'[]\\;/";

    setState(() {
      _hasLength = password.length >= 8 && password.length <= 30;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasDigit = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.split('').any((char) => specialChars.contains(char));
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _birthDateController.dispose();
    _mainController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.green,
              onSurface: AppColors.textPrimary,
              surface: AppColors.card,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _birthDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _submit() async {
    // Vérification de la validité du formulaire et des règles du mot de passe
    if (!_formKey.currentState!.validate()) return;
    
    if (!_hasLength || !_hasUppercase || !_hasLowercase || !_hasDigit || !_hasSpecialChar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez respecter tous les critères de sécurité du mot de passe.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Stockage temporaire des données en RAM
      PendingUserCache.fullName = _nameController.text.trim();
      PendingUserCache.email = _emailController.text.trim();
      PendingUserCache.password = _passwordController.text;
      PendingUserCache.birthDate = _selectedDate;

      // 2. Création du compte Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: PendingUserCache.email!,
        password: PendingUserCache.password!,
      );

      User? user = userCredential.user;

      if (user != null) {
        // 3. Envoi de l'email de vérification
        await user.sendEmailVerification();

        if (!mounted) return;

        // 4. Redirection vers l'écran de vérification
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CheckEmailScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "Une erreur d'authentification est survenue";
      if (e.code == 'weak-password') {
        message = 'Le mot de passe fourni est trop faible.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Un compte existe déjà pour cette adresse email.';
      } else if (e.code == 'invalid-email') {
        message = 'Adresse email invalide.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      // Affichage de l'erreur exacte dans la console pour le débogage
      print("Erreur inattendue lors de l'inscription : $e");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur: ${e.toString()}"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildCriterionRow(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isValid ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isValid ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedItem(int index, Widget child) {
    return FadeTransition(
      opacity: _itemFades[index],
      child: SlideTransition(
        position: _itemSlides[index],
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _animatedItem(
                              0,
                              const Text(
                                'Créer un compte',
                                textAlign: TextAlign.center,
                                textScaler: TextScaler.linear(1.0),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _animatedItem(
                              1,
                              const Text(
                                'Rejoignez OpenLedger pour sécuriser vos finances.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 36),
                            _animatedItem(
                              2,
                              TextFormField(
                                controller: _nameController,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'Nom complet',
                                  prefixIcon: Icon(Icons.person_outline, color: AppColors.green),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Veuillez entrer votre nom'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _animatedItem(
                              3,
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'Adresse email',
                                  prefixIcon: Icon(Icons.email_outlined, color: AppColors.green),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Veuillez entrer votre email';
                                  }
                                  if (!v.contains('@')) return 'Email invalide';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                            _animatedItem(
                              4,
                              TextFormField(
                                controller: _birthDateController,
                                readOnly: true,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'Date de naissance',
                                  prefixIcon: Icon(Icons.calendar_today_outlined, color: AppColors.green),
                                ),
                                onTap: () => _selectBirthDate(context),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Veuillez sélectionner votre date de naissance'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _animatedItem(
                              5,
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    style: const TextStyle(color: AppColors.textPrimary),
                                    decoration: const InputDecoration(
                                      labelText: 'Mot de passe',
                                      prefixIcon: Icon(Icons.lock_outline, color: AppColors.green),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Veuillez entrer un mot de passe';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildCriterionRow('Entre 8 et 30 caractères', _hasLength),
                                        _buildCriterionRow('Une lettre majuscule', _hasUppercase),
                                        _buildCriterionRow('Une lettre minuscule', _hasLowercase),
                                        _buildCriterionRow('Un chiffre', _hasDigit),
                                        _buildCriterionRow('Un caractère spécial (!@#\$%^&*)', _hasSpecialChar),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _animatedItem(
                              6,
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: true,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'Confirmer le mot de passe',
                                  prefixIcon: Icon(Icons.lock_reset, color: AppColors.green),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Veuillez confirmer votre mot de passe';
                                  }
                                  if (v != _passwordController.text) {
                                    return 'Les mots de passe ne correspondent pas';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 40),
                            _animatedItem(
                              7,
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.green,
                                        foregroundColor: AppColors.background,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                color: AppColors.background,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Text(
                                              "S'inscrire",
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Center(
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                                        );
                                      },
                                      child: const Text(
                                        "Vous êtes déjà inscrit ? Connectez-vous",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: AppColors.green,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}