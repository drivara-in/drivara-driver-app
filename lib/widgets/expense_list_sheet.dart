import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ExpenseListSheet extends StatefulWidget {
  final Map<String, dynamic> job;

  const ExpenseListSheet({Key? key, required this.job}) : super(key: key);

  @override
  State<ExpenseListSheet> createState() => _ExpenseListSheetState();
}

class _ExpenseListSheetState extends State<ExpenseListSheet> {
  bool _isLoading = true;
  List<dynamic> _expenses = [];
  String? _currentDriverId;

  @override
  void initState() {
    super.initState();
    _fetchDriverId();
    _fetchExpenses();
  }

  Future<void> _fetchDriverId() async {
    final driverId = await ApiConfig.getDriverId();
    if (mounted) {
      setState(() {
        _currentDriverId = driverId;
      });
    }
  }

  Future<void> _fetchExpenses() async {
    try {
      final response = await ApiConfig.dio.get('/driver/jobs/${widget.job['id']}/expenses');
      if (mounted) {
        setState(() {
          _expenses = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching expenses: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  t.t('submitted_expenses'),
                  style: AppTextStyles.header.copyWith(
                    fontSize: 20,
                    color: Theme.of(context).textTheme.bodyLarge?.color
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_expenses.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 64,
                      color: Theme.of(context).disabledColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.t('no_expenses'),
                      style: TextStyle(
                        color: Theme.of(context).disabledColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchExpenses,
                child: ListView.separated(
                  itemCount: _expenses.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final expense = _expenses[index];
                    return _buildExpenseCard(expense, t);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense, LocalizationProvider t) {
    final rawAmount = expense['amount'];
    final double amount = (rawAmount is num) 
        ? rawAmount.toDouble() 
        : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
    String type = expense['type'] ?? 'Unknown';
    String displayType;
    
    if (type == 'Unknown') {
       displayType = t.t('unknown');
    } else {
       displayType = t.translateDynamic(type.toString().trim());
    }
    
    DateTime timestamp;
    final rawTimestamp = expense['timestamp'];
    if (rawTimestamp is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(rawTimestamp).toLocal();
    } else if (rawTimestamp is String) {
      timestamp = DateTime.tryParse(rawTimestamp)?.toLocal() ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }
    final description = expense['description'];
    final location = expense['location'];

    // Quantity & rate per litre for fuel/DEF
    final rawQty = expense['qty'];
    final double? qty = rawQty is num ? rawQty.toDouble() : double.tryParse(rawQty?.toString() ?? '');
    final double? ratePerL = (qty != null && qty > 0) ? amount / qty : null;

    final createdBy = expense['created_by_name'] ?? 'Driver';
    final createdById = expense['created_by'];
    final driverId = expense['driver_id'];
    
    // Allow delete if created by this user ID OR matched by driver ID
    final canDelete = _currentDriverId != null && (
        (createdById != null && createdById == _currentDriverId) || 
        (driverId != null && driverId == _currentDriverId)
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayType,
                      style: AppTextStyles.header.copyWith(
                        fontSize: 16,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a', t.locale.toString()).format(timestamp),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: AppTextStyles.header.copyWith(
                    fontSize: 16,
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (canDelete) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _confirmDelete(expense['id']),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
          
          if (qty != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.local_gas_station, size: 16, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                const SizedBox(width: 8),
                Text(
                  '${qty.toStringAsFixed(1)} L',
                  style: AppTextStyles.body.copyWith(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                ),
                if (ratePerL != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '@ ₹${ratePerL.toStringAsFixed(2)}/L',
                    style: AppTextStyles.label.copyWith(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6)),
                  ),
                ],
              ],
            ),
          ],

          if (description != null && description.toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.note_outlined,
                  size: 16,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    description.toString(),
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (expense['attachment_url'] != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  String urlString = expense['attachment_url']?.toString() ?? '';
                  final uploadId = expense['file_upload_id']?.toString();
                  
                  // If we have an upload ID, try to get a fresh signed URL first
                  if (uploadId != null && uploadId.isNotEmpty) {
                      try {
                        final res = await ApiConfig.dio.get('/uploads/$uploadId/url');
                        if (res.statusCode == 200 && res.data != null) {
                           final signed = res.data['url'] ?? res.data['publicUrl'] ?? res.data['srcUrl'];
                           if (signed != null && signed.toString().isNotEmpty) {
                              urlString = signed.toString();
                           }
                        }
                      } catch (e) {
                        debugPrint("Error fetching signed URL: $e");
                        // Fallback to original urlString
                      }
                  }

                  if (urlString.isEmpty) return;

                  if (urlString.startsWith('/')) {
                     final baseUrl = ApiConfig.baseUrl; 
                     final rootUrl = baseUrl.endsWith('/api') 
                        ? baseUrl.substring(0, baseUrl.length - 4) 
                        : baseUrl;
                     
                     urlString = '$rootUrl$urlString';
                  }
                  
                  final uri = Uri.parse(urlString);
                  
                  // Simple check for PDF - launch externally
                  if (urlString.toLowerCase().contains('.pdf')) {
                       if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                       }
                       return;
                  }

                  // For images, show in-app dialog
                  final token = await ApiConfig.getAuthToken();
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (ctx) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: const EdgeInsets.all(16),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Image.network(
                                urlString,
                                // Remove headers as signed URLs (S3) conflict with Bearer tokens
                                // headers: token != null ? {'Authorization': 'Bearer $token'} : null,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(child: CircularProgressIndicator());
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.white,
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                                        const SizedBox(height: 10),
                                        Text('Failed to load image', style: TextStyle(color: Colors.black)),
                                        const SizedBox(height: 4),
                                        Text('Error: $error', style: TextStyle(color: Colors.black, fontSize: 10)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.attachment,
                      size: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.t('view_bill'),
                      style: AppTextStyles.label.copyWith(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          
          if (location != null && location.toString().isNotEmpty && location != 'Manual Entry') ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location,
                    style: AppTextStyles.label.copyWith(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 14,
                color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
              ),
              const SizedBox(width: 6),
              Text(
                '${t.t('added_by')} $createdBy',
                style: AppTextStyles.label.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String expenseId) {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.t('delete_expense')),
        content: Text(t.t('delete_expense_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.t('cancel')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final success = await ApiConfig.deleteExpense(expenseId);
              if (success) {
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t.t('expense_deleted'))),
                   );
                }
                _fetchExpenses(); // Refresh list
              } else {
                 if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to delete expense')),
                   );
                   setState(() => _isLoading = false);
                 }
              }
            },
            child: Text(t.t('delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
