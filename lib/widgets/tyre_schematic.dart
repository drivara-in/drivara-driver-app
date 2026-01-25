import 'package:flutter/material.dart';

class TyreSchematic extends StatelessWidget {
  final Map<String, dynamic> layout; // e.g. {wheelsByAxle: [2, 4, 4], splitAfter: 1}
  final List<String> selectedKeys;
  final Function(String key) onTyreTap;

  const TyreSchematic({
    super.key,
    required this.layout,
    required this.selectedKeys,
    required this.onTyreTap,
  });

  @override
  Widget build(BuildContext context) {
    if (layout['wheelsByAxle'] == null) {
      return const Center(child: Text("No layout data"));
    }

    final List<dynamic> axles = layout['wheelsByAxle'];
    int splitAfter = layout['splitAfter'] ?? -1;

    // Use a ListView to scroll if the truck is long
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          // Front of truck indicator
          Container(
            width: 80,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Center(child: Icon(Icons.keyboard_arrow_up, size: 16, color: Colors.grey)),
          ),
          
          const SizedBox(height: 10),

          // Chassis lines (drawing a simple frame)
          Stack(
            alignment: Alignment.topCenter,
            children: [
              // We'll construct the axles in a Column and overlay the chassis rails if feasible,
              // or just draw the axles directly. 
              // A column of "AxleRows" works best.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < axles.length; i++) ...[
                    // Add gap if split
                    if (i > 0 && (i - 1) == splitAfter)
                         const SizedBox(height: 40), 

                    _buildAxleRow(context, i, axles[i] as int),
                    
                    if (i < axles.length - 1)
                       const SizedBox(height: 60), // Spacing between axles
                  ]
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAxleRow(BuildContext context, int axleIndex, int wheelCount) {
    // Generate keys for this axle. 
    // Logic: 
    // 2 wheels -> L, R (or A1-L, A1-R)
    // 4 wheels -> LO, LI, RI, RO
    
    List<String> keys = [];
    if (wheelCount == 2) {
      keys = ['L', 'R'];
    } else if (wheelCount == 4) {
      keys = ['LO', 'LI', 'RI', 'RO'];
    } else {
      // Fallback generic
      for(int k=0; k<wheelCount/2; k++) {
        keys.add('L${k+1}');
      }
      for(int k=0; k<wheelCount/2; k++) {
        keys.add('R${k+1}');
      }
    }

    final axleKeyPrefix = "A${axleIndex + 1}";

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LEFT SIDE
        Row(
          mainAxisSize: MainAxisSize.min,
          children: keys.where((k) => k.startsWith('L')).map((k) {
             return _buildTyre(context, "$axleKeyPrefix-$k");
          }).toList().reversed.toList(), // Outer to Inner
        ),
        
        // AXLE BEAM
        Container(
          width: 80,
          height: 8,
          color: Colors.grey[700],
        ),
        
        // RIGHT SIDE
        Row(
          mainAxisSize: MainAxisSize.min,
          children: keys.where((k) => k.startsWith('R')).map((k) {
             return _buildTyre(context, "$axleKeyPrefix-$k");
          }).toList(), // Inner to Outer
        ),
      ],
    );
  }

  Widget _buildTyre(BuildContext context, String key) {
    final isSelected = selectedKeys.contains(key);
    
    return GestureDetector(
      onTap: () => onTyreTap(key),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 32,
        height: 50,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.black87,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: [
             if (isSelected) BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)
          ]
        ),
        child: Center(
          child: Text(
            key.split('-')[1], 
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ),
    );
  }
}
