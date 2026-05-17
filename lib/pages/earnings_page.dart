import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drivara_driver_app/api_config.dart';
import 'package:drivara_driver_app/pages/settlement_sheet.dart';

// "My Earnings" — per-driver list of completed-trip salary shares over a
// chosen window. Reads from GET /api/driver/me/earnings?from=&to=. Tapping
// a row pulls /api/driver/jobs/:jobId/settlement and reopens the same
// settlement sheet the driver saw on Complete.
//
// Only completed jobs (status='completed') contribute — accrual on
// in-progress jobs is intentionally excluded so the totals match what the
// company actually owes today.

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _currencyDetailed = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('d MMM yyyy');

enum _Period { d7, d30, d90, all }

extension _PeriodX on _Period {
  String get label {
    switch (this) {
      case _Period.d7: return 'Last 7 days';
      case _Period.d30: return 'Last 30 days';
      case _Period.d90: return 'Last 90 days';
      case _Period.all: return 'All time';
    }
  }

  DateTime get from {
    final now = DateTime.now();
    switch (this) {
      case _Period.d7: return now.subtract(const Duration(days: 7));
      case _Period.d30: return now.subtract(const Duration(days: 30));
      case _Period.d90: return now.subtract(const Duration(days: 90));
      case _Period.all: return DateTime(2000);
    }
  }
}

class EarningsPage extends StatefulWidget {
  const EarningsPage({super.key});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  _Period _period = _Period.d30;
  bool _loading = true;
  String? _error;
  double _totalSalary = 0;
  List<dynamic> _jobs = [];

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
      final from = _period.from.toUtc().toIso8601String();
      final to = DateTime.now().toUtc().toIso8601String();
      final res = await ApiConfig.dio.get(
        '/driver/me/earnings',
        queryParameters: {'from': from, 'to': to},
      );
      final data = res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : {};
      setState(() {
        _totalSalary = (data['total_salary'] as num?)?.toDouble() ?? 0;
        _jobs = (data['jobs'] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load earnings. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _openJobSettlement(Map<String, dynamic> job) async {
    final jobId = job['id']?.toString();
    if (jobId == null) return;
    try {
      final res = await ApiConfig.dio.get('/driver/jobs/$jobId/settlement');
      if (!mounted) return;
      await showSettlementSheet(
        context,
        settlement: Map<String, dynamic>.from(res.data as Map),
        jobTitle: job['title']?.toString(),
        okLabel: 'Close',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load settlement.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Earnings')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _Period.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final p = _Period.values[i];
                    final selected = p == _period;
                    return ChoiceChip(
                      label: Text(p.label),
                      selected: selected,
                      onSelected: (_) {
                        if (p != _period) {
                          setState(() => _period = p);
                          _fetch();
                        }
                      },
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_period.label, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        _currency.format(_totalSalary),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.green.shade700,
                            ),
                      ),
                      Text(
                        _loading ? 'Loading…' : '${_jobs.length} trip${_jobs.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                      : _jobs.isEmpty
                          ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('No completed trips in this period.'))])
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _jobs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final job = _jobs[i] as Map<String, dynamic>;
                                final share = (job['salary_share'] as num?)?.toDouble() ?? 0;
                                final endAt = job['end_at']?.toString();
                                final endDate = endAt != null && endAt.isNotEmpty
                                    ? _dateFmt.format(DateTime.parse(endAt).toLocal())
                                    : '—';
                                final role = job['role']?.toString() ?? 'primary';
                                final title = (job['title']?.toString() ?? '').trim();
                                final displayTitle = title.isEmpty ? 'Trip' : title;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    onTap: () => _openJobSettlement(job),
                                    title: Text(displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text('$endDate · ${role.toUpperCase()}'),
                                    trailing: Text(
                                      _currencyDetailed.format(share),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
