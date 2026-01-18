
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/leaderboard_service.dart';
import 'api_config.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadDriverId();
  }

  Future<void> _loadDriverId() async {
    final id = await ApiConfig.getDriverId();
    if (mounted) {
      setState(() {
        _currentDriverId = id;
      });
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Leaderboard', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip('This Month', LeaderboardPeriod.month),
                const SizedBox(width: 12),
                _buildFilterChip('This Week', LeaderboardPeriod.week),
                const SizedBox(width: 12),
                _buildFilterChip('All Time', LeaderboardPeriod.all),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty 
                    ? Center(child: Text("No drivers found", style: GoogleFonts.inter(color: Colors.white54)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isMe = entry.id == _currentDriverId;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isMe ? const Color(0xFF1E1E1E) : const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(16),
                              border: isMe ? Border.all(color: Colors.green.withOpacity(0.5)) : null,
                              boxShadow: isMe ? [BoxShadow(color: Colors.green.withOpacity(0.1), blurRadius: 10)] : null,
                            ),
                            child: Row(
                              children: [
                                // Rank
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _getRankColor(entry.rank),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '#${entry.rank}',
                                    style: GoogleFonts.outfit(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                // Avatar & Name
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey[800],
                                  backgroundImage: entry.avatarUploadId != null
                                    ? NetworkImage('${ApiConfig.baseUrl.replaceAll("/api", "")}/uploads/get/${entry.avatarUploadId}?thumb=true')
                                    : null,
                                  child: entry.avatarUploadId == null
                                      ? const Icon(Icons.person, color: Colors.white54)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.name,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (isMe)
                                        Text(
                                          'You',
                                          style: GoogleFonts.inter(
                                            color: Colors.green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                
                                // Stats
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${entry.distanceKm.toStringAsFixed(1)} km',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4)
                                        ),
                                        child: Text(
                                          '${entry.mileage.toStringAsFixed(1)} km/l',
                                          style: GoogleFonts.inter(
                                            color: Colors.blueAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, LeaderboardPeriod period) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriod = period;
        });
        _loadData(); // Reload data
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

  Color _getRankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700); // Gold
    if (rank == 2) return const Color(0xFFC0C0C0); // Silver
    if (rank == 3) return const Color(0xFFCD7F32); // Bronze
    return Colors.white;
  }
}
