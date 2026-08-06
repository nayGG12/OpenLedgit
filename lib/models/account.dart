enum AccountType { banque, especes, autre }

extension AccountTypeX on AccountType {
  String get label {
    switch (this) {
      case AccountType.banque:
        return 'Banque';
      case AccountType.especes:
        return 'Espèces';
      case AccountType.autre:
        return 'Autre';
    }
  }

  String get emoji {
    switch (this) {
      case AccountType.banque:
        return '🏦';
      case AccountType.especes:
        return '💵';
      case AccountType.autre:
        return '💼';
    }
  }
}

class Account {
  String id;
  String name;
  AccountType type;
  double balance;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'balance': balance,
      };

// Exemple de correction dans Account.fromJson
factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String? ?? '', // Plus d'appel à StorageService ici
      name: json['name'] as String? ?? '',
      type: AccountType.values.firstWhere(
        (e) => e.name == json['type'], 
        orElse: () => AccountType.banque,
      ),
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0, 
    );
  }
}
