import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../models/account.dart';

class StorageService {
  static const String _txBoxName = 'transactions_box';
  static const String _accountBoxName = 'accounts_box';

  // --- TRANSACTIONS ---

  static Future<void> addTransaction(LedgerTransaction tx) async {
    final box = await Hive.openBox<LedgerTransaction>(_txBoxName);
    await box.put(tx.id, tx);
  }

  static Future<List<LedgerTransaction>> getTransactions() async {
    final box = await Hive.openBox<LedgerTransaction>(_txBoxName);
    return box.values.toList();
  }

  // --- COMPTES ---

  static Future<void> upsertAccount(Account account) async {
    final box = await Hive.openBox<Account>(_accountBoxName);
    await box.put(account.id, account);
  }

  static Future<List<Account>> getAccounts() async {
    final box = await Hive.openBox<Account>(_accountBoxName);
    // Retourne la liste vide si aucun compte n'a été créé par l'utilisateur
    return box.values.toList();
  }

  static Future<void> deleteAccount(String id) async {
    final box = await Hive.openBox<Account>(_accountBoxName);
    await box.delete(id);
  }

  // --- UTILITAIRE ---

  static String newId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}