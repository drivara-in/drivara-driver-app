
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'leaderboard_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme base
      appBar: AppBar(
        title: Text('Drivara Dashboard', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
            const SizedBox(height: 16),
             Text(
              'You are all set!',
              style: GoogleFonts.outfit(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
            ),
             const SizedBox(height: 8),
             Text(
              'Permissions granted. Ready to drive.',
              style: GoogleFonts.inter(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LeaderboardPage()),
                  );
              },
              icon: const Icon(Icons.leaderboard, color: Colors.black),
              label: Text('View Leaderboard', style: GoogleFonts.outfit(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
