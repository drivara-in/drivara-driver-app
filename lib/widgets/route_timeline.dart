import 'package:flutter/material.dart';

class RouteTimelineWidget extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;

  const RouteTimelineWidget({
    super.key,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline Bar
            Stack(
              children: [
                // Background Line
                Container(
                  height: 6,
                  width: width,
                  decoration: BoxDecoration(
                    color: inactiveColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Progress Line
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  height: 6,
                  width: width * progress.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Start", style: TextStyle(color: inactiveColor, fontSize: 10)),
                Text("${(progress * 100).toStringAsFixed(0)}%", style: TextStyle(color: activeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                Text("End", style: TextStyle(color: inactiveColor, fontSize: 10)),
              ],
            )
          ],
        );
      },
    );
  }
}
