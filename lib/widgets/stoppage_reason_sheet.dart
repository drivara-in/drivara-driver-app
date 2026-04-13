import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';

class StoppageReasonSheet extends StatefulWidget {
  final Function(String reason, String? notes, String? photoUploadId) onSubmit;
  final DateTime stoppedSince;
  final bool isLoading;

  const StoppageReasonSheet({
    required this.onSubmit,
    required this.stoppedSince,
    this.isLoading = false,
    super.key,
  });

  @override
  State<StoppageReasonSheet> createState() => _StoppageReasonSheetState();
}

class _StoppageReasonSheetState extends State<StoppageReasonSheet> {
  String? _selectedReason;
  String? _uploadedPhotoId;
  String? _photoFileName;
  bool _isUploading = false;
  String? _errorText;
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _otherCtrl = TextEditingController();
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  static const List<Map<String, dynamic>> _reasons = [
    {'key': 'tea_food', 'locKey': 'stoppage_tea_food', 'icon': Icons.restaurant},
    {'key': 'rest_sleep', 'locKey': 'stoppage_rest_sleep', 'icon': Icons.hotel},
    {'key': 'fuel_fill', 'locKey': 'stoppage_fuel_fill', 'icon': Icons.local_gas_station},
    {'key': 'mechanical_issue', 'locKey': 'stoppage_mechanical_issue', 'icon': Icons.build},
    {'key': 'tyre_issue', 'locKey': 'stoppage_tyre_issue', 'icon': Icons.tire_repair},
    {'key': 'traffic_road_block', 'locKey': 'stoppage_traffic', 'icon': Icons.traffic},
    {'key': 'police_rto_check', 'locKey': 'stoppage_police_rto', 'icon': Icons.local_police},
    {'key': 'unplanned_loading_unloading', 'locKey': 'stoppage_unplanned_lu', 'icon': Icons.inventory},
    {'key': 'personal', 'locKey': 'stoppage_personal', 'icon': Icons.person},
    {'key': 'waiting_instructions', 'locKey': 'stoppage_waiting', 'icon': Icons.hourglass_top},
    {'key': 'waiting_at_stop', 'locKey': 'stoppage_waiting_at_stop', 'icon': Icons.access_time_filled},
    {'key': 'other', 'locKey': 'stoppage_other', 'icon': Icons.more_horiz},
  ];

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.stoppedSince);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.stoppedSince);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notesCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source, imageQuality: 70);
      if (image != null) {
        await _uploadFile(File(image.path));
      }
    } catch (e) {
      debugPrint("Image Pick Error: $e");
    }
  }

  Future<void> _uploadFile(File file) async {
    setState(() => _isUploading = true);
    try {
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final response = await ApiConfig.dio.post('/upload', data: formData);
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _uploadedPhotoId = response.data['id'];
          _photoFileName = fileName;
        });
      }
    } catch (e) {
      debugPrint("Upload Failed: $e");
      if (mounted) setState(() => _errorText = "Upload Failed");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _submit() {
    if (_selectedReason == null) {
      setState(() => _errorText = 'Please select a reason');
      return;
    }
    if (_selectedReason == 'other' && _otherCtrl.text.trim().isEmpty) {
      setState(() => _errorText = 'Please specify the reason');
      return;
    }
    setState(() => _errorText = null);

    String notes = _notesCtrl.text.trim();
    if (_selectedReason == 'other') {
      notes = '${_otherCtrl.text.trim()}${notes.isNotEmpty ? '\n$notes' : ''}';
    }

    widget.onSubmit(_selectedReason!, notes.isEmpty ? null : notes, _uploadedPhotoId);
  }

  @override
  Widget build(BuildContext context) {
    final loc = Provider.of<LocalizationProvider>(context);
    String t(String key) => loc.t(key) ?? key;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    t('stoppage_why'),
                    style: AppTextStyles.header.copyWith(
                      fontSize: 20,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Stopped duration badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    '${t('stoppage_stopped_for')} ${_formatDuration(_elapsed)}',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Reason chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reasons.map((r) {
                final isSelected = _selectedReason == r['key'];
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        r['icon'] as IconData,
                        size: 16,
                        color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                      const SizedBox(width: 6),
                      Text(t(r['locKey'] as String)),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedReason = selected ? r['key'] as String : null;
                      _errorText = null;
                    });
                  },
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  backgroundColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : Theme.of(context).dividerColor,
                    ),
                  ),
                );
              }).toList(),
            ),

            // "Other" text field
            if (_selectedReason == 'other') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otherCtrl,
                decoration: InputDecoration(
                  labelText: t('stoppage_other_hint'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
                maxLines: 1,
              ),
            ],

            const SizedBox(height: 16),

            // Notes
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: t('notes'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 16),

            // Photo upload
            Text(
              t('stoppage_photo_optional'),
              style: AppTextStyles.label.copyWith(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 8),
            if (_uploadedPhotoId != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_photoFileName ?? "Uploaded", overflow: TextOverflow.ellipsis)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => setState(() {
                        _uploadedPhotoId = null;
                        _photoFileName = null;
                      }),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : () => _pickImage(ImageSource.camera),
                      icon: _isUploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.camera_alt),
                      label: const Text("Camera"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : () => _pickImage(ImageSource.gallery),
                      icon: _isUploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.photo_library),
                      label: const Text("Gallery"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 20),

            // Error
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: widget.isLoading ? null : _submit,
                style: AppTheme.darkTheme.elevatedButtonTheme.style!.copyWith(
                  backgroundColor: WidgetStateProperty.all(AppColors.primary),
                ),
                child: widget.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        t('stoppage_submit'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
