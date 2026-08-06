import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import '../services/storage_service.dart';

class CollectNameScreen extends StatefulWidget {
  const CollectNameScreen({super.key});

  @override
  State<CollectNameScreen> createState() => _CollectNameScreenState();
}

class _CollectNameScreenState extends State<CollectNameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final name = _nameController.text.trim();
    try {
      // Sauvegarde locale (rapide)
      await StorageService.saveUserFullName(name);

      if (!mounted) return;

      // Navigue immédiatement vers l'app principale
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RootNavigation()),
        (route) => false,
      );

      // Mise à jour distante en arrière-plan (ne bloque pas l'UI)
      Future(() async {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await user.updateDisplayName(name);
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
                  'fullName': name,
                  'email': user.email,
                  'uid': user.uid,
                }, SetOptions(merge: true));
          }
        } catch (_) {
          // Ignorer les erreurs réseau
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la sauvegarde : $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 24.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 80,
                  color: AppColors.green,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Quel est votre nom complet ?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ce nom sera utilisé dans l\'application et sauvegardé localement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nom complet'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'Le nom complet est requis.';
                      if (v.trim().split(' ').length < 2)
                        return 'Veuillez entrer votre nom et prénom.';
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: AppColors.background,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Enregistrer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
