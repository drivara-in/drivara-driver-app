import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _registrationNumber = "";
  
  // Interaction State
  String? _sourceKey;
  List<Map<String, String>> _swaps = [];

  @override
  void initState() {
    super.initState();
    _registrationNumber = widget.registrationNumber;
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
      
      if (orgId == null) throw Provider.of<LocalizationProvider>(context, listen: false).t('org_id_error') ?? "Organization ID not found";
      
      final res = await ApiConfig.dio.get('/orgs/$orgId/vehicles/${widget.vehicleId}');
      
      setState(() {
        _tyreDetails = Map<String, dynamic>.from(res.data['tyreDetails'] ?? {});
        // Update registration number if available and current is Unknown or empty
        if (_registrationNumber == "Unknown" || _registrationNumber.isEmpty) {
            if (res.data['registrationNumber'] != null) _registrationNumber = res.data['registrationNumber'];
            else if (res.data['registration_number'] != null) _registrationNumber = res.data['registration_number'];
            else if (res.data['vehicle_number'] != null) _registrationNumber = res.data['vehicle_number'];
            else if (res.data['reg_no'] != null) _registrationNumber = res.data['reg_no'];
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching vehicle: $e");
      if (mounted) {
         final t = Provider.of<LocalizationProvider>(context, listen: false);
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${t.t('failed_load_vehicle')}$e")));
         setState(() => _isLoading = false);
      }
    }
  }

  void _handleTyreSwap(String source, String target) {
    if (source == target) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _performSwap(source, target);
      // Removed interaction banner logic, simple direct manipulation
    });
  }

  void _performSwap(String source, String target) {
    // record swap
    _swaps.add({
      'from': source,
      'to': target,
      'fromLabel': source, 
      'toLabel': target
    });

    // update local state
    final sourceData = _tyreDetails[source];
    final targetData = _tyreDetails[target];

    _tyreDetails[source] = targetData ?? {};
    _tyreDetails[target] = sourceData ?? {};
  }

  void _undoAll() {
    setState(() {
       // Reload to reset
       _swaps.clear();
       _isLoading = true;
    });
    _fetchVehicleDetails(); // Simplest reset
  }

  Future<void> _saveChanges() async {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    setState(() => _isSaving = true);
    
    try {
        final orgId = widget.orgId; // Assuming passed or we throw
        if (orgId == null) throw Provider.of<LocalizationProvider>(context, listen: false).t('org_id_error') ?? "Org ID missing";
        
        await ApiConfig.dio.post(
           '/orgs/$orgId/vehicles/${widget.vehicleId}', 
           data: {'tyreDetails': _tyreDetails}
        );

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('changes_saved') ?? "Changes saved successfully!")));
           Navigator.pop(context);
        }
    } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${t.t('error_saving')}$e")));
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
          final parts = key.split('-');
          if (parts.length < 2) continue;
          
          final axlePart = parts[0]; 
          if (axlePart.startsWith('A')) {
              final axleNum = int.tryParse(axlePart.substring(1));
              if (axleNum != null) {
                  if (axleNum > maxAxle) maxAxle = axleNum;
                  final pos = parts[1]; 
                  int currentCount = wheelsPerAxle[axleNum] ?? 2; 
                  
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
      
      int split = -1;
      if (config.length > 2) split = 0; 

      return {
          'wheelsByAxle': config,
          'splitAfter': split
      };
  }

  void _handleTyreTap(String key, Map<String, dynamic> details) {
    if (details.isEmpty) return; // Or show specific "Empty" dialog
    
    final loc = Provider.of<LocalizationProvider>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
               children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.2) : Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close, color: theme.iconTheme.color), onPressed: () => Navigator.pop(ctx))
               ],
             ),
             const SizedBox(height: 20),
             _buildDetailRow(loc.t('brand'), details['brand']),
             _buildDetailRow(loc.t('model'), details['model']),
             _buildDetailRow(loc.t('serial'), details['serial']),
             const Divider(height: 30),
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(loc.t('odometer_installed'), style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                   Text("${details['mount_odometer'] ?? '-'} km", style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color))
                ],
             ),
             const SizedBox(height: 10),
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(loc.t('total_run'), style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                   Text("${details['kms'] ?? '-'} km", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green))
                ],
             ),
             const SizedBox(height: 30),
             
             // Actions
             SizedBox(
               width: double.infinity,
               child: ElevatedButton.icon(
                 onPressed: () {
                   Navigator.pop(ctx);
                   _showSwapTargetSelector(key);
                 }, 
                 icon: const Icon(Icons.swap_horiz, color: Colors.white),
                 label: Text(loc.t('move_swap'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                 style: ElevatedButton.styleFrom(
                   padding: const EdgeInsets.symmetric(vertical: 16),
                   backgroundColor: theme.primaryColor,
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                 ),
               ),
             )
          ],
        ),
      ),
    );
  }
  
  void _showSwapTargetSelector(String sourceKey) {
     final loc = Provider.of<LocalizationProvider>(context, listen: false);
     final theme = Theme.of(context);
     
     final availableTargets = _getAllPossibleKeys(_deriveLayoutFromDetails())
         .where((k) => k != sourceKey)
         .toList();
         
     showModalBottomSheet(
       context: context,
       isScrollControlled: true,
       backgroundColor: theme.cardColor,
       shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
       builder: (ctx) => DraggableScrollableSheet(
         initialChildSize: 0.6,
         minChildSize: 0.4,
         maxChildSize: 0.9,
         expand: false,
         builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                   Text(loc.t('swap_tyre_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textTheme.titleLarge?.color)),
                   const SizedBox(height: 10),
                   Text("${loc.t('select_target_tyre')} $sourceKey", style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                   const SizedBox(height: 20),
                   Expanded(
                     child: ListView.builder(
                       controller: scrollController,
                       itemCount: availableTargets.length,
                       itemBuilder: (ctx, i) {
                          final target = availableTargets[i];
                          final details = _tyreDetails[target] ?? {};
                          final hasTyre = details.isNotEmpty;
                          
                          return ListTile(
                            leading: Icon(hasTyre ? Icons.circle : Icons.radio_button_unchecked, color: hasTyre ? theme.iconTheme.color : Colors.grey),
                            title: Text(target, style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color)),
                            subtitle: Text(hasTyre ? "${details['brand']} ${details['serial']}" : loc.t('empty_slot'), style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7))),
                            onTap: () {
                               Navigator.pop(ctx);
                               _handleTyreSwap(sourceKey, target);
                            },
                          );
                       },
                     ),
                   )
                ],
              ),
            );
         },
       ),
     );
  }

  Widget _buildDetailRow(String label, String? value) {
     final theme = Theme.of(context);
     return Padding(
       padding: const EdgeInsets.only(bottom: 12),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.spaceBetween,
         children: [
            Text(label, style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6), fontSize: 13)),
            Text(value ?? "-", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.textTheme.bodyLarge?.color))
         ],
       ),
     );
  }

  @override
  Widget build(BuildContext context) {
    final layout = _deriveLayoutFromDetails();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final loc = Provider.of<LocalizationProvider>(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.cardColor,
        centerTitle: true,
        title: Text(_registrationNumber, style: TextStyle(color: theme.textTheme.titleLarge?.color, fontWeight: FontWeight.bold)),
        iconTheme: theme.iconTheme,
        actions: [
          // Reset Button (Undo Icon)
          if (_swaps.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.orange, size: 28),
              onPressed: _undoAll,
              tooltip: loc.t('reset_all'),
            )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
               Expanded(
                 child: Container(
                   color: theme.scaffoldBackgroundColor, // Seamless background
                   child: TyreSchematic(
                      layout: layout, 
                      selectedKeys: const [], 
                      onTyreSwap: _handleTyreSwap,
                      onTyreTap: _handleTyreTap,
                      tyreDetailsLookup: _tyreDetails,
                   ),
                 ),
               ),
               
               // Bottom Action Bar
               Container(
                 padding: const EdgeInsets.all(16),
                 decoration: BoxDecoration(
                   color: theme.cardColor,
                   boxShadow: [BoxShadow(color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 16)]
                 ),
                 child: SafeArea(
                   top: false,
                   child: SizedBox(
                     width: double.infinity,
                     child: ElevatedButton(
                       onPressed: _swaps.isEmpty ? null : _saveChanges,
                       style: ElevatedButton.styleFrom(
                         padding: const EdgeInsets.symmetric(vertical: 16),
                         backgroundColor: theme.primaryColor,
                         disabledBackgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                       ),
                       child: _isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                          : Text(
                              _swaps.isEmpty 
                                ? loc.t('no_changes') 
                                : loc.t('save_changes').replaceAll('{count}', _swaps.length.toString()),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
                            ),
                     ),
                   ),
                 ),
               )
            ],
        ),
    );
  }

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
             for(int k=0; k<count; k++) keys.add("A$axleNum-W${k+1}");
         }
      }
      return keys;
  }
  
  List<String> _getAllPossibleKeys(Map<String, dynamic> layout) {
     final valid = _generateExpectedKeys(layout);
     final extras = _tyreDetails.keys.where((k) => !valid.contains(k)).toList();
     return [...valid, ...extras];
  }
}
