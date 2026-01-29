import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drivara_driver_app/widgets/tyre_widget.dart';
import 'package:provider/provider.dart';
import 'package:drivara_driver_app/providers/localization_provider.dart';


class TyreSchematic extends StatelessWidget {
  final Map<String, dynamic> layout;
  final List<String> selectedKeys;
  final Function(String source, String target) onTyreSwap;
  final Function(String key, Map<String, dynamic> details) onTyreTap;
  // Details to render inside TyreWidget. Passed from parent.
  final Map<String, dynamic> tyreDetailsLookup;

  const TyreSchematic({
    super.key,
    required this.layout,
    required this.selectedKeys,
    required this.onTyreSwap, // Callback when D&D completes
    required this.onTyreTap, // Callback for details
    required this.tyreDetailsLookup,
  });

  @override
  Widget build(BuildContext context) {
    final loc = Provider.of<LocalizationProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // InteractiveViewer allows Pan & Zoom
    // constrained: false allows the child to be larger than the viewport (scrollable canvas)
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.symmetric(horizontal: 200, vertical: 200),
      minScale: 0.1, // Allow zooming out further
      maxScale: 4.0,
      child: ConstrainedBox(
         constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width,
            minHeight: MediaQuery.of(context).size.height,
         ),
         child: Container(
             alignment: Alignment.center,
             padding: const EdgeInsets.only(top: 40, bottom: 100, left: 20, right: 20),
             child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
             // Spare Tyre Rack (Separate from Chassis)
             // Spare Tyre Rack (Separate from Chassis)
             Builder(
               builder: (context) {
                  // Find all keys starting with "SP" and sort them numeric (SP1, SP2, SP10)
                  final spareKeys = tyreDetailsLookup.keys
                      .where((k) => k.startsWith('SP'))
                      .toList();
                  
                  if (spareKeys.isEmpty) return const SizedBox.shrink();

                  spareKeys.sort((a, b) {
                      final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                      return numA.compareTo(numB);
                  });

                  return Column(
                    children: [
                     Container(
                       padding: const EdgeInsets.all(16),
                       decoration: BoxDecoration(
                         color: theme.cardColor,
                         borderRadius: BorderRadius.circular(20),
                         border: Border.all(color: theme.dividerColor, width: 2, style: BorderStyle.solid),
                       ),
                       child: Column(
                         children: [
                           Text(loc.t('spare_rack'), style: TextStyle(
                             fontSize: 10, 
                             fontWeight: FontWeight.bold, 
                             color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5),
                             letterSpacing: 1.5
                           )),
                           const SizedBox(height: 12),
                           SingleChildScrollView(
                             scrollDirection: Axis.horizontal,
                             child: Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                  for (int i = 0; i < spareKeys.length; i++) ...[
                                     if (i > 0) const SizedBox(width: 30),
                                     _buildDraggableTyre(context, spareKeys[i]),
                                  ]
                               ],
                             ),
                           ),
                         ],
                       ),
                     ),
                     const SizedBox(height: 50),
                    ],
                  );
               }
             ),


             // Main Chassis
             CustomPaint(
               painter: ChassisPainter(
                 layout: layout, 
                 color: isDark ? Colors.grey.shade700 : const Color(0xFFD0D0D0)
               ),
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     // Front Indicator
                     Icon(Icons.arrow_upward, size: 24, color: theme.disabledColor),
                     Text(loc.t('front'), style: TextStyle(
                       fontSize: 12, 
                       fontWeight: FontWeight.bold, 
                       color: theme.disabledColor,
                       letterSpacing: 2
                     )),
                     const SizedBox(height: 40),
                     
                     ..._buildAxles(context),
                   ],
                 ),
               ),
             ),
           ],
         ),
       ),
      ),
    );
  }

  List<Widget> _buildAxles(BuildContext context) {
     List<Widget> axleWidgets = [];
     final config = layout['wheelsByAxle'] as List<dynamic>? ?? [];
     final splitAfter = layout['splitAfter'] as int; // e.g. 0 means after axle 1

     for (int i = 0; i < config.length; i++) {
        final axleNum = i + 1;
        final count = config[i] as int;
        
        // Trailer split visual
        if (i == splitAfter + 1 && splitAfter != -1) {
           axleWidgets.add(_buildTrailerConnector());
           axleWidgets.add(const SizedBox(height: 30));
        }
        
        axleWidgets.add(_buildAxleRow(context, axleNum, count));
        axleWidgets.add(const SizedBox(height: 50)); // Large spacing between axles
     }
     
     return axleWidgets;
  }
  
  Widget _buildTrailerConnector() {
    return SizedBox(
      height: 40,
      child: Center(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]
          ),
        ),
      ),
    );
  }

  Widget _buildAxleRow(BuildContext context, int axleNum, int wheelCount) {
     List<Widget> wheels = [];
     
     // 2 types: standard (2 wheels) or dual (4 wheels)
     if (wheelCount == 2) {
       wheels = [
         _buildDraggableTyre(context, "A$axleNum-L"),
         const SizedBox(width: 80), // Wide gap for chassis
         _buildDraggableTyre(context, "A$axleNum-R"),
       ];
     } else if (wheelCount == 4) {
       wheels = [
         _buildDraggableTyre(context, "A$axleNum-LO"),
         const SizedBox(width: 8),
         _buildDraggableTyre(context, "A$axleNum-LI"),
         const SizedBox(width: 80),
         _buildDraggableTyre(context, "A$axleNum-RI"),
         const SizedBox(width: 8),
         _buildDraggableTyre(context, "A$axleNum-RO"),
       ];
     } else {
        // Generic fallback
        for(int k=0; k<wheelCount; k++) {
           wheels.add(_buildDraggableTyre(context, "A$axleNum-W${k+1}"));
           if (k < wheelCount-1) wheels.add(const SizedBox(width: 8));
        }
     }
     
     return Row(
       mainAxisSize: MainAxisSize.min,
       children: wheels,
     );
  }

  Widget _buildDraggableTyre(BuildContext context, String key) {
    final details = Map<String, dynamic>.from(tyreDetailsLookup[key] ?? {});
    
    return DragTarget<String>(
      onWillAccept: (inputKey) => inputKey != key,
      onAccept: (sourceKey) {
          HapticFeedback.heavyImpact();
          onTyreSwap(sourceKey, key);
      },
      builder: (context, candidateData, rejectedData) {
         final isTarget = candidateData.isNotEmpty;
         final isSource = key == ""; // We don't easily track isSource here anymore without state, relying on visual feedback pill
         
         return LongPressDraggable<String>(
           data: key,
           delay: const Duration(milliseconds: 200), // Prevent accidental drags
           feedback: Material(
             color: Colors.transparent,
             elevation: 0,
             child: Transform.scale(
               scale: 1.2,
               child: TyreWidget(
                 positionKey: key, 
                 details: details, 
                 isSelected: true, // Highlight style
                 isSource: true,
                 onTap: (){},
               ),
             ),
           ),
           childWhenDragging: Opacity(
             opacity: 0.2, // Ghost
             child: TyreWidget(positionKey: key, details: details, isSelected: false, isSource: false, onTap: (){}),
           ),
           onDragStarted: () => HapticFeedback.selectionClick(),
           child: TyreWidget(
             positionKey: key,
             details: details,
             isSelected: isTarget || selectedKeys.contains(key),
             isSource: false,
             onTap: () => onTyreTap(key, details), // Show details dialog
           ),
         );
      },
    );
  }
}

class ChassisPainter extends CustomPainter {
  final Map<String, dynamic> layout;
  final Color color;
  
  ChassisPainter({required this.layout, this.color = const Color(0xFFD0D0D0)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    // Center X
    final cx = size.width / 2;
    // Rail Offset from Center
    final offset = 60.0; 

    // Draw long longitudinal rails
    final railPath = Path();
    railPath.moveTo(cx - offset, 40);
    railPath.lineTo(cx - offset, size.height);
    
    railPath.moveTo(cx + offset, 40);
    railPath.lineTo(cx + offset, size.height);
    
    canvas.drawPath(railPath, paint);
    
    // Axles (Horizontal bars connecting wheels) are inferred by position, but let's draw cross-members
    // We can't easily know EXACT Y positions of children here without LayoutBuilder loop, 
    // but we can draw generic cross frames regularly.
    
    final crossPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
      
    double y = 120;
    while (y < size.height) {
       canvas.drawLine(Offset(cx - offset, y), Offset(cx + offset, y), crossPaint);
       y += 180; // Approximate axle spacing
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
