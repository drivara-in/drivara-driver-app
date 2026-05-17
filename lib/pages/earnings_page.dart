import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:drivara_driver_app/api_config.dart';
import 'package:drivara_driver_app/pages/settlement_sheet.dart';
import 'package:drivara_driver_app/providers/localization_provider.dart';

// "My Earnings" — per-driver salary shares over a chosen window. Reads from
// GET /api/driver/me/earnings?from=&to=. Tapping a row pulls
// /api/driver/jobs/:jobId/settlement and reopens the settlement sheet.
//
// Visual treatment:
//   • Hero card with gradient + big ₹ total, period label, mini stats row.
//   • Period chips beneath, segmented look.
//   • Trip list: each row is a card with a calendar pill on the left,
//     route on top, role badge below, ₹ share on the right in green.
//   • Empty state with an icon + helper text instead of a bare sentence.

final _currency0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _currency2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _shortDateFmt = DateFormat('d MMM');

enum _Period { d7, d30, d90, all }

extension _PeriodX on _Period {
  String label(LocalizationProvider t) {
    switch (this) {
      case _Period.d7: return t.t('earnings_period_d7') ?? 'Last 7 days';
      case _Period.d30: return t.t('earnings_period_d30') ?? 'Last 30 days';
      case _Period.d90: return t.t('earnings_period_d90') ?? 'Last 90 days';
      case _Period.all: return t.t('earnings_period_all') ?? 'All time';
    }
  }

  String shortLabel(LocalizationProvider t) {
    switch (this) {
      case _Period.d7: return t.t('earnings_chip_d7') ?? '7D';
      case _Period.d30: return t.t('earnings_chip_d30') ?? '30D';
      case _Period.d90: return t.t('earnings_chip_d90') ?? '90D';
      case _Period.all: return t.t('earnings_chip_all') ?? 'ALL';
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

const _gradStart = Color(0xFF059669);   // emerald-600
const _gradEnd = Color(0xFF0D9488);     // teal-600
const _moneyColor = Color(0xFF065F46);  // emerald-800

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
  List<Map<String, dynamic>> _jobs = const [];

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
        _totalSalary = double.tryParse('${data['total_salary'] ?? 0}') ?? 0;
        _jobs = ((data['jobs'] as List?) ?? const [])
            .whereType<Map>()
            .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final t = Provider.of<LocalizationProvider>(context, listen: false);
      setState(() {
        _error = t.t('earnings_load_error') ?? 'Could not load earnings. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _openJobSettlement(Map<String, dynamic> job) async {
    final jobId = job['id']?.toString();
    if (jobId == null) return;
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    try {
      final res = await ApiConfig.dio.get('/driver/jobs/$jobId/settlement');
      if (!mounted) return;
      await showSettlementSheet(
        context,
        settlement: Map<String, dynamic>.from(res.data as Map),
        jobTitle: job['title']?.toString(),
        okLabel: t.t('settlement_close') ?? 'Close',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('settlement_load_error') ?? 'Could not load settlement.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    final avgPerTrip = _jobs.isNotEmpty ? _totalSalary / _jobs.length : 0;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(t.t('earnings_title') ?? 'My Earnings'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _hero(context, avgPerTrip, t)),
            SliverToBoxAdapter(child: _periodChips(context, t)),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(context, Icons.error_outline, _error!),
              )
            else if (_jobs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(
                  context,
                  Icons.event_busy_outlined,
                  (t.t('earnings_empty_template') ?? 'No completed trips in {period}')
                      .replaceFirst('{period}', _period.label(t).toLowerCase()),
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _sectionHeader(context, t.t('earnings_section_trips') ?? 'TRIPS', _jobs.length)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: _jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _TripCard(
                    job: _jobs[i],
                    onTap: () => _openJobSettlement(_jobs[i]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, num avgPerTrip, LocalizationProvider t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_gradStart, _gradEnd],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _gradEnd.withOpacity(0.30),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
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
                    _period.label(t).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 22),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              t.t('earnings_you_earned') ?? 'You earned',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _currency0.format(_totalSalary),
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
                Expanded(child: _heroStat(Icons.local_shipping_outlined, _jobs.length.toString(),
                    _jobs.length == 1
                        ? (t.t('earnings_trip_one') ?? 'trip')
                        : (t.t('earnings_trip_many') ?? 'trips'))),
                Container(width: 1, height: 32, color: Colors.white.withOpacity(0.18)),
                Expanded(child: _heroStat(Icons.trending_up_rounded,
                    _jobs.isEmpty ? '—' : _currency0.format(avgPerTrip),
                    t.t('earnings_avg_per_trip') ?? 'avg/trip')),
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

  Widget _periodChips(BuildContext context, LocalizationProvider t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: _Period.values.map((p) {
          final selected = p == _period;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () {
                  if (p != _period) {
                    setState(() => _period = p);
                    _fetch();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? _gradStart : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    p.shortLabel(t),
                    style: TextStyle(
                      color: selected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
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
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onTap;
  const _TripCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    final share = double.tryParse('${job['salary_share'] ?? 0}') ?? 0;
    final endAt = job['end_at']?.toString();
    DateTime? endDate;
    if (endAt != null && endAt.isNotEmpty) {
      try { endDate = DateTime.parse(endAt).toLocal(); } catch (_) {}
    }
    final title = (job['title']?.toString() ?? '').trim();
    final displayTitle = title.isEmpty ? (t.t('earnings_trip_default_title') ?? 'Trip') : title;

    return Material(
      color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Calendar pill — month above, day below
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _gradStart.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      endDate != null ? DateFormat('MMM').format(endDate).toUpperCase() : '—',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _gradStart,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      endDate != null ? endDate.day.toString() : '—',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _moneyColor,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    if (endDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _shortDateFmt.format(endDate),
                        style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _currency2.format(share),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: _moneyColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
