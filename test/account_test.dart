import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger/models/account.dart';

void main() {
  group('Account JSON', () {
    test('manual accounts keep their virtual flag when serialized', () {
      final account = Account(
        id: 'pocket-money',
        name: 'Argent de poche',
        type: AccountType.especes,
        balance: 25.5,
        isManual: true,
      );

      final restored = Account.fromJson(account.toJson());

      expect(restored.id, account.id);
      expect(restored.name, account.name);
      expect(restored.type, account.type);
      expect(restored.balance, account.balance);
      expect(restored.isManual, isTrue);
    });

    test('existing accounts without the virtual flag remain compatible', () {
      final account = Account.fromJson({
        'id': 'existing-account',
        'name': 'Compte existant',
        'type': 'banque',
        'balance': 100,
      });

      expect(account.isManual, isFalse);
      expect(account.balance, 100);
    });
  });
}
