import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Reusable "I owe you" sheet shown to the driver:
//  1. Right after they tap Complete Trip on the active-job page, so they see
//     the company's settlement figure for that trip before the screen
//     bounces to NoJobPage.
//  2. When they tap a past job row on the Earnings page, so they can
//     re-open the same numbers later.
//
// The widget is pure presentation. Caller fetches the payload from
// GET /api/driver/jobs/:jobId/settlement and passes it in. Layout mirrors
// the dispatcher's CompleteJobModal settlement card on the web.

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String _fmt(dynamic v) {
  final n = double.tryParse('${v ?? 0}');
  if (n == null) return '—';
  return _currency.format(n);
}

Future<void> showSettlementSheet(
  BuildContext context, {
  required Map<String, dynamic> settlement,
  String? jobTitle,
  String okLabel = 'OK',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SettlementSheetContent(
      settlement: settlement,
      jobTitle: jobTitle,
      okLabel: okLabel,
    ),
  );
}

class _SettlementSheetContent extends StatelessWidget {
  final Map<String, dynamic> settlement;
  final String? jobTitle;
  final String okLabel;

  const _SettlementSheetContent({
    required this.settlement,
    required this.jobTitle,
    required this.okLabel,
  });

  @override
  Widget build(BuildContext context) {
    final role = settlement['role']?.toString() ?? 'primary';
    final salary = double.tryParse('${settlement['salary_share'] ?? 0}') ?? 0;
    final expenses = double.tryParse('${settlement['expenses_logged'] ?? 0}') ?? 0;
    final advance = double.tryParse('${settlement['advance_taken'] ?? 0}') ?? 0;
    final net = double.tryParse('${settlement['net_payable'] ?? 0}') ?? (salary + expenses - advance);

    final netIsPositive = net >= 0;
    final netColor = netIsPositive ? Colors.green.shade700 : Colors.red.shade700;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trip Settlement',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (jobTitle != null && jobTitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(jobTitle!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          )),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _row(context, 'Salary', _fmt(salary)),
                  _row(context, 'Expenses you logged', _fmt(expenses)),
                  _row(context, 'Advance taken', '− ${_fmt(advance)}'),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Net payable to you',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_fmt(net),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: netColor,
                              )),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(okLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ],
      ),
    );
  }
}
