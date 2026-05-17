import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drivara_driver_app/api_config.dart';

// Read-only loans for the signed-in driver. Backed by:
//   GET /api/driver/me/loans
//   GET /api/driver/me/loans/:loanId
//
// Visual treatment:
//   • LoansPage opens with a hero summary card (gradient indigo→violet)
//     showing total outstanding across active loans + active count.
//   • Each loan card has a strong purpose/plan title row, status pill,
//     big Outstanding amount, a slim progress bar (paid vs disbursed),
//     and a next-installment chip (red when any are overdue).
//   • LoanDetailPage gets a matching hero, a 4-stat grid, and timeline-
//     style schedule + payments lists with colored dots per status.

final _currency0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _currency2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('d MMM yyyy');
final _shortDateFmt = DateFormat('d MMM');

const _heroStart = Color(0xFF4F46E5);   // indigo-600
const _heroEnd = Color(0xFF7C3AED);     // violet-600
const _accent = Color(0xFF4338CA);      // indigo-700

String _fmtAmount0(dynamic v) {
  final n = double.tryParse('${v ?? 0}');
  if (n == null) return '—';
  return _currency0.format(n);
}

String _fmtAmount2(dynamic v) {
  final n = double.tryParse('${v ?? 0}');
  if (n == null) return '—';
  return _currency2.format(n);
}

String _fmtDate(dynamic v) {
  if (v == null) return '—';
  try { return _dateFmt.format(DateTime.parse(v.toString()).toLocal()); } catch (_) { return v.toString(); }
}

String _fmtShortDate(dynamic v) {
  if (v == null) return '—';
  try { return _shortDateFmt.format(DateTime.parse(v.toString()).toLocal()); } catch (_) { return v.toString(); }
}

String _prettyPlanType(String? type) {
  switch (type) {
    case 'emi': return 'EMI';
    case 'no_cost_emi': return 'No-Cost EMI';
    case 'interest_only': return 'Interest Only';
    default: return type ?? '—';
  }
}

({Color color, Color background}) _statusColors(String? status) {
  switch (status) {
    case 'paid':
    case 'closed':
      return (color: const Color(0xFF15803D), background: const Color(0xFFD1FAE5));
    case 'overdue':
    case 'defaulted':
      return (color: const Color(0xFFB91C1C), background: const Color(0xFFFEE2E2));
    case 'partial':
      return (color: const Color(0xFFB45309), background: const Color(0xFFFEF3C7));
    case 'active':
    case 'pending':
    default:
      return (color: _accent, background: const Color(0xFFE0E7FF));
  }
}

class LoansPage extends StatefulWidget {
  const LoansPage({super.key});

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _loans = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiConfig.dio.get('/driver/me/loans');
      final data = res.data is List ? (res.data as List) : const [];
      setState(() {
        _loans = data
            .whereType<Map>()
            .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load loans. Pull to retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeLoans = _loans.where((l) => l['status'] == 'active').toList();
    final totalOutstanding = activeLoans.fold<double>(
      0,
      (sum, l) => sum + ((l['outstanding_principal'] as num?)?.toDouble() ?? 0),
    );
    final hasOverdue = _loans.any((l) => ((l['overdue_count'] ?? 0) as num) > 0);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('My Loans'), elevation: 0),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _hero(
                outstanding: totalOutstanding,
                activeCount: activeLoans.length,
                totalCount: _loans.length,
                hasOverdue: hasOverdue,
              ),
            ),
            if (_loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(hasScrollBody: false, child: _emptyState(context, Icons.error_outline, _error!))
            else if (_loans.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(context, Icons.account_balance_outlined, 'No loans on file.'),
              )
            else ...[
              SliverToBoxAdapter(child: _sectionHeader(context, 'YOUR LOANS', _loans.length)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: _loans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _LoanSummaryCard(loan: _loans[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero({
    required double outstanding,
    required int activeCount,
    required int totalCount,
    required bool hasOverdue,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_heroStart, _heroEnd],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: _heroEnd.withOpacity(0.30), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'OUTSTANDING BALANCE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  hasOverdue ? Icons.warning_amber_rounded : Icons.account_balance_outlined,
                  color: Colors.white70,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _currency0.format(outstanding),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withOpacity(0.18)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _heroStat(
                    Icons.bolt_rounded,
                    activeCount.toString(),
                    activeCount == 1 ? 'active' : 'active',
                  ),
                ),
                Container(width: 1, height: 32, color: Colors.white.withOpacity(0.18)),
                Expanded(
                  child: _heroStat(
                    Icons.layers_outlined,
                    totalCount.toString(),
                    totalCount == 1 ? 'total loan' : 'total loans',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          ],
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Theme.of(context).textTheme.bodySmall?.color,
              )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                )),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, IconData icon, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 32, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color)),
          ],
        ),
      ),
    );
  }
}

class _LoanSummaryCard extends StatelessWidget {
  final Map<String, dynamic> loan;
  const _LoanSummaryCard({required this.loan});

  @override
  Widget build(BuildContext context) {
    final amount = (loan['amount'] as num?)?.toDouble() ?? 0;
    final outstanding = (loan['outstanding_principal'] as num?)?.toDouble() ?? 0;
    final paid = (amount - outstanding).clamp(0, amount).toDouble();
    final progress = amount > 0 ? (paid / amount).clamp(0.0, 1.0) : 0.0;

    final status = loan['status']?.toString();
    final colors = _statusColors(status);
    final purpose = (loan['purpose']?.toString() ?? '').trim();
    final next = loan['next_installment'] as Map<String, dynamic>?;
    final overdue = ((loan['overdue_count'] ?? 0) as num).toInt();
    final planType = _prettyPlanType(loan['plan_type']?.toString());

    return Material(
      color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: loan['id'].toString())),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.account_balance, color: colors.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          purpose.isEmpty ? planType : purpose,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(planType,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            )),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (status ?? '—').toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: colors.color, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OUTSTANDING',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Theme.of(context).hintColor,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          _currency0.format(outstanding),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('DISBURSED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Theme.of(context).hintColor,
                          )),
                      const SizedBox(height: 2),
                      Text(_currency0.format(amount),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar (paid vs disbursed)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overdue > 0 ? const Color(0xFFDC2626) : _accent,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_currency0.format(paid)} paid of ${_currency0.format(amount)} (${(progress * 100).toStringAsFixed(0)}%)',
                style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
              if (next != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: overdue > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        overdue > 0 ? Icons.warning_amber_rounded : Icons.event_outlined,
                        size: 18,
                        color: overdue > 0 ? const Color(0xFFDC2626) : _accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              overdue > 0 ? '$overdue overdue' : 'Next installment',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: overdue > 0 ? const Color(0xFFDC2626) : _accent,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Text(
                              '${_fmtAmount0(next['total_due'])} due ${_fmtShortDate(next['due_date'])}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Theme.of(context).hintColor),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoanDetailPage extends StatefulWidget {
  final String loanId;
  const LoanDetailPage({super.key, required this.loanId});

  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _loan;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiConfig.dio.get('/driver/me/loans/${widget.loanId}');
      setState(() {
        _loan = Map<String, dynamic>.from(res.data as Map);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load loan. Pull to retry.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Loan Detail'), elevation: 0),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final loan = _loan!;
    final amount = (loan['amount'] as num?)?.toDouble() ?? 0;
    final outstanding = (loan['outstanding_principal'] as num?)?.toDouble() ?? 0;
    final totalPaid = (loan['total_paid'] as num?)?.toDouble() ?? 0;
    final interestPaid = (loan['total_interest_paid'] as num?)?.toDouble() ?? 0;
    final rate = loan['interest_rate'];
    final progress = amount > 0 ? ((amount - outstanding) / amount).clamp(0.0, 1.0) : 0.0;

    final installments = (loan['installments'] as List?) ?? const [];
    final payments = (loan['payments'] as List?) ?? const [];
    final purpose = (loan['purpose']?.toString() ?? '').trim();
    final notes = (loan['notes']?.toString() ?? '').trim();
    final status = loan['status']?.toString();
    final planType = _prettyPlanType(loan['plan_type']?.toString());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Hero
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_heroStart, _heroEnd],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: _heroEnd.withOpacity(0.30), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      planType.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (status ?? '—').toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (purpose.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(purpose, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              const Text('Outstanding', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _currency0.format(outstanding),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withOpacity(0.20),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% paid · ${_currency0.format(amount)} disbursed',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _statTile(context, 'Paid', _fmtAmount0(totalPaid), Icons.check_circle_outline)),
            const SizedBox(width: 10),
            Expanded(child: _statTile(context, 'Interest', _fmtAmount0(interestPaid), Icons.percent_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statTile(context, 'Rate', rate != null ? '$rate%' : '—', Icons.trending_up_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _statTile(context, 'Started', _fmtDate(loan['start_date']), Icons.event_outlined)),
          ],
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOTES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Theme.of(context).hintColor)),
                const SizedBox(height: 4),
                Text(notes, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        _sectionTitle(context, 'SCHEDULE', installments.length),
        const SizedBox(height: 8),
        if (installments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No installments.', style: TextStyle(color: Theme.of(context).hintColor)),
          )
        else
          ...installments.map((inst) => _InstallmentRow(inst: inst as Map<String, dynamic>)),
        const SizedBox(height: 22),
        _sectionTitle(context, 'PAYMENTS', payments.length),
        const SizedBox(height: 8),
        if (payments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No payments recorded.', style: TextStyle(color: Theme.of(context).hintColor)),
          )
        else
          ...payments.map((p) => _PaymentRow(payment: p as Map<String, dynamic>)),
      ],
    );
  }

  Widget _statTile(BuildContext context, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _accent),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String label, int count) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Theme.of(context).textTheme.bodySmall?.color,
            )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Theme.of(context).textTheme.bodyMedium?.color)),
        ),
      ],
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  final Map<String, dynamic> inst;
  const _InstallmentRow({required this.inst});

  @override
  Widget build(BuildContext context) {
    final status = inst['status']?.toString();
    final colors = _statusColors(status);
    final no = inst['installment_no']?.toString() ?? '?';
    final dueDate = _fmtShortDate(inst['due_date']);
    final amount = _fmtAmount2(inst['total_due']);
    final isPaid = status == 'paid';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(no, style: TextStyle(color: colors.color, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(amount, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()])),
                  Text('Due $dueDate', style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(8)),
              child: Text(
                (status ?? '—').toUpperCase(),
                style: TextStyle(color: colors.color, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5),
              ),
            ),
            if (isPaid) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, color: colors.color, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final type = payment['payment_type']?.toString().toUpperCase() ?? 'PAYMENT';
    final mode = payment['payment_mode']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF15803D), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fmtAmount2(payment['amount']),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()])),
                  Text('$type · ${_fmtShortDate(payment['payment_date'])}',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color)),
                ],
              ),
            ),
            if (mode != null && mode.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  mode.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
