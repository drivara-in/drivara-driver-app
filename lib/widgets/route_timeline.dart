import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/localization_provider.dart';

class RouteTimelineWidget extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final Color activeColor;
  final Color inactiveColor;
  final List<Map<String, dynamic>>? stops; // Optional stops data

  final Function(int)? onStopTap;
  final int? selectedStopIndex;

  const RouteTimelineWidget({
    super.key,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.stops,
    this.onStopTap,
    this.selectedStopIndex,
  });

  String _getStopLabel(int index) {
    // Return A, B, C, etc.
    return String.fromCharCode(65 + index); // 65 is 'A' in ASCII
  }

  IconData _getActivityIcon(String? activity) {
    if (activity == 'loading') return Icons.upload;
    if (activity == 'unloading') return Icons.download;
    return Icons.circle_outlined;
  }

  Color _getActivityColor(String? activity) {
    if (activity == 'loading') return Colors.green;
    if (activity == 'unloading') return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    // If no stops provided, show simple start/end
    if (stops == null || stops!.isEmpty) {
      return _buildSimpleTimeline(context);
    }

    return _buildStopsTimeline(context);
  }

  Widget _buildSimpleTimeline(BuildContext context) {
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
                Text(Provider.of<LocalizationProvider>(context, listen: false).t('label_start'), style: TextStyle(color: inactiveColor, fontSize: 10)),
                Text("${(progress * 100).toStringAsFixed(0)}%", style: TextStyle(color: activeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                Text(Provider.of<LocalizationProvider>(context, listen: false).t('label_end'), style: TextStyle(color: inactiveColor, fontSize: 10)),
              ],
            )
          ],
        );
      },
    );
  }

  Widget _buildStopsTimeline(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final stopCount = stops!.length;
        
        // Ensure we reserve space for the 30px (approx) markers so they don't clip
        const double markerSize = 30.0;
        const double halfMarker = markerSize / 2;
        
        // Effective width for the connecting line
        final double lineWidth = totalWidth - markerSize; 
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline with stops
            SizedBox(
              height: 48, // Increased height for selection halo
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Background Line
                  Positioned(
                    top: 21, // Centered vertically (48/2 - 6/2)
                    left: halfMarker,
                    width: lineWidth,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: inactiveColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Progress Line
                  Positioned(
                    top: 21,
                    left: halfMarker,
                    width: lineWidth * progress.clamp(0.0, 1.0),
                    child: Container( // Changed from AnimatedContainer to avoid layout jitter during internal width changes, or keep AnimatedContainer
                      height: 6,
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Stop markers
                  ...List.generate(stopCount, (index) {
                    final stop = stops![index];
                    final activity = stop['activity'] as String?;
                    final isSelected = selectedStopIndex == index;
                    
                    // 0.0 to 1.0 along the line
                    final t = stopCount > 1 ? index / (stopCount - 1) : 0.0;
                    
                    final double leftPos = lineWidth * t;
                    
                    return Positioned(
                      left: leftPos, 
                      top: 4, // Adjust for larger container
                      child: GestureDetector(
                        onTap: () {
                           if (onStopTap != null) onStopTap!(index);
                        },
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: isSelected ? 40 : markerSize,
                              height: isSelected ? 40 : markerSize,
                              decoration: BoxDecoration(
                                color: _getActivityColor(activity),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
                                  width: isSelected ? 4 : 2,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(color: _getActivityColor(activity).withOpacity(0.5), blurRadius: 10, spreadRadius: 2)
                                ] : null
                              ),
                              child: Icon(
                                _getActivityIcon(activity),
                                size: isSelected ? 20 : 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Stop labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(stopCount, (index) {
                final stop = stops![index];
                // final label = stop['label'] as String? ?? _getStopLabel(index);
                final activity = stop['activity'] as String?;
                final isSelected = selectedStopIndex == index;
                
                return Expanded(
                  child: InkWell(
                    onTap: () {
                       if (onStopTap != null) onStopTap!(index);
                    },
                    child: Text(
                      _getStopLabel(index),
                      textAlign: index == 0 ? TextAlign.start : (index == stopCount - 1 ? TextAlign.end : TextAlign.center),
                      style: TextStyle(
                        color: _getActivityColor(activity),
                        fontSize: isSelected ? 12 : 10,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
