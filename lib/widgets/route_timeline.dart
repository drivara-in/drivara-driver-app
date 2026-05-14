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

  double _stopPosition(int index, int stopCount) {
    final stop = stops![index];
    if (stop.containsKey('proportional_position')) {
      return (stop['proportional_position'] as num).toDouble();
    }
    return stopCount > 1 ? index / (stopCount - 1) : 0.0;
  }

  /// Group stops whose marker positions overlap into clusters.
  /// Returns clusters of stop indices, ordered by position along the timeline.
  List<List<int>> _buildClusters(double lineWidth, int stopCount, double overlapPx) {
    final positions = List<double>.generate(
      stopCount,
      (i) => lineWidth * _stopPosition(i, stopCount),
    );
    final sorted = List<int>.generate(stopCount, (i) => i)
      ..sort((a, b) => positions[a].compareTo(positions[b]));

    final clusters = <List<int>>[];
    List<int>? cur;
    for (final idx in sorted) {
      if (cur == null) {
        cur = [idx];
        continue;
      }
      final lastPos = positions[cur.last];
      if ((positions[idx] - lastPos).abs() < overlapPx) {
        cur.add(idx);
      } else {
        clusters.add(cur);
        cur = [idx];
      }
    }
    if (cur != null) clusters.add(cur);
    return clusters;
  }

  void _showClusterDisambiguation(BuildContext context, List<int> indices) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    Provider.of<LocalizationProvider>(context, listen: false)
                        .t('multiple_stops_here'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    Provider.of<LocalizationProvider>(context, listen: false)
                        .t('pick_the_correct_stop'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: indices.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final idx = indices[i];
                    final s = stops![idx];
                    final activity = s['activity'] as String?;
                    final addr = (s['address'] ?? s['label'] ?? 'Stop ${idx + 1}')
                        .toString();
                    final isSelected = selectedStopIndex == idx;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getActivityColor(activity),
                        child: Text(
                          _getStopLabel(idx),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        addr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: activity != null && activity.isNotEmpty
                          ? Text(activity.toUpperCase())
                          : null,
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: activeColor)
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        if (onStopTap != null) onStopTap!(idx);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
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

        // Detect overlapping stops and group them into clusters so the driver
        // can disambiguate via a bottom sheet when two stops are visually
        // stacked on the timeline.
        const double overlapThresholdPx = markerSize * 0.7;
        final clusters =
            _buildClusters(lineWidth, stopCount, overlapThresholdPx);

        // Check collision (Vehicle vs Stops) - Hide vehicle if overlapping stop
        // Vehicle pos logic: left: halfMarker + (lineWidth * progress) - 12
        // Stop pos logic: left: leftPos (lineWidth * t)
        // Threshold: markerSize (30) / 2 = 15 approx. Let's use 10px tolerance.

        bool isOverlapping = false;
        final double vehicleActualLeft = (lineWidth * progress.clamp(0.0, 1.0)); // Relative to line start

        for (int i = 0; i < stopCount; i++) {
            final double stopLeft = lineWidth * _stopPosition(i, stopCount);

            if ((vehicleActualLeft - stopLeft).abs() < 15.0) { // Increased threshold to 15px to cover the marker radius
                isOverlapping = true;
                break;
            }
        }

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
                  
                  // Stop markers (cluster-aware: collapses overlapping stops
                  // into a single cluster marker so the driver can pick
                  // explicitly from a bottom sheet).
                  ...clusters.map((cluster) {
                    if (cluster.length == 1) {
                      final index = cluster.first;
                      final stop = stops![index];
                      final activity = stop['activity'] as String?;
                      final isSelected = selectedStopIndex == index;
                      final double leftPos =
                          lineWidth * _stopPosition(index, stopCount);

                      return Positioned(
                        left: leftPos,
                        top: 4,
                        child: GestureDetector(
                          onTap: () {
                            if (onStopTap != null) onStopTap!(index);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: isSelected ? 40 : markerSize,
                            height: isSelected ? 40 : markerSize,
                            decoration: BoxDecoration(
                              color: _getActivityColor(activity),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.8),
                                width: isSelected ? 4 : 2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: _getActivityColor(activity)
                                            .withOpacity(0.5),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _getActivityIcon(activity),
                              size: isSelected ? 20 : 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    }

                    // Cluster of 2+ overlapping stops: render a stacked
                    // marker with a count badge. Tap → disambiguation sheet.
                    final containsSelected = selectedStopIndex != null &&
                        cluster.contains(selectedStopIndex);
                    final repIndex = containsSelected
                        ? selectedStopIndex!
                        : cluster.first;
                    final activity = stops![repIndex]['activity'] as String?;
                    final repColor = _getActivityColor(activity);
                    final double avgT = cluster
                            .map((i) => _stopPosition(i, stopCount))
                            .reduce((a, b) => a + b) /
                        cluster.length;
                    final double leftPos = lineWidth * avgT;
                    final size = containsSelected ? 40.0 : markerSize;

                    return Positioned(
                      left: leftPos,
                      top: 4,
                      child: GestureDetector(
                        onTap: () =>
                            _showClusterDisambiguation(context, cluster),
                        child: SizedBox(
                          width: size + 6,
                          height: size + 6,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Back card (offset) to suggest a stack.
                              Positioned(
                                left: 4,
                                top: 4,
                                child: Container(
                                  width: size,
                                  height: size,
                                  decoration: BoxDecoration(
                                    color: repColor.withOpacity(0.55),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.6),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              // Front card.
                              Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  color: repColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: containsSelected
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.85),
                                    width: containsSelected ? 4 : 2,
                                  ),
                                  boxShadow: containsSelected
                                      ? [
                                          BoxShadow(
                                            color: repColor.withOpacity(0.5),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  Icons.layers,
                                  size: containsSelected ? 20 : 16,
                                  color: Colors.white,
                                ),
                              ),
                              // Count badge.
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                  child: Text(
                                    '${cluster.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // Vehicle Icon Head (Moved to end for Z-Index)
                  if (!isOverlapping)
                    Positioned(
                      top: 13, // (48 - 24 icon) / 2 = 12ish, adjustments for center. Line is at top 21 height 6. Center ~24. Icon 24 center.
                      left: halfMarker + (lineWidth * progress.clamp(0.0, 1.0)) - 12, // -12 to center the 24px icon horizontally
                      child: Container(
                          decoration: BoxDecoration(
                             color: Colors.white,
                             shape: BoxShape.circle,
                             boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]
                          ), 
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.local_shipping, size: 16, color: activeColor)
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Stop labels (A, B, C...) — cluster-aware: a single label per
            // cluster (e.g. "A,B" or "A+2") so labels never visually stack.
            SizedBox(
               height: 20,
               width: totalWidth,
               child: Stack(
                 children: clusters.map((cluster) {
                   final activity = stops![cluster.first]['activity'] as String?;
                   final containsSelected = selectedStopIndex != null &&
                       cluster.contains(selectedStopIndex);
                   final double avgT = cluster
                           .map((i) => _stopPosition(i, stopCount))
                           .reduce((a, b) => a + b) /
                       cluster.length;
                   final double leftPos = lineWidth * avgT;

                   String labelText;
                   if (cluster.length == 1) {
                     labelText = _getStopLabel(cluster.first);
                   } else if (cluster.length == 2) {
                     labelText =
                         '${_getStopLabel(cluster[0])},${_getStopLabel(cluster[1])}';
                   } else {
                     labelText =
                         '${_getStopLabel(cluster.first)}+${cluster.length - 1}';
                   }

                   return Positioned(
                      left: leftPos,
                      width: markerSize,
                      child: InkWell(
                         onTap: () {
                            if (cluster.length == 1) {
                              if (onStopTap != null) onStopTap!(cluster.first);
                            } else {
                              _showClusterDisambiguation(context, cluster);
                            }
                         },
                         child: Text(
                           labelText,
                           textAlign: TextAlign.center,
                           style: TextStyle(
                             color: _getActivityColor(activity),
                             fontSize: containsSelected ? 12 : 10,
                             fontWeight: containsSelected
                                 ? FontWeight.w900
                                 : FontWeight.bold,
                           ),
                         ),
                      ),
                   );
                 }).toList(),
               ),
            ),
            
            // Address Display (New)
            if (selectedStopIndex != null && selectedStopIndex! < stops!.length)
               Padding(
                 padding: const EdgeInsets.only(top: 8.0),
                 child: Container(
                   width: double.infinity,
                   padding: const EdgeInsets.all(8),
                   decoration: BoxDecoration(
                     color: _getActivityColor(stops![selectedStopIndex!]['activity']).withOpacity(0.1),
                     borderRadius: BorderRadius.circular(8),
                     border: Border.all(color: _getActivityColor(stops![selectedStopIndex!]['activity']).withOpacity(0.3))
                   ),
                   child: Row(
                     children: [
                        Icon(Icons.location_on, size: 16, color: _getActivityColor(stops![selectedStopIndex!]['activity'])),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                             stops![selectedStopIndex!]['address'] ?? "Unknown Location",
                             style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                             maxLines: 2,
                             overflow: TextOverflow.ellipsis,
                          ),
                        ),
                     ],
                   ),
                 ),
               ),
          ],
        );
      },
    );
  }
}
