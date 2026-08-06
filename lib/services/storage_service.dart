import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/account.dart';
import '../models/transaction.dart';

/// Service de stockage de secours basé sur de la mémoire vive et du JSON brut
/// pour éliminer tout blocage lié aux plateformes natives.
class StorageService {
  static const _uuid = Uuid();

  // Stockage en mémoire vive de secours pour garantir zéropanne au démarrage
  static final Map<String, String> _memoryStore = {};

  static Future<void> initDefaultDataIfNeeded() async {
    // Initialisation immédiate sans bloquer sur le pont natif.
    // Ne crée aucun compte par défaut : l'utilisateur doit ajouter ses propres comptes.
    if (!_memoryStore.containsKey('ol_accounts')) {
      await saveAccounts([]);
    }
    if (!_memoryStore.containsKey('ol_transactions')) {
      await saveTransactions([]);
    }
  }

  // ---------- Comptes ----------

  static Future<List<Account>> getAccounts() async {
    final raw = _memoryStore['ol_accounts'];
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAccounts(List<Account> accounts) async {
    final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
    _memoryStore['ol_accounts'] = raw;
  }

  static Future<void> upsertAccount(Account account) async {
    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx >= 0) {
      accounts[idx] = account;
    } else {
      accounts.add(account);
    }
    await saveAccounts(accounts);
  }

  static Future<void> deleteAccount(String accountId) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.id == accountId);
    await saveAccounts(accounts);
    final txs = await getTransactions();
    txs.removeWhere((t) => t.accountId == accountId);
    await saveTransactions(txs);
  }

  // ---------- Transactions ----------

  static Future<List<LedgerTransaction>> getTransactions() async {
    final raw = _memoryStore['ol_transactions'];
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    final txs = list
        .map((e) => LedgerTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
    txs.sort((a, b) => b.date.compareTo(a.date));
    return txs;
  }

  static Future<void> saveTransactions(
    List<LedgerTransaction> transactions,
  ) async {
    final raw = jsonEncode(transactions.map((t) => t.toJson()).toList());
    _memoryStore['ol_transactions'] = raw;
  }

  static Future<void> addTransaction(LedgerTransaction tx) async {
    final txs = await getTransactions();
    txs.add(tx);
    await saveTransactions(txs);

    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.id == tx.accountId);
    if (idx >= 0) {
      accounts[idx].balance += tx.amount;
      await saveAccounts(accounts);
    }
  }

  static Future<void> deleteTransaction(String txId) async {
    final txs = await getTransactions();
    final tx = txs.firstWhere((t) => t.id == txId);
    txs.removeWhere((t) => t.id == txId);
    await saveTransactions(txs);

    final accounts = await getAccounts();
    final idx = accounts.indexWhere((a) => a.id == tx.accountId);
    if (idx >= 0) {
      accounts[idx].balance -= tx.amount;
      await saveAccounts(accounts);
    }
  }

  static String newId() => _uuid.v4();

  static Future<void> wipeAll() async {
    _memoryStore.clear();
    await initDefaultDataIfNeeded();
  }
}
