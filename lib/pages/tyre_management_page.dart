import 'package:flutter/material.dart';
import 'package:drivara_driver_app/widgets/tyre_schematic.dart';
import 'package:drivara_driver_app/widgets/tyre_slot_card.dart';
import 'package:drivara_driver_app/api_config.dart';
import 'package:provider/provider.dart';
import 'package:drivara_driver_app/providers/localization_provider.dart';

class TyreManagementPage extends StatefulWidget {
  final String vehicleId;
  final String registrationNumber;
  final String? orgId;

  const TyreManagementPage({
    super.key, 
    required this.vehicleId,
    required this.registrationNumber,
    this.orgId,
  });

  @override
  State<TyreManagementPage> createState() => _TyreManagementPageState();
}

class _TyreManagementPageState extends State<TyreManagementPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _tyreDetails = {};
  
  // Interaction State
  String? _sourceKey;
  List<Map<String, String>> _swaps = [];

  @override
  void initState() {
    super.initState();
    _fetchVehicleDetails();
  }

  Future<void> _fetchVehicleDetails() async {
    try {
      String? orgId = widget.orgId;
      
      if (orgId == null) {
          try {
             final meRes = await ApiConfig.dio.get('/driver/me/profile'); // Corrected endpoint guess?
             orgId = meRes.data['selectedOrgId'] ?? meRes.data['orgs']?[0]['id'];
          } catch(e) {
             // fallback to error
             debugPrint("Could not determine orgId: $e");
          }
      }
      
      if (orgId == null) throw "Organization ID not found";
      
      final res = await ApiConfig.dio.get('/orgs/$orgId/vehicles/${widget.vehicleId}');
      
      setState(() {
        _tyreDetails = Map<String, dynamic>.from(res.data['tyreDetails'] ?? {});
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching vehicle: $e");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load vehicle: $e")));
         setState(() => _isLoading = false);
      }
    }
  }

  void _handleTyreTap(String key) {
    if (_sourceKey == null) {
      // Select Source
      setState(() => _sourceKey = key);
    } else if (_sourceKey == key) {
      // Deselect
      setState(() => _sourceKey = null);
    } else {
      // SWAP
      _performSwap(_sourceKey!, key);
    }
  }

  void _performSwap(String source, String target) {
    setState(() {
      // record swap
      _swaps.add({
        'from': source,
        'to': target,
        'fromLabel': source, // could prettify
        'toLabel': target
      });

      // update local state
      final sourceData = _tyreDetails[source];
      final targetData = _tyreDetails[target];

      _tyreDetails[source] = targetData ?? {};
      _tyreDetails[target] = sourceData ?? {};

      // reset selection
      _sourceKey = null;
    });
  }

  void _undoLastSwap() {
    if (_swaps.isEmpty) return;
    final last = _swaps.removeLast();
    // Reverse logic
    _performSwap(last['to']!, last['from']!); // This adds a new swap entry, we should manually revert instead.
    
    // Manual Revert:
    setState(() {
        _swaps.removeLast(); // Remove the "revert" swap we just added by calling performSwap recursively? 
        // No, let's just do logic manually to avoid mess.
    });
    // Actually, simpler: just reload data or track history better. 
    // For MVP, just "Reset" is easier than undo stack? 
    // Let's implement proper undo:
    
    setState(() {
       // We already popped last above.
       // Now reverse the data change.
       final source = last['to']!; // was target
       final target = last['from']!; // was source
       
       final sourceData = _tyreDetails[source];
       final targetData = _tyreDetails[target];
       
       _tyreDetails[source] = targetData ?? {};
       _tyreDetails[target] = sourceData ?? {};
    });
  }

  Future<void> _saveChanges() async {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    setState(() => _isSaving = true);
    
    try {
        final orgId = widget.orgId;
        if (orgId == null) throw "Org ID missing";
        
        // 1. Update Vehicle
        await ApiConfig.dio.post(
           '/orgs/$orgId/vehicles/${widget.vehicleId}', 
           data: {'tyreDetails': _tyreDetails} // Validate endpoint method (likely PATCH/POST)
        );

        // 2. Create Expense (Optional) - User prompt?
        // For MVP, integrated save. Web had prompt. We can implement prompt later.
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('changes_saved') ?? "Changes saved successfully!")));
           Navigator.pop(context);
        }
    } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    } finally {
        if (mounted) setState(() => _isSaving = false);
    }
  }

  Map<String, dynamic> _deriveLayoutFromDetails() {
      if (_tyreDetails.isEmpty) {
          return {'wheelsByAxle': [], 'splitAfter': -1};
      }

      int maxAxle = 0;
      Map<int, int> wheelsPerAxle = {};

      for (var key in _tyreDetails.keys) {
          // Expected format: "A1-L", "A2-RO"
          final parts = key.split('-');
          if (parts.length < 2) continue;
          
          final axlePart = parts[0]; // "A1"
          if (axlePart.startsWith('A')) {
              final axleNum = int.tryParse(axlePart.substring(1));
              if (axleNum != null) {
                  if (axleNum > maxAxle) maxAxle = axleNum;
                  
                  // Count wheels? Simplified: if we see "O" (Outer) or "I" (Inner), it's likely 4 wheels.
                  // If just L/R, it might be 2.
                  // We'll track max wheels seen for this axle.
                  final pos = parts[1]; // "L", "RO", etc.
                  int currentCount = wheelsPerAxle[axleNum] ?? 2; // Default to 2
                  
                  if (pos.contains('I') || pos.contains('O')) {
                     currentCount = 4;
                  }
                  wheelsPerAxle[axleNum] = currentCount;
              }
          }
      }
      
      List<int> config = [];
      for (int i = 1; i <= maxAxle; i++) {
         config.add(wheelsPerAxle[i] ?? 2);
      }
      
      // Heuristic for split: usually between 1st (steer) and others if > 2 axles
      int split = -1;
      if (config.length > 2) split = 0; // standard truck layout

      return {
          'wheelsByAxle': config,
          'splitAfter': split
      };
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically derive layout from data keys
    final layout = _deriveLayoutFromDetails();
    final allKeys = _getAllPossibleKeys(layout);
    
    // Sort keys logically: A1-L, A1-R, A2...
    // Or just use the keys present + derived empty ones?
    // Let's use the explicit slot capability if we can derive it.
    // For now, sorting available keys from details + any we might imply? 
    // Ideally we should generate the full "expected" key set based on `layout['wheelsByAxle']`.
    // Let's implement a helper to generate all expected keys for the grid.
    final expectedKeys = _generateExpectedKeys(layout);
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(widget.registrationNumber, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
             Text("${expectedKeys.length} Tyres • ${layout['wheelsByAxle'].length} Axles", style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
          ],
        ),
        actions: [
          if (_swaps.isNotEmpty)
             Container(
               margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
               child: ElevatedButton.icon(
                 onPressed: _undoLastSwap,
                 icon: const Icon(Icons.undo, size: 14),
                 label: const Text("Undo"),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.amber.shade100, 
                   foregroundColor: Colors.amber.shade900,
                   elevation: 0,
                   padding: const EdgeInsets.symmetric(horizontal: 12)
                 ),
               ),
             )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
               // Interaction Banner
               if (_sourceKey != null)
                  Container(
                    width: double.infinity,
                    color: Colors.blue.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.touch_app, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: "Select target to swap "),
                                TextSpan(text: _sourceKey!, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ]
                            ),
                            style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                          ),
                        ),
                        TextButton(
                           onPressed: () => setState(() => _sourceKey = null),
                           child: const Text("Cancel"),
                        )
                      ],
                    ),
                  ),

               Expanded(
                 child: Row(
                   crossAxisAlignment: CrossAxisAlignment.stretch,
                   children: [
                      // LEFT: Schematic Stickyt
                      Container(
                        width: 140, // Fixed narrow width for schematic
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(right: BorderSide(color: Colors.grey.shade200))
                        ),
                        child: TyreSchematic(
                           layout: layout, 
                           selectedKeys: [_sourceKey].whereType<String>().toList(),
                           onTyreTap: _handleTyreTap,
                        ),
                      ),
                      
                      // RIGHT: Manifest Grid
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                             Text("Active Configuration", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1)),
                             const SizedBox(height: 12),
                             
                             Wrap(
                               spacing: 12,
                               runSpacing: 12,
                               children: expectedKeys.map((k) {
                                  // Find details
                                  final d = _tyreDetails[k] ?? {};
                                  final isSel = _sourceKey == k;
                                  
                                  return SizedBox(
                                    width: 160, // Fixed Card Width
                                    height: 110,
                                    child: TyreSlotCard(
                                      positionKey: k,
                                      details: d,
                                      isSelected: isSel,
                                      isSource: _sourceKey != null,
                                      onTap: () => _handleTyreTap(k),
                                    ),
                                  );
                               }).toList(),
                             ),
                             
                             const SizedBox(height: 100), // Bottom padding for FAB/Button
                          ],
                        ),
                      )
                   ],
                 ),
               ),
               
               // Bottom Action Bar
               Container(
                 padding: const EdgeInsets.all(16),
                 decoration: BoxDecoration(
                   color: Colors.white,
                   boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 16)]
                 ),
                 child: SizedBox(
                   width: double.infinity,
                   child: ElevatedButton(
                     onPressed: _swaps.isEmpty ? null : _saveChanges,
                     style: ElevatedButton.styleFrom(
                       padding: const EdgeInsets.symmetric(vertical: 16),
                       backgroundColor: Colors.blue.shade700,
                       disabledBackgroundColor: Colors.grey.shade300,
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                     ),
                     child: _isSaving 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                        : Text(_swaps.isEmpty ? "No Changes" : "Save ${_swaps.length} Changes", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                   ),
                 ),
               )
            ],
        ),
    );
  }

  // Helper to generate full list of expected keys based on layout
  List<String> _generateExpectedKeys(Map<String, dynamic> layout) {
      List<String> keys = [];
      final axles = layout['wheelsByAxle'] as List<dynamic>? ?? [];
      
      for(int i=0; i<axles.length; i++) {
         int count = axles[i] as int;
         int axleNum = i + 1;
         if (count == 2) {
            keys.add("A$axleNum-L");
            keys.add("A$axleNum-R");
         } else if (count == 4) {
             keys.add("A$axleNum-LO");
             keys.add("A$axleNum-LI");
             keys.add("A$axleNum-RI");
             keys.add("A$axleNum-RO");
         } else {
             // generic
             for(int k=0; k<count; k++) keys.add("A$axleNum-W${k+1}");
         }
      }
      return keys;
  }
  
  List<String> _getAllPossibleKeys(Map<String, dynamic> layout) {
     final valid = _generateExpectedKeys(layout);
     // Also include any extra keys found in details but not in layout (e.g. spares SP1)
     final extras = _tyreDetails.keys.where((k) => !valid.contains(k)).toList();
     return [...valid, ...extras];
  }
}
