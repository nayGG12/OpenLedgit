import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../theme/app_theme.dart';

class TransactionTile extends StatelessWidget {
  final LedgerTransaction transaction;
  final String accountName;
  final VoidCallback? onLongPress;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.accountName,
    this.onLongPress,
  });

  IconData get _categoryIcon {
    switch (transaction.category) {
      case 'Salaire':
        return Icons.work_outline;
      case 'Alimentation':
        return Icons.restaurant_outlined;
      case 'Transport':
        return Icons.directions_bus_outlined;
      case 'Logement':
        return Icons.home_outlined;
      case 'Loisirs':
        return Icons.sports_esports_outlined;
      case 'Santé':
        return Icons.favorite_border;
      case 'Shopping':
        return Icons.shopping_bag_outlined;
      case 'Abonnements':
        return Icons.autorenew;
      case 'Virement':
        return Icons.swap_horiz;
      default:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final isIncome = transaction.isIncome;
    final color = isIncome ? AppColors.green : AppColors.red;
    final sign = isIncome ? '+' : '';

    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(_categoryIcon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${transaction.category} · $accountName · ${DateFormat('dd/MM/yyyy').format(transaction.date)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '$sign${formatter.format(transaction.amount)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
