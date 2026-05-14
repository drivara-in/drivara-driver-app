import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';

/// Bottom sheet that shows the last N hours of a tank/gauge metric for the
/// active job. Driver taps the Fuel / DEF / Battery / Exhaust gauge → this
/// opens, fetches the history, and renders a line chart with min/max/avg.
class TankHistorySheet extends StatefulWidget {
  /// Job to fetch tank history for.
  final String jobId;

  /// Which metric to render. Must be one of: fuel, def, battery, exhaust.
  final String metric;

  /// Display label, e.g. "Fuel Level".
  final String label;

  /// Unit suffix, e.g. "L", "V", "°C".
  final String unit;

  /// Accent colour for the line + fill gradient.
  final Color color;

  /// How many hours back to fetch. Default 24.
  final int hours;

  const TankHistorySheet({
    super.key,
    required this.jobId,
    required this.metric,
    required this.label,
    required this.unit,
    required this.color,
    this.hours = 24,
  });

  static Future<void> open(
    BuildContext context, {
    required String jobId,
    required String metric,
    required String label,
    required String unit,
    required Color color,
    int hours = 24,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TankHistorySheet(
        jobId: jobId,
        metric: metric,
        label: label,
        unit: unit,
        color: color,
        hours: hours,
      ),
    );
  }

  @override
  State<TankHistorySheet> createState() => _TankHistorySheetState();
}

class _TankHistorySheetState extends State<TankHistorySheet> {
  bool _loading = true;
  String? _error;
  List<_Sample> _samples = const [];
  double? _tankCapacity;
  // Engine-bus channels (def, exhaust, etc.) freeze when truck is shut
  // down. Server returns the last snapshot value + timestamp so we can
  // surface "Sensor offline since X · last reading 28 L" instead of
  // an empty chart.
  _LastKnown? _lastKnown;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final r = await ApiConfig.dio.get(
        '/driver/jobs/${widget.jobId}/tank-history',
        queryParameters: {'hours': widget.hours},
      );
      final data = r.data as Map<String, dynamic>;
      final raw = (data[widget.metric] as List?) ?? const [];
      final samples = raw
          .map((e) {
            final m = e as Map<String, dynamic>;
            final t = (m['t'] as num?)?.toInt();
            final v = (m['v'] as num?)?.toDouble();
            if (t == null || v == null) return null;
            return _Sample(DateTime.fromMillisecondsSinceEpoch(t), v);
          })
          .whereType<_Sample>()
          .toList();

      double? tank;
      if (widget.metric == 'fuel') {
        tank = (data['fuelTankL'] as num?)?.toDouble();
      } else if (widget.metric == 'def') {
        tank = (data['defTankL'] as num?)?.toDouble();
      }

      _LastKnown? lastKnown;
      final lkMap = data['lastKnown'] as Map<String, dynamic>?;
      final lkRaw = lkMap == null ? null : lkMap[widget.metric];
      if (lkRaw is Map<String, dynamic>) {
        final v = (lkRaw['value'] as num?)?.toDouble();
        final ts = (lkRaw['ts'] as num?)?.toInt();
        if (v != null && ts != null) {
          lastKnown = _LastKnown(
            value: v,
            ts: DateTime.fromMillisecondsSinceEpoch(ts),
            isStale: lkRaw['isStale'] == true,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _samples = samples;
        _tankCapacity = tank;
        _lastKnown = lastKnown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final t = Provider.of<LocalizationProvider>(context, listen: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_iconFor(widget.metric), color: widget.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          (t.t('last_n_hours') ?? 'Last {hours} hour{plural}')
                              .replaceAll('{hours}', '${widget.hours}')
                              .replaceAll('{plural}', widget.hours == 1 ? '' : 's'),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: _buildBody(theme, t),
              ),
              if (!_loading && _error == null && _samples.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildStatsRow(theme, t),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, LocalizationProvider t) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: widget.color),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${t.t('history_load_error') ?? 'Could not load history.'}\n$_error',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    if (_samples.isEmpty) {
      // Engine-bus channels (def, exhaust, coolant, etc.) stop publishing
      // when the truck shuts down. If the server returned a last-known
      // snapshot we surface it here so the driver sees "last reading"
      // instead of a blank chart.
      final last = _lastKnown;
      if (last != null) {
        final ageDays = DateTime.now().difference(last.ts).inDays;
        final ageLabel = ageDays > 0
            ? '${DateFormat('d MMM').format(last.ts.toLocal())} (${ageDays}d ago)'
            : DateFormat('HH:mm').format(last.ts.toLocal());
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.power_settings_new, size: 28, color: theme.hintColor),
                const SizedBox(height: 8),
                Text(
                  t.t('sensor_offline') ?? 'Sensor offline',
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (t.t('no_samples_idle') ?? 'No samples in the last {hours}h — vehicle was idle.')
                      .replaceAll('{hours}', '${widget.hours}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.color.withOpacity(0.25)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.t('last_reading_label') ?? 'LAST READING',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${last.value.toStringAsFixed(widget.metric == 'exhaust' || widget.metric == 'battery' ? 1 : 0)} ${widget.unit}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: widget.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ageLabel,
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 32, color: theme.hintColor),
            const SizedBox(height: 8),
            Text(
              (t.t('no_data_in_window') ?? 'No data in the last {hours} hours')
                  .replaceAll('{hours}', '${widget.hours}'),
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final spots = <FlSpot>[];
    for (final s in _samples) {
      spots.add(FlSpot(s.t.millisecondsSinceEpoch.toDouble(), s.v));
    }
    final values = _samples.map((s) => s.v).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxVal - minVal).abs() * 0.1).clamp(0.5, 50.0);
    // For fuel/DEF, anchor the lower bound at 0 so the chart shows context
    // (e.g. how full the tank actually is). For battery/exhaust use the
    // min-with-padding because the relevant range is tight.
    final isTank = widget.metric == 'fuel' || widget.metric == 'def';
    final yMin = isTank ? 0.0 : (minVal - pad);
    final yMax = isTank
        ? (_tankCapacity != null && _tankCapacity! > 0
            ? _tankCapacity!
            : (maxVal + pad))
        : (maxVal + pad);

    final tStart = spots.first.x;
    final tEnd = spots.last.x;
    final tSpan = (tEnd - tStart).clamp(1, double.infinity);

    return LineChart(
      LineChartData(
        minX: tStart,
        maxX: tEnd,
        minY: yMin,
        maxY: yMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.dividerColor.withOpacity(0.3),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) {
                if (v == meta.min || v == meta.max || (v - meta.min).abs() < 0.001) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    v.toStringAsFixed(isTank ? 0 : 1),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: tSpan / 4,
              getTitlesWidget: (v, meta) {
                final dt = DateTime.fromMillisecondsSinceEpoch(v.toInt());
                final fmt = widget.hours <= 24
                    ? DateFormat.Hm()
                    : DateFormat('MMM d HH:mm');
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    fmt.format(dt),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => widget.color,
            tooltipRoundedRadius: 6,
            getTooltipItems: (touched) => touched.map((spot) {
              final dt = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
              final tStr = DateFormat('MMM d, HH:mm').format(dt);
              final vStr = spot.y.toStringAsFixed(isTank ? 0 : 1);
              return LineTooltipItem(
                '$vStr ${widget.unit}\n$tStr',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            barWidth: 2,
            color: widget.color,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.color.withOpacity(0.25),
                  widget.color.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme, LocalizationProvider t) {
    final values = _samples.map((s) => s.v).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final avgVal = values.reduce((a, b) => a + b) / values.length;
    final latest = _samples.last.v;
    final isTank = widget.metric == 'fuel' || widget.metric == 'def';
    final dec = isTank ? 0 : 1;

    Widget cell(String label, String value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        cell(t.t('stat_latest') ?? 'Latest', '${latest.toStringAsFixed(dec)} ${widget.unit}'),
        cell(t.t('stat_min') ?? 'Min', '${minVal.toStringAsFixed(dec)} ${widget.unit}'),
        cell(t.t('stat_avg') ?? 'Avg', '${avgVal.toStringAsFixed(dec)} ${widget.unit}'),
        cell(t.t('stat_max') ?? 'Max', '${maxVal.toStringAsFixed(dec)} ${widget.unit}'),
      ],
    );
  }

  IconData _iconFor(String metric) {
    switch (metric) {
      case 'fuel':
        return Icons.local_gas_station;
      case 'def':
        return Icons.opacity;
      case 'battery':
        return Icons.battery_charging_full;
      case 'exhaust':
        return Icons.local_fire_department;
      default:
        return Icons.show_chart;
    }
  }
}

class _Sample {
  final DateTime t;
  final double v;
  _Sample(this.t, this.v);
}

class _LastKnown {
  final double value;
  final DateTime ts;
  final bool isStale;
  _LastKnown({required this.value, required this.ts, required this.isStale});
}
