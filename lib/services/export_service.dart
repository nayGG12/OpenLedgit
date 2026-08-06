import 'dart:convert';
import 'dart:io';
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
  static Future<void> exportJson() async {
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

    await Share.shareXFiles([XFile(file.path)], text: 'Sauvegarde OpenLedger (JSON)');
  }

  /// Exporte uniquement les transactions en CSV, lisible dans Excel/LibreOffice/Sheets.
  static Future<void> exportCsv() async {
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
    final file = File('${dir.path}/openledger_transactions_${_timestamp()}.csv');
    await file.writeAsString(csvStr);

    await Share.shareXFiles([XFile(file.path)], text: 'Transactions OpenLedger (CSV)');
  }

  /// Importe une sauvegarde JSON précédemment exportée et remplace les données locales.
  /// Retourne true si l'import a réussi.
  static Future<bool> importJsonFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return false;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
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
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
