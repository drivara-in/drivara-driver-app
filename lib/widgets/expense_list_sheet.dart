import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';

class ExpenseListSheet extends StatefulWidget {
  final Map<String, dynamic> job;

  const ExpenseListSheet({Key? key, required this.job}) : super(key: key);

  @override
  State<ExpenseListSheet> createState() => _ExpenseListSheetState();
}

class _ExpenseListSheetState extends State<ExpenseListSheet> {
  bool _isLoading = true;
  List<dynamic> _expenses = [];

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  Future<void> _fetchExpenses() async {
    try {
      final response = await ApiConfig.dio.get('/driver/jobs/${widget.job['id']}/expenses');
      if (mounted) {
        setState(() {
          _expenses = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching expenses: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  t.t('submitted_expenses'),
                  style: AppTextStyles.header.copyWith(
                    fontSize: 20,
                    color: Theme.of(context).textTheme.bodyLarge?.color
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_expenses.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: Theme.of(context).disabledColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.t('no_expenses'),
                      style: TextStyle(
                        color: Theme.of(context).disabledColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchExpenses,
                child: ListView.separated(
                  itemCount: _expenses.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final expense = _expenses[index];
                    return _buildExpenseCard(expense, t);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense, LocalizationProvider t) {
    final amount = expense['amount'] ?? 0;
    String type = expense['type'] ?? t.t('unknown');
    // Map backend English type to localized string
    if (type != t.t('unknown')) {
       final key = 'etype_$type';
       final localized = t.t(key);
       if (localized != key) {
         type = localized;
       }
    }
    
    final timestamp = expense['timestamp'] != null 
        ? DateTime.parse(expense['timestamp']) 
        : DateTime.now();
    final description = expense['description'];
    final location = expense['location'];
    final createdBy = expense['created_by_name'] ?? 'Driver';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: AppTextStyles.header.copyWith(
                        fontSize: 16,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a', t.locale.toString()).format(timestamp),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: AppTextStyles.header.copyWith(
                    fontSize: 16,
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          if (description != null && description.toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.note_outlined,
                  size: 16,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    description,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ],
            ),
          ],
          
          if (location != null && location.toString().isNotEmpty && location != 'Manual Entry') ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              Text(
                '${t.t('added_by')} $createdBy',
                style: AppTextStyles.label.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
