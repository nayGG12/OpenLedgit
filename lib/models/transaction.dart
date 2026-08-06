const List<String> kCategories = [
  'Salaire',
  'Alimentation',
  'Transport',
  'Logement',
  'Loisirs',
  'Santé',
  'Shopping',
  'Abonnements',
  'Virement',
  'Autre',
];

class LedgerTransaction {
  String id;
  String title;
  double amount; // positif = revenu, négatif = dépense
  String category;
  String accountId;
  DateTime date;
  String? note;
  String? receiptImagePath;

  LedgerTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.accountId,
    required this.date,
    this.note,
    this.receiptImagePath,
  });

  bool get isIncome => amount >= 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'category': category,
    'accountId': accountId,
    'date': date.toIso8601String(),
    'note': note,
    'receiptImagePath': receiptImagePath,
  };

  factory LedgerTransaction.fromJson(Map<String, dynamic> json) =>
      LedgerTransaction(
        id: json['id'] as String,
        title: json['title'] as String,
        amount: (json['amount'] as num).toDouble(),
        category: json['category'] as String,
        accountId: json['accountId'] as String,
        date: DateTime.parse(json['date'] as String),
        note: json['note'] as String?,
        receiptImagePath: json['receiptImagePath'] as String?,
      );
}
