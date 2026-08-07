import 'dart:convert';
import 'dart:io';
import 'package:uuid/Uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/transaction.dart';

/// Service de stockage persistant utilisant SharedPreferences.
/// Conserve les données sur l'appareil entre les redémarrages.
class StorageService {
  static const _uuid = Uuid();
  static const _accountsKey = 'ol_accounts';
  static const _transactionsKey = 'ol_transactions';
  static const _userFullNameKey = 'user_full_name';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<void> initDefaultDataIfNeeded() async {
    final p = await _prefs();
    if (!p.containsKey(_accountsKey)) {
      await saveAccounts([]);
    }
    if (!p.containsKey(_transactionsKey)) {
      await saveTransactions([]);
    }
  }

  // ---------- Comptes ----------

  static Future<List<Account>> getAccounts() async {
    final p = await _prefs();
    final raw = p.getString(_accountsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveAccounts(List<Account> accounts) async {
    final p = await _prefs();
    final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await p.setString(_accountsKey, raw);
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
    final removed = txs.where((t) => t.accountId == accountId).toList();
    txs.removeWhere((t) => t.accountId == accountId);
    await saveTransactions(txs);

    for (final tx in removed) {
      if (tx.receiptImagePath != null) {
        final file = File(tx.receiptImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  // ---------- Transactions ----------

  static Future<List<LedgerTransaction>> getTransactions() async {
    final p = await _prefs();
    final raw = p.getString(_transactionsKey);
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
    final p = await _prefs();
    final raw = jsonEncode(transactions.map((t) => t.toJson()).toList());
    await p.setString(_transactionsKey, raw);
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

    if (tx.receiptImagePath != null) {
      final file = File(tx.receiptImagePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static Future<void> updateTransaction(LedgerTransaction updatedTx) async {
    final txs = await getTransactions();
    final idx = txs.indexWhere((t) => t.id == updatedTx.id);
    if (idx < 0) return;

    final oldTx = txs[idx];
    txs[idx] = updatedTx;
    await saveTransactions(txs);

    final accounts = await getAccounts();
    final oldAccountIdx = accounts.indexWhere((a) => a.id == oldTx.accountId);
    if (oldAccountIdx >= 0) {
      accounts[oldAccountIdx].balance -= oldTx.amount;
    }
    final newAccountIdx = accounts.indexWhere(
      (a) => a.id == updatedTx.accountId,
    );
    if (newAccountIdx >= 0) {
      accounts[newAccountIdx].balance += updatedTx.amount;
    }
    if (oldAccountIdx >= 0 || newAccountIdx >= 0) {
      await saveAccounts(accounts);
    }
  }

  static String newId() => _uuid.v4();

  static Future<void> wipeAll() async {
    final p = await _prefs();
    await p.remove(_accountsKey);
    await p.remove(_transactionsKey);
    await p.remove(_userFullNameKey);
    await initDefaultDataIfNeeded();
  }

  // ---------- Utilisateur ----------

  static Future<String?> getUserFullName() async {
    final p = await _prefs();
    return p.getString(_userFullNameKey);
  }

  static Future<void> saveUserFullName(String name) async {
    final p = await _prefs();
    await p.setString(_userFullNameKey, name);
  }
}
