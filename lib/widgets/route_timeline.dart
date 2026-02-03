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
        
        // Check collision (Vehicle vs Stops) - Hide vehicle if overlapping stop
        // Vehicle pos logic: left: halfMarker + (lineWidth * progress) - 12
        // Stop pos logic: left: leftPos (lineWidth * t)
        // Threshold: markerSize (30) / 2 = 15 approx. Let's use 10px tolerance.
        
        bool isOverlapping = false;
        final double vehicleActualLeft = (lineWidth * progress.clamp(0.0, 1.0)); // Relative to line start
        
        for (int i = 0; i < stopCount; i++) {
            final stop = stops![i];
            double t = 0.0;
            if (stop.containsKey('proportional_position')) {
                t = (stop['proportional_position'] as num).toDouble();
            } else {
                t = stopCount > 1 ? i / (stopCount - 1) : 0.0;
            }
            final double stopLeft = lineWidth * t;
            
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
                  
                  // Stop markers
                  ...List.generate(stopCount, (index) {
                    final stop = stops![index];
                    final activity = stop['activity'] as String?;
                    final isSelected = selectedStopIndex == index;
                    
                    // 0.0 to 1.0 along the line (Priority: Proportional Position)
                    double t = 0.0;
                    if (stop.containsKey('proportional_position')) {
                        t = (stop['proportional_position'] as num).toDouble();
                    } else {
                        // Fallback to equal spacing
                        t = stopCount > 1 ? index / (stopCount - 1) : 0.0;
                    }
                    
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

            // Stop labels (A, B, C...) - Using Stack for precise alignment
            SizedBox(
               height: 20,
               width: totalWidth,
               child: Stack(
                 children: List.generate(stopCount, (index) {
                   final stop = stops![index];
                   final activity = stop['activity'] as String?;
                   final isSelected = selectedStopIndex == index;
                   
                   double t = stop.containsKey('proportional_position') 
                      ? (stop['proportional_position'] as num).toDouble() 
                      : (stopCount > 1 ? index / (stopCount - 1) : 0.0);
                      
                   final double leftPos = lineWidth * t; // Same calculation as markers
                   
                   return Positioned(
                      left: leftPos,
                      width: markerSize, // Center within the marker width
                      child: InkWell(
                         onTap: () {
                            if (onStopTap != null) onStopTap!(index);
                         },
                         child: Text(
                           _getStopLabel(index),
                           textAlign: TextAlign.center,
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
