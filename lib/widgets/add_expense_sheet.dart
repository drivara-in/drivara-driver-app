import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AddExpenseSheet extends StatefulWidget {
  final Map<String, dynamic> job;
  final VoidCallback? onSuccess;
  final LatLng? currentLocation;

  const AddExpenseSheet({Key? key, required this.job, this.onSuccess, this.currentLocation}) : super(key: key);

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  bool _isLoading = false;
  bool _isTypesLoading = true;
  List<dynamic> _expenseTypes = [];
  
  // Form State
  String? _selectedType;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  DateTime _selectedDateTime = DateTime.now();
  
  // Location Coordinates State
  double? _lat;
  double? _lng;

  // File Upload State
  File? _selectedBillImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchExpenseTypes();
    if (widget.currentLocation != null) {
       _geocodePosition(widget.currentLocation!.latitude, widget.currentLocation!.longitude);
    }
  }

  Future<void> _fetchLocationForTime() async {
     try {
        if (mounted) setState(() => _locationController.text = "Fetching location...");
        
        final response = await ApiConfig.dio.get(
           '/driver/jobs/${widget.job['id']}/telemetry',
           queryParameters: {
              'timestamp': _selectedDateTime.toIso8601String()
           }
        );

        if (response.statusCode == 200 && response.data != null) {
           final lat = response.data['lat'];
           final lng = response.data['lng'];
           if (lat is num && lng is num) {
              await _geocodePosition(lat.toDouble(), lng.toDouble());
           }
        }
     } catch (e) {
        debugPrint("Telemetry fetch failed: $e");
        if (mounted) _locationController.text = ""; 
     }
  }

  Future<void> _geocodePosition(double lat, double lng) async {
     try {
        setState(() {
          _lat = lat;
          _lng = lng;
        });
        
        final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
        if (apiKey == null) return;

        final Response response = await Dio().get(
           'https://maps.googleapis.com/maps/api/geocode/json',
           queryParameters: {
              'latlng': '$lat,$lng',
              'key': apiKey
           }
        );

        if (response.data['status'] == 'OK' && response.data['results'] is List && response.data['results'].isNotEmpty) {
           if (mounted) {
              setState(() {
                 _locationController.text = response.data['results'][0]['formatted_address'];
              });
           }
        }
     } catch (e) {
        debugPrint("Geocoding failed: $e");
        if (mounted) _locationController.text = "";
     }
  }

  Future<void> _fetchExpenseTypes() async {
    try {
      final response = await ApiConfig.dio.get('/driver/expenses/types');
      if (mounted) {
        setState(() {
          _expenseTypes = response.data;
          _isTypesLoading = false;
          // Pre-select if only one
          if (_expenseTypes.length == 1) {
             _selectedType = _expenseTypes[0]['name'];
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching expense types: $e");
      if (mounted) setState(() => _isTypesLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _selectedBillImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _removeImage() {
    setState(() {
      _selectedBillImage = null;
    });
  }

  Future<void> _submit() async {
     final t = Provider.of<LocalizationProvider>(context, listen: false);
     if (_selectedType == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('select_type_error'))));
        return;
     }

     // Check mandatory bill
     final selectedTypeObj = _expenseTypes.firstWhere((e) => e['name'] == _selectedType, orElse: () => null);
     final bool isMandatory = selectedTypeObj != null && (selectedTypeObj['is_bill_mandatory'] == true || selectedTypeObj['mandate'] == true);
     
     if (isMandatory && _selectedBillImage == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('bill_required_error'))));
        return;
     }

      if (_amountController.text.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('enter_amount_error'))));
         return;
      }

      // Quantity is mandatory for Fuel/DEF expenses
      final isFuelOrDef = _selectedType != null && (_selectedType!.toLowerCase().contains('fuel') || _selectedType!.toLowerCase().contains('def'));
      if (isFuelOrDef && _qtyController.text.isEmpty) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('enter_quantity_error') ?? 'Please enter quantity in litres')));
         return;
      }

     setState(() => _isLoading = true);
     try {
        debugPrint("Submitting expense for Job: ${widget.job['id']}. Job Keys: ${widget.job.keys.toList()}");
        
        String? fileId;
        if (_selectedBillImage != null) {
           final uuid = DateTime.now().millisecondsSinceEpoch.toString(); // Simple unique ID
           final ext = _selectedBillImage!.path.split('.').last;
           final orgId = widget.job['org_id'] ?? widget.job['orgId']; // Try both casing
           debugPrint("Detected OrgID: $orgId");

           if (orgId != null) {
              final customKey = 'orgs/$orgId/jobs/expenses/$uuid.$ext';
              debugPrint("Uploading file to custom key: $customKey");
              fileId = await ApiConfig.uploadFile(_selectedBillImage!.path, customKey: customKey);
           } else {
              debugPrint("Uploading file without custom key");
              fileId = await ApiConfig.uploadFile(_selectedBillImage!.path);
           }
           debugPrint("File Upload Success. ID: $fileId");
        }

        final payload = {
           'type': _selectedType,
           'amount': double.tryParse(_amountController.text) ?? 0,
           'timestamp': _selectedDateTime.toIso8601String(),
           'timezone': DateTime.now().timeZoneName,
           'description': _descController.text,
           'location': _locationController.text.isNotEmpty ? _locationController.text : "Manual Entry",
           'file_upload_id': fileId,
           'latitude': _lat,
           'longitude': _lng,
           if (_qtyController.text.isNotEmpty) 'qty': double.tryParse(_qtyController.text),
        };

        debugPrint("Posting expense payload: $payload");
        final response = await ApiConfig.dio.post('/driver/jobs/${widget.job['id']}/expenses', data: payload);
        debugPrint("Expense Post Response: ${response.statusCode} - ${response.data}");
        
        if (mounted) {
           Navigator.pop(context);
           widget.onSuccess?.call();
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('expense_added_success'))));
        }
     } catch (e) {
        debugPrint("Expense Submission Error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${t.t('expense_add_failed')}$e")));
        }
     } finally {
        if (mounted) setState(() => _isLoading = false);
     }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    
    return Container(
      padding: EdgeInsets.only(
          left: 24, 
          right: 24, 
          top: 24, 
          bottom: MediaQuery.of(context).viewInsets.bottom + 24
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(t.t('add_expense'), style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color)),
             const SizedBox(height: 20),
             
              if (_isTypesLoading) 
                 const Center(child: CircularProgressIndicator())
              else if (_expenseTypes.isEmpty)
                 Padding(
                   padding: const EdgeInsets.all(16.0),
                   child: Text(t.t('unknown'), style: TextStyle(color: Theme.of(context).disabledColor)), // Fallback for no types
                 )
              else ...[
                 // Type Dropdown
                 DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: InputDecoration(
                       labelText: t.t('expense_type'),
                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                       filled: true,
                       fillColor: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    items: _expenseTypes.map((type) {
                      final englishName = type['name'].toString().trim();
                      final localizedName = t.translateDynamic(englishName);
                      
                      return DropdownMenuItem<String>(
                         value: englishName, 
                         child: Text(localizedName),
                      );
                  }).toList(),
                    onChanged: (val) { setState(() { _selectedType = val; _qtyController.clear(); }); },
                 ),
                 const SizedBox(height: 16),

                 // Amount
                 TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                       labelText: t.t('amount_inr'),
                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                       filled: true,
                       fillColor: Theme.of(context).scaffoldBackgroundColor,
                    ),
                 ),
                 const SizedBox(height: 16),

                 // Quantity (Litres) — shown only for Fuel/DEF expense types
                 if (_selectedType != null && (_selectedType!.toLowerCase().contains('fuel') || _selectedType!.toLowerCase().contains('def')))
                   ...[
                     TextField(
                       controller: _qtyController,
                       keyboardType: const TextInputType.numberWithOptions(decimal: true),
                       decoration: InputDecoration(
                         labelText: t.t('quantity_litres') ?? 'Quantity (Litres)',
                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                         filled: true,
                         fillColor: Theme.of(context).scaffoldBackgroundColor,
                         suffixText: 'L',
                       ),
                     ),
                     const SizedBox(height: 16),
                   ],

                     Row(
                   children: [
                     // Date Picker
                     Expanded(
                       flex: 3,
                       child: InkWell(
                         onTap: () async {
                            final d = await showDatePicker(
                               context: context, 
                               firstDate: DateTime.now().subtract(const Duration(days: 30)),
                               lastDate: DateTime.now(),
                               initialDate: _selectedDateTime,
                               locale: t.locale, 
                            );
                            if (d != null) {
                               setState(() {
                                 _selectedDateTime = DateTime(
                                   d.year, d.month, d.day,
                                   _selectedDateTime.hour, _selectedDateTime.minute
                                 );
                               });
                               _fetchLocationForTime();
                            }
                         },
                         child: InputDecorator(
                            decoration: InputDecoration(
                               labelText: t.t('date'),
                               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                               filled: true,
                               fillColor: Theme.of(context).scaffoldBackgroundColor,
                               suffixIcon: const Icon(Icons.calendar_today, size: 18)
                            ),
                            child: Text(
                               DateFormat('dd MMM yyyy', t.locale.toString()).format(_selectedDateTime),
                               style: const TextStyle(fontSize: 14),
                            ),
                         ),
                       ),
                     ),
                     const SizedBox(width: 12),
                     // Time Picker
                     Expanded(
                       flex: 2,
                       child: InkWell(
                         onTap: () async {
                            final time = await showTimePicker(
                               context: context,
                               initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
                               builder: (context, child) {
                                 return Localizations.override(
                                   context: context,
                                   locale: t.locale,
                                   child: child,
                                 );
                               }
                            );
                            if (time != null) {
                               var newDateTime = DateTime(
                                   _selectedDateTime.year,
                                   _selectedDateTime.month,
                                   _selectedDateTime.day,
                                   time.hour, time.minute
                               );
                               
                               if (newDateTime.isAfter(DateTime.now())) {
                                  newDateTime = newDateTime.subtract(const Duration(days: 1));
                                  if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('date_adjusted_msg'))));
                                  }
                               }

                               setState(() {
                                 _selectedDateTime = newDateTime;
                               });
                               _fetchLocationForTime();
                            }
                         },
                         child: InputDecorator(
                            decoration: InputDecoration(
                               labelText: t.t('time'),
                               border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                               filled: true,
                               fillColor: Theme.of(context).scaffoldBackgroundColor,
                               suffixIcon: const Icon(Icons.access_time, size: 18)
                            ),
                            child: Text(
                               DateFormat('hh:mm a', t.locale.toString()).format(_selectedDateTime),
                               style: const TextStyle(fontSize: 14),
                            ),
                         ),
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 16),
                 
                  // Description (Optional)
                  TextField(
                     controller: _descController,
                     decoration: InputDecoration(
                        labelText: t.t('note_optional'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Theme.of(context).scaffoldBackgroundColor,
                     ),
                  ),
                  const SizedBox(height: 16),

                  // Bill Upload Section
                  Builder(
                    builder: (context) {
                      final selectedTypeObj = _expenseTypes.firstWhere((e) => e['name'] == _selectedType, orElse: () => null);
                      final bool isMandatory = selectedTypeObj != null && (selectedTypeObj['is_bill_mandatory'] == true || selectedTypeObj['mandate'] == true);
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isMandatory ? t.t('bill_image_req') : t.t('bill_image_opt'), 
                                style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)
                              ),
                              if (isMandatory)
                                const Text(" *", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              if (_selectedBillImage != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Container(
                                    width: 20, height: 20,
                                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                                  ),
                                )
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_selectedBillImage != null)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(_selectedBillImage!, height: 150, width: double.infinity, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 8, right: 8,
                                  child: InkWell(
                                    onTap: _removeImage,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                                    ),
                                  ),
                                )
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickImage(ImageSource.camera),
                                    icon: const Icon(Icons.camera_alt),
                                    label: Text(t.t('camera')),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickImage(ImageSource.gallery),
                                    icon: const Icon(Icons.photo_library),
                                    label: Text(t.t('gallery')),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      );
                    }
                  ),
              ],

              const SizedBox(height: 24),
              
              SizedBox(
                 width: double.infinity,
                 height: 50,
                 child: ElevatedButton(
                    onPressed: _isLoading || _expenseTypes.isEmpty ? null : _submit,
                    style: ElevatedButton.styleFrom(
                       backgroundColor: AppColors.primary,
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    child: _isLoading 
                       ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                       : Text(t.t('submit_expense'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                 ),
              )
          ],
        ),
      ),
    );
  }
}
