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

class _ExpenseListSheetState extends State<ExpenseListSheet>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<dynamic> _expenses = [];
  String? _currentDriverId;
  Map<String, Map<String, dynamic>> _typeTranslations = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchDriverId();
    _fetchExpenses();
    _fetchExpenseTypes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Filter the unified expenses list per tab. Tabs are not partitions —
  /// a manual fuel entry shows in BOTH "Driver" (because source==manual)
  /// and "Fuel" (because category==fuel).
  List<dynamic> _filterFor(int tabIndex) {
    switch (tabIndex) {
      case 1: // Fuel
        return _expenses.where((e) => (e['category'] ?? '') == 'fuel').toList();
      case 2: // Fastag
        return _expenses.where((e) => (e['category'] ?? '') == 'fastag').toList();
      case 0: // Driver — only manual entries
      default:
        return _expenses.where((e) => (e['source'] ?? '') == 'manual').toList();
    }
  }

  Future<void> _fetchExpenseTypes() async {
    try {
      final response = await ApiConfig.dio.get('/driver/expenses/types');
      if (mounted && response.data is List) {
        final map = <String, Map<String, dynamic>>{};
        for (final t in response.data) {
          if (t is Map && t['name'] != null) {
            map[t['name'].toString().trim()] = Map<String, dynamic>.from(t);
          }
        }
        setState(() => _typeTranslations = map);
      }
    } catch (_) {}
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
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 0),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
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
                    color: theme.textTheme.bodyLarge?.color,
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
          const SizedBox(height: 8),

          // Tabs: Driver (manual) · Fuel (manual + card) · Fastag (manual + wallet).
          TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: theme.primaryColor,
            unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            indicatorColor: theme.primaryColor,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: [
              Tab(text: t.t('tab_driver') ?? 'Driver'),
              Tab(text: t.t('tab_fuel')   ?? 'Fuel'),
              Tab(text: t.t('tab_fastag') ?? 'Fastag'),
            ],
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTabList(_filterFor(0), t),
                      _buildTabList(_filterFor(1), t),
                      _buildTabList(_filterFor(2), t),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabList(List<dynamic> rows, LocalizationProvider t) {
    if (rows.isEmpty) {
      return Center(
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
              t.t('no_expenses') ?? 'No expenses',
              style: TextStyle(
                color: Theme.of(context).disabledColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchExpenses,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _buildExpenseCard(rows[i], t),
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
       final trimmedType = type.toString().trim();
       final typeData = _typeTranslations[trimmedType];
       final translations = typeData?['translations'];
       final langCode = t.locale.languageCode;
       if (translations is Map && translations[langCode] != null) {
         displayType = translations[langCode].toString();
       } else {
         displayType = t.translateDynamic(trimmedType);
       }
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

    final createdBy = expense['created_by_name'] ?? t.t('source_manual') ?? 'Driver';
    // Trust the server's deletable flag (only true for source='manual' entries
    // logged by THIS driver). Falls back to the legacy client-side check when
    // the server hasn't been redeployed yet.
    final canDelete = (expense['deletable'] == true)
        || (_currentDriverId != null
            && expense['source'] == 'manual'
            && expense['driver_id'] != null
            && expense['driver_id'] == _currentDriverId);

    // Source pill — localized.
    final source = (expense['source'] ?? 'manual').toString();
    final category = (expense['category'] ?? 'other').toString();
    String sourceLabel;
    Color sourceColor;
    switch (source) {
      case 'card':
        sourceLabel = t.t('source_card') ?? 'Card';
        sourceColor = const Color(0xFFEF4444);
        break;
      case 'wallet':
        sourceLabel = t.t('source_wallet') ?? 'FASTag';
        sourceColor = const Color(0xFF8B5CF6);
        break;
      case 'parivahan':
        sourceLabel = t.t('source_parivahan') ?? 'Parivahan';
        sourceColor = const Color(0xFFF59E0B);
        break;
      case 'manual':
      default:
        sourceLabel = t.t('source_manual') ?? 'Manual';
        sourceColor = AppColors.primary;
    }

    // Category icon (rendered alongside the title for quick scanning).
    IconData categoryIcon;
    switch (category) {
      case 'fuel':
        categoryIcon = Icons.local_gas_station;
        break;
      case 'fastag':
        categoryIcon = Icons.toll;
        break;
      default:
        categoryIcon = Icons.receipt_long_outlined;
    }

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
                    Row(
                      children: [
                        Icon(categoryIcon, size: 16, color: sourceColor),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            displayType,
                            style: AppTextStyles.header.copyWith(
                              fontSize: 16,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Source pill is informational only for auto-imported
                        // entries (Card / FASTag / Parivahan). Manual is the
                        // default for driver-submitted expenses, so labelling
                        // every row "Manual" is noise — hide it.
                        if (source != 'manual') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: sourceColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: sourceColor.withOpacity(0.3), width: 0.8),
                            ),
                            child: Text(
                              sourceLabel,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: sourceColor,
                              ),
                            ),
                          ),
                        ],
                      ],
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
                  '${qty.toStringAsFixed(1)} ${t.t('unit_litre_short') ?? 'L'}',
                  style: AppTextStyles.body.copyWith(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                ),
                if (ratePerL != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '@ ₹${ratePerL.toStringAsFixed(2)}/${t.t('unit_litre_short') ?? 'L'}',
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
                                        Text(t.t('failed_load_image') ?? 'Failed to load image', style: const TextStyle(color: Colors.black)),
                                        const SizedBox(height: 4),
                                        Text('${t.t('error_label') ?? 'Error'}: $error', style: const TextStyle(color: Colors.black, fontSize: 10)),
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
                      SnackBar(content: Text(t.t('failed_delete_expense') ?? 'Failed to delete expense')),
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
