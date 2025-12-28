import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';

class AddExpenseSheet extends StatefulWidget {
  final Map<String, dynamic> job;
  final VoidCallback? onSuccess;

  const AddExpenseSheet({Key? key, required this.job, this.onSuccess}) : super(key: key);

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
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _locationController = TextEditingController(); // Optional manual entry
  DateTime _selectedDateTime = DateTime.now(); // Initialize with current date/time

  @override
  void initState() {
    super.initState();
    _fetchExpenseTypes();
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

  Future<void> _submit() async {
     final t = Provider.of<LocalizationProvider>(context, listen: false);
     if (_selectedType == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('select_type_error'))));
        return;
     }
     if (_amountController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('enter_amount_error'))));
        return;
     }

     setState(() => _isLoading = true);
     try {
        final payload = {
           'type': _selectedType,
           'amount': double.tryParse(_amountController.text) ?? 0,
           'timestamp': _selectedDateTime.toIso8601String(),
           'description': _descController.text,
           'location': _locationController.text.isNotEmpty ? _locationController.text : "Manual Entry", 
           // file_upload_id not implemented yet in UI
        };

        final response = await ApiConfig.dio.post('/driver/jobs/${widget.job['id']}/expenses', data: payload);
        
        if (mounted) {
           Navigator.pop(context);
           widget.onSuccess?.call();
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('expense_added_success'))));
        }
     } catch (e) {
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
                       final englishName = type['name'];
                       final localizedName = t.t('etype_$englishName'); 
                       return DropdownMenuItem<String>(
                          value: englishName, 
                          child: Text(localizedName != 'etype_$englishName' ? localizedName : englishName),
                       );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedType = val),
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

                 // Date and Time Pickers
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
                              setState(() {
                                _selectedDateTime = DateTime(
                                  _selectedDateTime.year,
                                  _selectedDateTime.month,
                                  _selectedDateTime.day,
                                  time.hour, time.minute
                                );
                              });
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

