import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/leaderboard_service.dart';
import 'api_config.dart';
import 'providers/localization_provider.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final LeaderboardService _service = LeaderboardService();
  List<LeaderboardEntry> _entries = [];
  bool _isLoading = true;
  LeaderboardPeriod _selectedPeriod = LeaderboardPeriod.month;
  String? _currentDriverId;
  // Indices of rows where the driver tapped "Details" — show the inline
  // breakdown (per-violation counts + driver-friendly explanations).
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadDriverId();
  }

  Future<void> _loadDriverId() async {
    final id = await ApiConfig.getDriverId();
    if (mounted) setState(() => _currentDriverId = id);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _service.getLeaderboard(period: _selectedPeriod);
    if (mounted) {
      setState(() {
        _entries = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = Provider.of<LocalizationProvider>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(loc.t('leaderboard'),
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Period picker
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  _filterChip(loc.t('this_month'), LeaderboardPeriod.month),
                  const SizedBox(width: 12),
                  _filterChip(loc.t('this_week'), LeaderboardPeriod.week),
                  const SizedBox(width: 12),
                  _filterChip(loc.t('all_time'), LeaderboardPeriod.all),
                ],
              ),
            ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              )
            else if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 80),
                child: Center(
                  child: Text(loc.t('no_drivers_found'),
                      style: GoogleFonts.inter(color: Colors.white54)),
                ),
              )
            else ...[
              // Top-3 podium (only when we have at least 3 entries; otherwise
              // skip and just render the list).
              if (_entries.length >= 3) _podium(loc),

              // The full ranked list. When the podium is shown we still
              // include all entries below it (including the top 3 again,
              // for a complete view).
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                itemCount: _entries.length,
                itemBuilder: (context, i) => _entryCard(_entries[i], loc),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Top-3 podium ────────────────────────────────────────────────────────
  Widget _podium(LocalizationProvider loc) {
    final top = _entries.take(3).toList();
    // Order on screen: rank 2 (left, lower), rank 1 (centre, tallest), rank 3 (right, lowest)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _podiumPillar(top[1], height: 110, color: const Color(0xFFC0C0C0), loc: loc)),
          const SizedBox(width: 8),
          Expanded(child: _podiumPillar(top[0], height: 140, color: const Color(0xFFFFD700), loc: loc, crown: true)),
          const SizedBox(width: 8),
          Expanded(child: _podiumPillar(top[2], height: 90, color: const Color(0xFFCD7F32), loc: loc)),
        ],
      ),
    );
  }

  Widget _podiumPillar(LeaderboardEntry e,
      {required double height,
      required Color color,
      required LocalizationProvider loc,
      bool crown = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crown) const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 22),
        const SizedBox(height: 2),
        CircleAvatar(
          radius: crown ? 28 : 22,
          backgroundColor: Colors.grey[800],
          backgroundImage: e.avatarUrl != null ? NetworkImage(e.avatarUrl!) : null,
          child: e.avatarUrl == null
              ? Icon(Icons.person, color: Colors.white54, size: crown ? 28 : 22)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          e.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: color.withOpacity(0.25),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border.all(color: color.withOpacity(0.6)),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${e.score}',
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: crown ? 28 : 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                loc.t('score_label') ?? 'Score',
                style: GoogleFonts.inter(
                  color: color.withOpacity(0.85),
                  fontSize: 9,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '#${e.rank}',
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Individual driver card (collapsed → expandable) ─────────────────────
  Widget _entryCard(LeaderboardEntry e, LocalizationProvider loc) {
    final isMe = e.id == _currentDriverId;
    final expanded = _expandedIds.contains(e.id);
    final scoreColor = _scoreColor(e.score);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF1E2A1E) : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: isMe
            ? Border.all(color: Colors.green.withOpacity(0.5))
            : Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedIds.remove(e.id);
                } else {
                  _expandedIds.add(e.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Rank pill
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _rankColor(e.rank),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${e.rank}',
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: e.avatarUrl != null ? NetworkImage(e.avatarUrl!) : null,
                    child: e.avatarUrl == null
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.name,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  loc.t('you') ?? 'You',
                                  style: GoogleFonts.inter(
                                    color: Colors.greenAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _miniChip(
                              icon: Icons.straighten,
                              text: '${e.distanceKm.toStringAsFixed(0)} ${loc.t('unit_km') ?? 'km'}',
                              color: Colors.white70,
                            ),
                            if (e.loadedMileage != null)
                              _miniChip(
                                icon: Icons.inventory_2,
                                text: '${e.loadedMileage!.toStringAsFixed(1)} ${loc.t('unit_kmpl_short') ?? 'km/L'}',
                                color: Colors.lightBlueAccent,
                                tooltip: loc.t('loaded_mileage') ?? 'Loaded mileage',
                              ),
                            if (e.emptyMileage != null)
                              _miniChip(
                                icon: Icons.outbox,
                                text: '${e.emptyMileage!.toStringAsFixed(1)} ${loc.t('unit_kmpl_short') ?? 'km/L'}',
                                color: Colors.cyanAccent,
                                tooltip: loc.t('empty_mileage') ?? 'Empty mileage',
                              ),
                            if (e.violations.total > 0)
                              _miniChip(
                                icon: Icons.warning_amber,
                                text: '${e.violations.total}',
                                color: Colors.orangeAccent,
                                tooltip: loc.t('total_violations') ?? 'Total violations',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Score column
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${e.score}',
                        style: GoogleFonts.outfit(
                          color: scoreColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        loc.t('score_label') ?? 'Score',
                        style: GoogleFonts.inter(
                          color: scoreColor.withOpacity(0.7),
                          fontSize: 9,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: Colors.white38),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _expandedDetails(e, loc),
        ],
      ),
    );
  }

  // ── Expanded details: violations explained, mileage breakdown ───────────
  Widget _expandedDetails(LeaderboardEntry e, LocalizationProvider loc) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white12, height: 16),
          // Mileage breakdown (loaded vs empty side by side)
          Row(
            children: [
              Expanded(
                child: _statBlock(
                  label: loc.t('loaded_mileage') ?? 'Loaded mileage',
                  value: e.loadedMileage != null
                      ? '${e.loadedMileage!.toStringAsFixed(2)} ${loc.t('unit_kmpl_short') ?? 'km/L'}'
                      : '—',
                  sub: loc.t('with_cargo') ?? 'with cargo',
                  color: Colors.lightBlueAccent,
                  icon: Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBlock(
                  label: loc.t('empty_mileage') ?? 'Empty mileage',
                  value: e.emptyMileage != null
                      ? '${e.emptyMileage!.toStringAsFixed(2)} ${loc.t('unit_kmpl_short') ?? 'km/L'}'
                      : '—',
                  sub: loc.t('no_cargo') ?? 'no cargo',
                  color: Colors.cyanAccent,
                  icon: Icons.outbox,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (loc.t('violations_section_title') ?? 'Driving safety').toUpperCase(),
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // Violation rows (driver-friendly explanations)
          _violationRow(
            icon: Icons.speed,
            color: Colors.orangeAccent,
            label: loc.t('viol_speed_label') ?? 'Driving too fast',
            sub: loc.t('viol_speed_sub') ?? 'Speed crossed 80 km/h',
            count: e.violations.speed,
            zeroMsg: loc.t('all_within_speed') ?? 'All within speed limit',
          ),
          _violationRow(
            icon: Icons.fitness_center,
            color: Colors.amberAccent,
            label: loc.t('viol_rpm_label') ?? 'Engine over-revving',
            sub: loc.t('viol_rpm_sub') ?? 'RPM crossed 2400',
            count: e.violations.rpm,
            zeroMsg: loc.t('all_within_rpm') ?? 'Engine RPM healthy',
          ),
          _violationRow(
            icon: Icons.flash_on,
            color: Colors.redAccent,
            label: loc.t('viol_impact_label') ?? 'Hard driving',
            sub: loc.t('viol_impact_sub') ?? 'High speed + high RPM together',
            count: e.violations.impact,
            zeroMsg: loc.t('no_hard_driving') ?? 'No hard driving',
          ),
          _violationRow(
            icon: Icons.swap_calls,
            color: Colors.purpleAccent,
            label: loc.t('viol_harsh_label') ?? 'Sudden moves',
            sub: loc.t('viol_harsh_sub') ?? 'Hard brake / accel / sharp turn',
            count: e.violations.harsh,
            zeroMsg: loc.t('smooth_driving') ?? 'Smooth driving',
          ),
        ],
      ),
    );
  }

  Widget _miniChip({required IconData icon, required String text, required Color color, String? tooltip}) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: w) : w;
  }

  Widget _statBlock({required String label, required String value, String? sub, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: color.withOpacity(0.85),
                    fontSize: 9,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sub != null)
            Text(
              sub,
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _violationRow({
    required IconData icon,
    required Color color,
    required String label,
    required String sub,
    required int count,
    required String zeroMsg,
  }) {
    final isClean = count == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(isClean ? Icons.check_circle : icon, color: isClean ? Colors.greenAccent : color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isClean ? zeroMsg : sub,
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (!isClean)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, LeaderboardPeriod period) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPeriod = period);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(24),
          border: isSelected ? null : Border.all(color: Colors.white12),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700); // Gold
    if (rank == 2) return const Color(0xFFC0C0C0); // Silver
    if (rank == 3) return const Color(0xFFCD7F32); // Bronze
    return Colors.white70;
  }

  Color _scoreColor(int score) {
    if (score >= 85) return Colors.greenAccent;
    if (score >= 70) return Colors.lightGreenAccent;
    if (score >= 50) return Colors.amberAccent;
    return Colors.redAccent;
  }
}
