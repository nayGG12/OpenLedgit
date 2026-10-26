import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/native_liquid_glass_button.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_alert_dialog.dart';
import '../widgets/account_card.dart';
import '../widgets/transaction_tile.dart';
import 'add_transaction_screen.dart' show AddTransactionScreen;
import 'scan_ticket_screen.dart';
import 'transaction_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Account> _accounts = [];
  List<LedgerTransaction> _transactions = [];
  bool _loading = true;
  String _userName = '';
  String _searchQuery = '';
  String _selectedCategoryFilter = 'Tous';
  String _selectedAccountFilter = 'Tous';
  String _selectedTypeFilter = 'Tous';
  String _selectedChartAccount = 'Tous';
  String _minAmountFilter = '';
  String _maxAmountFilter = '';

  bool _isFabExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final local = await StorageService.getUserFullName();
    if (local != null && local.trim().isNotEmpty) {
      final firstName = local.trim().split(' ').first;
      if (mounted) setState(() => _userName = firstName);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String? name;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      name = doc.data()?['fullName'] as String?;
    } catch (_) {}
    name ??= user.displayName;
    name ??= user.email?.split('@').first;
    name ??= 'à toi';
    final firstName = name.trim().isEmpty
        ? 'à toi'
        : name.trim().split(' ').first;
    if (mounted) setState(() => _userName = firstName);
  }

  Future<void> _load() async {
    final accounts = await StorageService.getAccounts();
    final txs = await StorageService.getTransactions();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _transactions = txs;
      _loading = false;
    });
  }

  double get _total => _accounts.fold(0.0, (sum, a) => sum + a.balance);

  Future<void> _openAddTransaction() async {
    if (_accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crée d\'abord un compte dans l\'onglet Comptes.'),
        ),
      );
      return;
    }

    try {
      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(accounts: _accounts),
        ),
      );
      if (added == true) _load();
    } catch (e) {
      debugPrint('Erreur lors de l\'ouverture de l\'écran d\'ajout : $e');
    }
  }

  Future<void> _openScanTicket() async {
    if (_accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crée d\'abord un compte dans l\'onglet Comptes.'),
        ),
      );
      return;
    }

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ScanTicketScreen(accounts: _accounts)),
    );
    if (added == true) _load();
  }

  Future<void> _openTransactionDetail(
    LedgerTransaction tx,
    String accountName,
  ) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TransactionDetailScreen(transaction: tx, accountName: accountName),
      ),
    );
    if (deleted == true) _load();
  }

  void _openAdvancedFiltersDialog() {
    showDialog(
      context: context,
      builder: (context) => GlassAlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Filtres avancés',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedCategoryFilter,
                  dropdownColor: AppColors.card,
                  decoration: InputDecoration(
                    fillColor: AppColors.card,
                    filled: true,
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: ['Tous', ...kCategories]
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedCategoryFilter = value ?? 'Tous'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedAccountFilter,
                  dropdownColor: AppColors.card,
                  decoration: InputDecoration(
                    fillColor: AppColors.card,
                    filled: true,
                    labelText: 'Compte',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'Tous', child: Text('Tous')),
                    ..._accounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedAccountFilter = value ?? 'Tous'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedTypeFilter,
                  dropdownColor: AppColors.card,
                  decoration: InputDecoration(
                    fillColor: AppColors.card,
                    filled: true,
                    labelText: 'Type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Tous', child: Text('Tous')),
                    DropdownMenuItem(value: 'Revenu', child: Text('Revenu')),
                    DropdownMenuItem(value: 'Dépense', child: Text('Dépense')),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedTypeFilter = value ?? 'Tous'),
                ),
                const SizedBox(height: 14),
                TextField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Montant min (€)',
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _minAmountFilter = value),
                ),
                const SizedBox(height: 14),
                TextField(
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Montant max (€)',
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _maxAmountFilter = value),
                ),
              ],
            ),
          ),
        ),
        actions: [
          NativeLiquidGlassButton(
            button: TextButton(
              onPressed: () => setState(() {
                _selectedCategoryFilter = 'Tous';
                _selectedAccountFilter = 'Tous';
                _selectedTypeFilter = 'Tous';
                _minAmountFilter = '';
                _maxAmountFilter = '';
              }),
              child: const Text('Réinitialiser'),
            ),
          ),
          NativeLiquidGlassButton(
            button: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Appliquer'),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveFilters =>
      _selectedCategoryFilter != 'Tous' ||
      _selectedAccountFilter != 'Tous' ||
      _selectedTypeFilter != 'Tous' ||
      _minAmountFilter.isNotEmpty ||
      _maxAmountFilter.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final accountNames = {for (final a in _accounts) a.id: a.name};
    double? parseAmount(String value) {
      final normalized = value.trim().replaceAll(',', '.');
      return normalized.isEmpty ? null : double.tryParse(normalized);
    }

    final minAmount = parseAmount(_minAmountFilter);
    final maxAmount = parseAmount(_maxAmountFilter);

    final chartTransactions = _selectedChartAccount == 'Tous'
        ? _transactions
        : _transactions
              .where((tx) => tx.accountId == _selectedChartAccount)
              .toList();

    final chartBalance = _selectedChartAccount == 'Tous'
        ? _total
        : _accounts
              .firstWhere(
                (account) => account.id == _selectedChartAccount,
                orElse: () => Account(
                  id: 'Tous',
                  name: 'Tous',
                  type: AccountType.autre,
                  balance: 0.0,
                ),
              )
              .balance;

    final filteredTransactions = _transactions.where((tx) {
      final query = _searchQuery.toLowerCase();
      final accountName = accountNames[tx.accountId] ?? '';
      final matchesSearch =
          _searchQuery.trim().isEmpty ||
          tx.title.toLowerCase().contains(query) ||
          tx.category.toLowerCase().contains(query) ||
          (tx.note ?? '').toLowerCase().contains(query) ||
          accountName.toLowerCase().contains(query);
      if (!matchesSearch) return false;

      if (_selectedCategoryFilter != 'Tous' &&
          tx.category != _selectedCategoryFilter) {
        return false;
      }
      if (_selectedAccountFilter != 'Tous' &&
          tx.accountId != _selectedAccountFilter) {
        return false;
      }
      if (_selectedTypeFilter == 'Dépense' && tx.amount >= 0) return false;
      if (_selectedTypeFilter == 'Revenu' && tx.amount < 0) return false;

      final absAmount = tx.amount.abs();
      if (minAmount != null && absAmount < minAmount) return false;
      if (maxAmount != null && absAmount > maxAmount) return false;

      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('OPENLEDGER')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isFabExpanded) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.extended(
                onPressed: _openAddTransaction,
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('Saisie manuelle'),
                backgroundColor: AppColors.green,
                foregroundColor: Colors.black,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.extended(
                onPressed: _openScanTicket,
                icon: const Icon(Icons.document_scanner_outlined, size: 20),
                label: const Text('Scanner un ticket'),
                backgroundColor: AppColors.card,
                foregroundColor: AppColors.textPrimary,
              ),
            ),
          ],
          FloatingActionButton(
            onPressed: () => setState(() {
              _isFabExpanded = !_isFabExpanded;
            }),
            child: Icon(_isFabExpanded ? Icons.close : Icons.add),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _HomeBackdrop()),
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.green),
                )
              : RefreshIndicator(
                  color: AppColors.green,
                  backgroundColor: AppColors.card,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      _HomeContent(
                        child: Text(
                          'Bienvenue, $_userName 👋',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_accounts.isEmpty)
                        _HomeContent(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: AppColors.green,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    "Aucun compte pour l'instant. Ajoute-en un dans l'onglet Comptes pour commencer à suivre tes finances.",
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        _HomeContent(
                          child: const Text(
                            'Patrimoine total',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _HomeContent(
                          child: Text(
                            formatter.format(_total),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (_accounts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _HomeContent(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Comptes disponibles',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  children: _accounts
                                      .map(
                                        (account) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: AccountCard(account: account),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _HomeContent(
                          child: TextField(
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.card,
                              hintText: 'Rechercher une transaction',
                              hintStyle: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: AppColors.textSecondary,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() => _searchQuery = value);
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        _HomeContent(
                          child: Row(
                            children: [
                              Expanded(
                                child: NativeLiquidGlassButton(
                                  button: TextButton.icon(
                                    onPressed: _openAdvancedFiltersDialog,
                                    icon: Icon(
                                      Icons.tune_outlined,
                                      color: _hasActiveFilters
                                          ? AppColors.green
                                          : AppColors.textSecondary,
                                    ),
                                    label: Text(
                                      _hasActiveFilters
                                          ? 'Filtres actifs'
                                          : 'Filtres avancés',
                                      style: TextStyle(
                                        color: _hasActiveFilters
                                            ? AppColors.green
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_hasActiveFilters)
                                NativeLiquidGlassButton(
                                  button: TextButton(
                                    onPressed: () => setState(() {
                                      _selectedCategoryFilter = 'Tous';
                                      _selectedAccountFilter = 'Tous';
                                      _selectedTypeFilter = 'Tous';
                                      _minAmountFilter = '';
                                      _maxAmountFilter = '';
                                    }),
                                    child: const Text('Réinitialiser'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _HomeContent(
                          child: const Text(
                            'Dernières transactions',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (filteredTransactions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                _searchQuery.trim().isEmpty
                                    ? 'Aucune transaction pour l\'instant.\nAppuie sur + pour en ajouter une.'
                                    : 'Aucune transaction ne correspond à cette recherche.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              child: Column(
                                children: filteredTransactions
                                    .take(10)
                                    .toList()
                                    .map((t) {
                                      final accountName =
                                          accountNames[t.accountId] ??
                                          'Inconnu';
                                      return _HomeContent(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: () => _openTransactionDetail(
                                              t,
                                              accountName,
                                            ),
                                            child: TransactionTile(
                                              transaction: t,
                                              accountName: accountName,
                                            ),
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        _HomeContent(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Résumé mensuel',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedChartAccount,
                                        dropdownColor: AppColors.card,
                                        decoration: InputDecoration(
                                          fillColor: AppColors.card,
                                          filled: true,
                                          labelText: 'Compte graphique',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                        items: [
                                          const DropdownMenuItem(
                                            value: 'Tous',
                                            child: Text('Tous les comptes'),
                                          ),
                                          ..._accounts.map(
                                            (account) => DropdownMenuItem(
                                              value: account.id,
                                              child: Text(account.name),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) => setState(
                                          () => _selectedChartAccount =
                                              value ?? 'Tous',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _MonthlyChart(
                                  transactions: chartTransactions,
                                  currentBalance: chartBalance,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final Widget child;
  const _HomeContent({required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<LedgerTransaction> transactions;
  final double currentBalance;

  const _MonthlyChart({
    required this.transactions,
    required this.currentBalance,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    final values = List<double>.generate(31, (index) {
      final day = DateTime(
        startDate.year,
        startDate.month,
        startDate.day + index,
      );
      final laterSum = transactions
          .where((tx) {
            final txDay = DateTime(tx.date.year, tx.date.month, tx.date.day);
            return txDay.isAfter(day);
          })
          .fold(0.0, (sum, tx) => sum + tx.amount);
      return currentBalance - laterSum;
    });

    final monthlyTransactions = transactions
        .where((tx) => !tx.date.isBefore(startDate))
        .toList();
    final income = monthlyTransactions
        .where((tx) => tx.amount >= 0)
        .fold(0.0, (sum, tx) => sum + tx.amount);
    final expense = monthlyTransactions
        .where((tx) => tx.amount < 0)
        .fold(0.0, (sum, tx) => sum + tx.amount.abs());
    final net = income - expense;

    final minValue = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxValue = values.isEmpty ? 0.0 : values.reduce(math.max);
    final chartMinY = minValue == maxValue
        ? minValue - 1.0
        : math.min(0.0, minValue);
    final chartMaxY = minValue == maxValue
        ? maxValue + 1.0
        : math.max(0.0, maxValue);
    final yLabels = [chartMaxY, (chartMaxY + chartMinY) / 2, chartMinY];
    final dateFormat = DateFormat('dd MMM', 'fr_FR');
    final dateLabels = [
      dateFormat.format(startDate),
      dateFormat.format(startDate.add(const Duration(days: 15))),
      dateFormat.format(now),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Solde des 30 derniers jours',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${dateFormat.format(startDate)} → ${dateFormat.format(now)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 200,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: yLabels.map((value) {
                          return Text(
                            '${value.toStringAsFixed(0)} €',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CustomPaint(
                          painter: _LineChartPainter(
                            values: values,
                            minY: chartMinY,
                            maxY: chartMaxY,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: dateLabels
                        .map(
                          (label) => Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Revenus',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      '${income.toStringAsFixed(2)} €',
                      style: const TextStyle(color: AppColors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Dépenses',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      '${expense.toStringAsFixed(2)} €',
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Solde net : ${net.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double minY;
  final double maxY;

  _LineChartPainter({
    required this.values,
    required this.minY,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.textSecondary.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final curvePaint = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()..color = AppColors.green.withOpacity(0.16);

    for (int line = 0; line <= 3; line++) {
      final y = size.height * line / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) return;

    final span = maxY - minY == 0 ? 1.0 : maxY - minY;
    final step = values.length > 1
        ? size.width / (values.length - 1)
        : size.width;
    final points = List.generate(values.length, (index) {
      final dx = step * index;
      final dy = size.height - ((values[index] - minY) / span) * size.height;
      return Offset(dx, dy);
    });

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final current = points[i];
      final mid = Offset(
        (prev.dx + current.dx) / 2,
        (prev.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    if (points.length > 1) {
      final last = points.last;
      path.quadraticBezierTo(
        points[points.length - 2].dx,
        points[points.length - 2].dy,
        last.dx,
        last.dy,
      );
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY;
  }
}

class _HomeBackdrop extends StatelessWidget {
  const _HomeBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.9),
          radius: 1.2,
          colors: [Color(0x1422C55E), Colors.transparent],
        ),
      ),
    );
  }
}
