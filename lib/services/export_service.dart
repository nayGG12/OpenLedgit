import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import 'storage_service.dart';

class ExportService {
  /// Exporte toutes les données (comptes + transactions) en un fichier JSON
  /// et ouvre la feuille de partage système pour que l'utilisateur en fasse ce qu'il veut.
  static Future<void> exportJson(BuildContext context) async {
    final accounts = await StorageService.getAccounts();
    final txs = await StorageService.getTransactions();

    final payload = {
      'app': 'OpenLedger',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': accounts.map((a) => a.toJson()).toList(),
      'transactions': txs.map((t) => t.toJson()).toList(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/openledger_backup_${_timestamp()}.json');
    await file.writeAsString(jsonStr);

    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Sauvegarde OpenLedger (JSON)',
      sharePositionOrigin: origin,
    );
  }

  /// Exporte uniquement les transactions en CSV, lisible dans Excel/LibreOffice/Sheets.
  static Future<void> exportCsv(BuildContext context) async {
    final txs = await StorageService.getTransactions();
    final accounts = await StorageService.getAccounts();
    final accountName = {for (final a in accounts) a.id: a.name};

    final rows = <List<dynamic>>[
      ['Date', 'Titre', 'Catégorie', 'Compte', 'Montant'],
      for (final t in txs)
        [
          t.date.toIso8601String().split('T').first,
          t.title,
          t.category,
          accountName[t.accountId] ?? 'Inconnu',
          t.amount.toStringAsFixed(2),
        ],
    ];

    final csvStr = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/openledger_transactions_${_timestamp()}.csv',
    );
    await file.writeAsString(csvStr);

    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Transactions OpenLedger (CSV)',
      sharePositionOrigin: origin,
    );
  }

  /// Importe une sauvegarde JSON précédemment exportée et remplace les données locales.
  /// Retourne true si l'import a réussi.
  static Future<bool> importJsonFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true, // s'assure que bytes sont disponibles sur iOS
    );
    if (result == null) return false;

    final picked = result.files.single;
    String content;
    try {
      if (picked.path != null) {
        final file = File(picked.path!);
        content = await file.readAsString();
      } else if (picked.bytes != null) {
        content = const Utf8Decoder().convert(picked.bytes!);
      } else {
        return false;
      }
      final data = jsonDecode(content) as Map<String, dynamic>;

      final accounts = (data['accounts'] as List)
          .map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList();
      final txs = (data['transactions'] as List)
          .map((e) => LedgerTransaction.fromJson(e as Map<String, dynamic>))
          .toList();

      await StorageService.saveAccounts(accounts);
      await StorageService.saveTransactions(txs);
      return true;
    } catch (e) {
      // JSON invalide ou erreur d'écriture → échec de l'import
      return false;
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
