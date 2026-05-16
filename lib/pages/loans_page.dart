import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drivara_driver_app/api_config.dart';

// Read-only loans for the signed-in driver. Backed by:
//   GET /api/driver/me/loans
//   GET /api/driver/me/loans/:loanId
// The entry point on active_job_page.dart is conditionally rendered when the
// list returned by /api/driver/me/loans is non-empty, so a driver with no
// loans never sees this screen.

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('d MMM yyyy');

String _fmtAmount(dynamic v) {
  final n = double.tryParse('${v ?? 0}');
  if (n == null) return '—';
  return _currency.format(n);
}

String _fmtDate(dynamic v) {
  if (v == null) return '—';
  try {
    return _dateFmt.format(DateTime.parse(v.toString()).toLocal());
  } catch (_) {
    return v.toString();
  }
}

String _prettyPlanType(String? type) {
  switch (type) {
    case 'emi':
      return 'EMI';
    case 'no_cost_emi':
      return 'No-Cost EMI';
    case 'interest_only':
      return 'Interest Only';
    default:
      return type ?? '—';
  }
}

Color _statusColor(String? status, BuildContext ctx) {
  switch (status) {
    case 'paid':
    case 'closed':
      return Colors.green.shade600;
    case 'overdue':
    case 'defaulted':
      return Colors.red.shade600;
    case 'partial':
      return Colors.orange.shade700;
    case 'active':
    case 'pending':
    default:
      return Theme.of(ctx).colorScheme.primary;
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
  List<dynamic> _loans = [];

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
      final data = res.data;
      setState(() {
        _loans = data is List ? data : <dynamic>[];
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
    return Scaffold(
      appBar: AppBar(title: const Text('My Loans')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : _loans.isEmpty
                    ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('No loans on file.'))])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _loans.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) => _LoanSummaryCard(loan: _loans[i] as Map<String, dynamic>),
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
    final outstanding = loan['outstanding_principal'];
    final status = loan['status']?.toString();
    final purpose = (loan['purpose']?.toString() ?? '').trim();
    final next = loan['next_installment'] as Map<String, dynamic>?;
    final overdue = (loan['overdue_count'] ?? 0) as num;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: loan['id'].toString())),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      purpose.isEmpty ? _prettyPlanType(loan['plan_type']?.toString()) : purpose,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _statusChip(status, context),
                ],
              ),
              if (purpose.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(_prettyPlanType(loan['plan_type']?.toString()),
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _kv('Outstanding', _fmtAmount(outstanding), context),
                  _kv('Disbursed', _fmtAmount(loan['amount']), context, alignEnd: true),
                ],
              ),
              if (next != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: overdue > 0 ? Colors.red.shade50 : Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(overdue > 0 ? Icons.warning_amber_rounded : Icons.event,
                          size: 18, color: overdue > 0 ? Colors.red.shade700 : Theme.of(context).iconTheme.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          overdue > 0
                              ? '$overdue overdue · next ${_fmtAmount(next['total_due'])} due ${_fmtDate(next['due_date'])}'
                              : 'Next ${_fmtAmount(next['total_due'])} due ${_fmtDate(next['due_date'])}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
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

  Widget _statusChip(String? status, BuildContext ctx) {
    final color = _statusColor(status, ctx);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        (status ?? '—').toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _kv(String label, String value, BuildContext ctx, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
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
        _loan = res.data as Map<String, dynamic>;
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
      appBar: AppBar(title: const Text('Loan Detail')),
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
    final installments = (loan['installments'] as List?) ?? const [];
    final payments = (loan['payments'] as List?) ?? const [];
    final purpose = (loan['purpose']?.toString() ?? '').trim();
    final notes = (loan['notes']?.toString() ?? '').trim();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (purpose.isNotEmpty) ...[
                  Text(purpose, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                ],
                Text(_prettyPlanType(loan['plan_type']?.toString()),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _stat('Disbursed', _fmtAmount(loan['amount']), context)),
                    Expanded(child: _stat('Outstanding', _fmtAmount(loan['outstanding_principal']), context)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _stat('Paid', _fmtAmount(loan['total_paid']), context)),
                    Expanded(child: _stat('Rate', '${loan['interest_rate'] ?? '—'}%', context)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _stat('Start', _fmtDate(loan['start_date']), context)),
                    Expanded(child: _stat('Status', (loan['status'] ?? '—').toString().toUpperCase(), context)),
                  ],
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Notes', style: Theme.of(context).textTheme.bodySmall),
                  Text(notes),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Schedule', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (installments.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No installments.'))
        else
          ...installments.map((inst) => _InstallmentTile(inst: inst as Map<String, dynamic>)),
        const SizedBox(height: 16),
        Text('Payments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (payments.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No payments recorded.'))
        else
          ...payments.map((p) => _PaymentTile(payment: p as Map<String, dynamic>)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _stat(String label, String value, BuildContext ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(ctx).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _InstallmentTile extends StatelessWidget {
  final Map<String, dynamic> inst;
  const _InstallmentTile({required this.inst});

  @override
  Widget build(BuildContext context) {
    final status = inst['status']?.toString();
    final color = _statusColor(status, context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Text('${inst['installment_no'] ?? '?'}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ),
        title: Text(_fmtAmount(inst['total_due']), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Due ${_fmtDate(inst['due_date'])}'),
        trailing: Text(
          (status ?? '—').toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final type = payment['payment_type']?.toString().toUpperCase() ?? 'PAYMENT';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(_fmtAmount(payment['amount']), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$type · ${_fmtDate(payment['payment_date'])}'),
        trailing: payment['payment_mode'] != null
            ? Text(payment['payment_mode'].toString(),
                style: Theme.of(context).textTheme.bodySmall)
            : null,
      ),
    );
  }
}
