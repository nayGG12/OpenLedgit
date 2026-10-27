import 'package:flutter/material.dart';
import '../widgets/native_liquid_glass_button.dart';
import 'package:flutter/services.dart';

import '../models/account.dart';
import '../services/plaid_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/account_card.dart';

class AddBankAccountScreen extends StatefulWidget {
  const AddBankAccountScreen({super.key});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingAccounts = true;
  bool _isSavingManualAccount = false;
  bool _isCreatingManual = false;
  String _statusText = '';
  String? _error;
  PlaidLinkResult? _result;
  AccountType _selectedAccountType = AccountType.especes;
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await StorageService.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _isLoadingAccounts = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingAccounts = false;
        _error = 'Impossible de charger les comptes : $error';
      });
    }
  }

  Future<void> _connectBank() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await PlaidService.connectBankAccount(
        onStatusUpdate: (status) {
          if (mounted) setState(() => _statusText = status);
        },
      );

      if (!mounted) return;

      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }

      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de connecter la banque : $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveManualAccount() async {
    if (_isSavingManualAccount || _formKey.currentState?.validate() != true) {
      return;
    }

    final balance = double.parse(
      _balanceController.text.trim().replaceAll(',', '.'),
    );
    final account = Account(
      id: StorageService.newId(),
      name: _nameController.text.trim(),
      type: _selectedAccountType,
      balance: balance,
      isManual: true,
    );

    setState(() {
      _isSavingManualAccount = true;
      _error = null;
    });

    try {
      await StorageService.upsertAccount(account);
      if (!mounted) return;
      setState(() {
        _accounts = [..._accounts, account];
        _isCreatingManual = false;
        _isSavingManualAccount = false;
        _nameController.clear();
        _balanceController.clear();
        _selectedAccountType = AccountType.especes;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Compte virtuel créé.')));
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingManualAccount = false;
        _error = 'Impossible de créer le compte : $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes comptes')),
      body: _isLoading
          ? _buildLoading()
          : _result != null
          ? _buildResult(_result!)
          : _isCreatingManual
          ? _buildManualAccountForm()
          : _buildAccountOptions(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.green),
          const SizedBox(height: 16),
          Text(
            _statusText,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountOptions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        const Text(
          'Choisis comment ajouter ton compte',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tu peux connecter une banque ou créer un compte virtuel avec ton solde actuel.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
        const SizedBox(height: 20),
        _AccountOptionCard(
          icon: Icons.account_balance_outlined,
          title: 'Connecter une banque',
          description:
              'Synchronisation automatique du solde et des transactions. Tu dois posséder un compte bancaire.',
          buttonLabel: 'Connecter ma banque',
          onPressed: _connectBank,
        ),
        const SizedBox(height: 16),
        _AccountOptionCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Créer un compte virtuel',
          description:
              'Saisis le nom de ton choix et le montant disponible. Aucune banque ni carte requise — idéal pour suivre de l’argent de poche ou des espèces.',
          buttonLabel: 'Créer un compte sans banque',
          onPressed: () => setState(() {
            _error = null;
            _isCreatingManual = true;
          }),
          secondary: true,
        ),
        if (_isLoadingAccounts) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ] else if (_accounts.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text(
            'Mes comptes enregistrés',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ..._accounts.map((account) => AccountCard(account: account)),
        ],
      ],
    );
  }

  Widget _buildManualAccountForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        Row(
          children: [
            NativeLiquidGlassButton(button: IconButton(
              onPressed: _isSavingManualAccount
                  ? null
                  : () => setState(() => _isCreatingManual = false),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Retour aux choix de compte',
            )),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                'Nouveau compte virtuel',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Donne un nom à ton compte et indique combien tu as actuellement.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom du compte',
                  hintText: 'Ex. Argent de poche',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Entre un nom pour ce compte.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AccountType>(
                value: _selectedAccountType,
                decoration: const InputDecoration(
                  labelText: 'Type de compte',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: AccountType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text('${type.emoji} ${type.label}'),
                      ),
                    )
                    .toList(),
                onChanged: _isSavingManualAccount
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedAccountType = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Solde actuel',
                  hintText: 'Ex. 25,50',
                  prefixIcon: Icon(Icons.euro),
                  suffixText: '€',
                ),
                validator: (value) {
                  final normalized = value?.trim().replaceAll(',', '.');
                  if (normalized == null || normalized.isEmpty) {
                    return 'Entre le solde actuel.';
                  }
                  if (double.tryParse(normalized) == null) {
                    return 'Entre un montant valide.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.red)),
                const SizedBox(height: 12),
              ],
              NativeLiquidGlassButton(button: ElevatedButton.icon(
                onPressed: _isSavingManualAccount ? null : _saveManualAccount,
                icon: _isSavingManualAccount
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Enregistrer ce compte'),
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResult(PlaidLinkResult result) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        const Text(
          'Compte(s) connecté(s) :',
          style: TextStyle(
            color: AppColors.green,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        ...result.accounts.map(
          (account) => Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance,
                color: AppColors.green,
              ),
              title: Text(
                account.name,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                account.mask != null
                    ? 'x${account.mask}'
                    : (account.officialName ?? ''),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: Text(
                account.currentBalance != null
                    ? '${account.currentBalance!.toStringAsFixed(2)} ${account.currency ?? '€'}'
                    : '—',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '${result.transactions.length} transaction(s) importée(s)',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        NativeLiquidGlassButton(button: ElevatedButton(
          onPressed: () {
            // TODO: save linked accounts and transactions locally.
          },
          child: const Text('Importer dans OpenLedger'),
        )),
      ],
    );
  }
}

class _AccountOptionCard extends StatelessWidget {
  const _AccountOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.secondary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: secondary ? AppColors.textPrimary : AppColors.green,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: secondary
                  ? NativeLiquidGlassButton(button: OutlinedButton(
                      onPressed: onPressed,
                      child: Text(buttonLabel),
                    ))
                  : NativeLiquidGlassButton(button: ElevatedButton.icon(
                      onPressed: onPressed,
                      icon: const Icon(Icons.link),
                      label: Text(buttonLabel),
                    )),
            ),
          ],
        ),
      ),
    );
  }
}
