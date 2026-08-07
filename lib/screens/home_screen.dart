import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
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

  // Pulsation douce du bouton "+"
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _load();
    _loadUserName();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    // Priorité au nom local sauvegardé
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
    } catch (_) {
      // Pas bloquant : on retombe sur les infos Firebase Auth ci-dessous.
    }
    name ??= user.displayName;
    name ??= user.email?.split('@').first;
    name ??= 'à toi';
    final firstName = name.trim().isEmpty
        ? 'à toi'
        : name.trim().split(' ').first;
    if (mounted) setState(() => _userName = firstName);
  }

  Future<void> _load() async {
    // S'assure que les données par défaut (structures internes) sont initialisées
    // si le storage est vide. Ne crée AUCUN compte ni transaction automatiquement.

    final accounts = await StorageService.getAccounts();

    // Les transactions sont déjà sauvegardées automatiquement en local dès leur
    // création (StorageService.addTransaction), on se contente ici de recharger
    // l'état affiché à l'écran.
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
      floatingActionButton: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.elasticOut,
        builder: (context, entrance, child) =>
            Transform.scale(scale: entrance, child: child),
        child: ScaleTransition(
          scale: _pulseAnimation,
          child: FloatingActionButton(
            onPressed: _openAddTransaction,
            child: const Icon(Icons.add),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fond animé, discret : quelques halos qui bougent très lentement
          const Positioned.fill(child: _AnimatedBackdrop()),
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
                      _StaggeredFadeIn(
                        index: 0,
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
                        _StaggeredFadeIn(
                          index: 1,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: AppColors.green,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
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
                        _StaggeredFadeIn(
                          index: 1,
                          child: const Text(
                            'Patrimoine total',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _StaggeredFadeIn(
                          index: 2,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _total),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Text(
                              formatter.format(value),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _StaggeredFadeIn(
                        index: 3,
                        child: GestureDetector(
                          onTap: _openScanTicket,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.qr_code_scanner_outlined,
                                  color: AppColors.green,
                                  size: 28,
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Scanner un ticket pour pré-remplir une transaction',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_accounts.isNotEmpty) ...[
                        _StaggeredFadeIn(
                          index: 3,
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
                        const SizedBox(height: 20),
                      ],
                      _StaggeredFadeIn(
                        index: 4,
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
                      const SizedBox(height: 20),
                      const SizedBox(height: 12),
                      _StaggeredFadeIn(
                        index: 5 + _accounts.length,
                        child: TextField(
                          style: const TextStyle(color: AppColors.textPrimary),
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
                      _StaggeredFadeIn(
                        index: 6 + _accounts.length,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Filtres avancés',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedCategoryFilter,
                                      dropdownColor: AppColors.card,
                                      decoration: InputDecoration(
                                        fillColor: AppColors.card,
                                        filled: true,
                                        labelText: 'Catégorie',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
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
                                      onChanged: (value) => setState(
                                        () => _selectedCategoryFilter =
                                            value ?? 'Tous',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedAccountFilter,
                                      dropdownColor: AppColors.card,
                                      decoration: InputDecoration(
                                        fillColor: AppColors.card,
                                        filled: true,
                                        labelText: 'Compte',
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
                                          child: Text('Tous'),
                                        ),
                                        ..._accounts
                                            .map(
                                              (account) => DropdownMenuItem(
                                                value: account.id,
                                                child: Text(account.name),
                                              ),
                                            )
                                            .toList(),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _selectedAccountFilter =
                                            value ?? 'Tous',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedTypeFilter,
                                      dropdownColor: AppColors.card,
                                      decoration: InputDecoration(
                                        fillColor: AppColors.card,
                                        filled: true,
                                        labelText: 'Type',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'Tous',
                                          child: Text('Tous'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Revenu',
                                          child: Text('Revenu'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Dépense',
                                          child: Text('Dépense'),
                                        ),
                                      ],
                                      onChanged: (value) => setState(
                                        () => _selectedTypeFilter =
                                            value ?? 'Tous',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Min €',
                                        filled: true,
                                        fillColor: AppColors.card,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onChanged: (value) => setState(
                                        () => _minAmountFilter = value,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Max €',
                                        filled: true,
                                        fillColor: AppColors.card,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onChanged: (value) => setState(
                                        () => _maxAmountFilter = value,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => setState(() {
                                    _selectedCategoryFilter = 'Tous';
                                    _selectedAccountFilter = 'Tous';
                                    _selectedTypeFilter = 'Tous';
                                    _minAmountFilter = '';
                                    _maxAmountFilter = '';
                                  }),
                                  child: const Text(
                                    'Réinitialiser les filtres',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StaggeredFadeIn(
                        index: 6 + _accounts.length,
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
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                    final i = entry.key;
                                    final t = entry.value;
                                    final accountName =
                                        accountNames[t.accountId] ?? 'Inconnu';
                                    return _StaggeredFadeIn(
                                      index: 7 + _accounts.length + i,
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
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

/// Petit fondu + glissement pour faire apparaître les éléments en cascade,
/// sans dépendre d'un nombre d'items fixé à l'avance.
class _StaggeredFadeIn extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredFadeIn({required this.index, required this.child});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slideY;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;
  late final Animation<double> _blur;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    // Le fondu se termine avant la fin du mouvement : l'élément est déjà
    // visible pendant qu'il finit de se "poser" à sa place.
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _slideY = Tween<double>(
      begin: 46,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    // Léger dépassement (overshoot) pour un effet "pop" au lieu d'un simple zoom.
    _scale = Tween<double>(
      begin: 0.72,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _rotation = Tween<double>(
      begin: -0.05,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _blur = Tween<double>(begin: 8.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
    );

    final delay = Duration(milliseconds: 90 * widget.index.clamp(0, 24));
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        Widget content = child!;
        if (_blur.value > 0.05) {
          content = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _blur.value,
              sigmaY: _blur.value,
            ),
            child: content,
          );
        }
        return Opacity(
          opacity: _fade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, _slideY.value),
            child: Transform.rotate(
              angle: _rotation.value,
              child: Transform.scale(scale: _scale.value, child: content),
            ),
          ),
        );
      },
      child: widget.child,
    );
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

/// Fond décoratif : plusieurs formes organiques (pas des ronds parfaits) qui
/// flottent avec un mouvement plus vif, dégradé qui s'estompe en transparence.
/// Purement décoratif — n'intercepte aucun geste (IgnorePointer).
class _BlobSpec {
  final double size;
  final int seed;
  final Color color;
  final int durationMs;
  final double ampX;
  final double ampY;
  final double freqY;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const _BlobSpec({
    required this.size,
    required this.seed,
    required this.color,
    required this.durationMs,
    required this.ampX,
    required this.ampY,
    required this.freqY,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });
}

class _AnimatedBackdrop extends StatefulWidget {
  const _AnimatedBackdrop();

  @override
  State<_AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<_AnimatedBackdrop>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  static final List<_BlobSpec> _specs = [
    _BlobSpec(
      size: 200,
      seed: 1,
      color: AppColors.green.withOpacity(0.16),
      durationMs: 5200,
      ampX: 70,
      ampY: 50,
      freqY: 1.6,
      top: -50,
      left: -60,
    ),
    _BlobSpec(
      size: 150,
      seed: 2,
      color: AppColors.green.withOpacity(0.12),
      durationMs: 6400,
      ampX: 55,
      ampY: 65,
      freqY: 0.8,
      top: 100,
      right: -40,
    ),
    _BlobSpec(
      size: 230,
      seed: 3,
      color: AppColors.green.withOpacity(0.10),
      durationMs: 7600,
      ampX: 60,
      ampY: 45,
      freqY: 1.3,
      bottom: -70,
      left: 0,
    ),
    _BlobSpec(
      size: 130,
      seed: 4,
      color: AppColors.green.withOpacity(0.14),
      durationMs: 4600,
      ampX: 45,
      ampY: 55,
      freqY: 1.9,
      bottom: 60,
      right: -20,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = _specs
        .map(
          (s) => AnimationController(
            vsync: this,
            duration: Duration(milliseconds: s.durationMs),
          )..repeat(),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: List.generate(_specs.length, (i) {
          final spec = _specs[i];
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (context, _) {
              final t = _controllers[i].value * 2 * math.pi;
              final dx = spec.ampX * math.sin(t + spec.seed);
              final dy = spec.ampY * math.sin(t * spec.freqY);
              final rotation = t * 0.2;
              return Positioned(
                top: spec.top != null ? spec.top! + dy : null,
                bottom: spec.bottom != null ? spec.bottom! - dy : null,
                left: spec.left != null ? spec.left! + dx : null,
                right: spec.right != null ? spec.right! - dx : null,
                child: Transform.rotate(
                  angle: rotation,
                  child: _OrganicBlob(
                    size: spec.size,
                    seed: spec.seed,
                    color: spec.color,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

/// Forme organique irrégulière (pas un cercle) remplie d'un dégradé radial
/// qui s'estompe vers la transparence, avec un léger flou pour un rendu doux.
class _OrganicBlob extends StatelessWidget {
  final double size;
  final int seed;
  final Color color;
  const _OrganicBlob({
    required this.size,
    required this.seed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: CustomPaint(
          size: Size(size, size),
          painter: _BlobPainter(seed: seed, color: color),
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final int seed;
  final Color color;
  _BlobPainter({required this.seed, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed * 97);
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    const pointCount = 8;

    final points = <Offset>[];
    for (int i = 0; i < pointCount; i++) {
      final angle = (i / pointCount) * 2 * math.pi;
      final radiusVariance = baseRadius * (0.7 + rng.nextDouble() * 0.55);
      points.add(
        Offset(
          center.dx + radiusVariance * math.cos(angle),
          center.dy + radiusVariance * math.sin(angle),
        ),
      );
    }

    final path = Path();
    final start = Offset(
      (points[0].dx + points[points.length - 1].dx) / 2,
      (points[0].dy + points[points.length - 1].dy) / 2,
    );
    path.moveTo(start.dx, start.dy);
    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.close();

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withOpacity(0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.1));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => false;
}
