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
      child: Center(
        child: SizedBox(
          width: 200, // Fixed width for chassis
          child: Column(
            children: [
              // Front Indicator
              _buildFrontIndicator(),
              
              const SizedBox(height: 10),

              Stack(
                alignment: Alignment.topCenter,
                children: [
                  // 1. Chassis Rails Background
                  Positioned.fill(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 6, color: Colors.grey[300]), // Left Rail
                        const SizedBox(width: 80), // Rail Spacing
                        Container(width: 6, color: Colors.grey[300]), // Right Rail
                      ],
                    ),
                  ),

                  // 2. Axles
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < axles.length; i++) ...[
                        // Add gap if split (Trailer separation)
                        if (i > 0 && (i - 1) == splitAfter)
                             _buildCouplingLink(), 

                        _buildAxleRow(context, i, axles[i] as int),
                        
                        if (i < axles.length - 1 && !((i) == splitAfter))
                           const SizedBox(height: 40), // Standard Spacing
                      ]
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFrontIndicator() {
    return Column(
      children: [
        Icon(Icons.keyboard_arrow_up, size: 24, color: Colors.grey[400]),
        Text("FRONT", style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _buildCouplingLink() {
    return Container(
      height: 60,
      width: double.infinity,
      alignment: Alignment.center,
      child: Container(
         width: 4, height: 60, color: Colors.grey[400]
      ),
    );
  }

  Widget _buildAxleRow(BuildContext context, int axleIndex, int wheelCount) {
    List<String> keys = [];
    if (wheelCount == 2) {
      keys = ['L', 'R'];
    } else if (wheelCount == 4) {
      keys = ['LO', 'LI', 'RI', 'RO'];
    } else {
      // Fallback
      for(int k=0; k<wheelCount/2; k++) keys.add('L${k+1}');
      for(int k=0; k<wheelCount/2; k++) keys.add('R${k+1}');
    }

    final axleKeyPrefix = "A${axleIndex + 1}";

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // LEFT SIDE
        Row(
          mainAxisSize: MainAxisSize.min,
          children: keys.where((k) => k.startsWith('L')).map((k) {
             return _buildTyrePill(context, "$axleKeyPrefix-$k");
          }).toList().reversed.toList(), // Outer to Inner
        ),
        
        // AXLE BEAM
        Container(
          width: 86,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.grey[700],
            borderRadius: BorderRadius.circular(3)
          ),
        ),
        
        // RIGHT SIDE
        Row(
          mainAxisSize: MainAxisSize.min,
          children: keys.where((k) => k.startsWith('R')).map((k) {
             return _buildTyrePill(context, "$axleKeyPrefix-$k");
          }).toList(), // Inner to Outer
        ),
      ],
    );
  }

  Widget _buildTyrePill(BuildContext context, String key) {
    final isSelected = selectedKeys.contains(key);
    
    // Web style: 
    // - Black/Grey usually
    // - Blue when selected
    
    return GestureDetector(
      onTap: () => onTyreTap(key),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 24,
        height: 44,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade600 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent, 
            width: 1.5
          ),
          boxShadow: [
             if (isSelected) BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 6, spreadRadius: 1)
          ]
        ),
        child: Center(
          child: Text(
            key.split('-')[1], 
            style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
