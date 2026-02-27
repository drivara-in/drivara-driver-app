import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../api_config.dart';
import '../providers/localization_provider.dart';
import '../theme/app_theme.dart';

class StopCompletionSheet extends StatefulWidget {
  final Map<String, dynamic> stop;
  final int stopIndex;
  final Function(String? fileId, String? notes) onSubmit;

  const StopCompletionSheet({
    Key? key,
    required this.stop,
    required this.stopIndex,
    required this.onSubmit
  }) : super(key: key);

  @override
  State<StopCompletionSheet> createState() => _StopCompletionSheetState();
}

class _StopCompletionSheetState extends State<StopCompletionSheet> {
  final TextEditingController _notesController = TextEditingController();
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  String? _errorText;
  
  // Decide if POD is mandatory based on stop type
  // Usually Unloading or Dropoff requires POD.
  bool get _isPodMandatory {
      final type = widget.stop['type'];
      return type == 'unloading' || type == 'dropoff';
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _submit() async {
      final t = Provider.of<LocalizationProvider>(context, listen: false);
      if (_isPodMandatory && _imageFile == null) {
          setState(() => _errorText = t.t('pod_required_error') ?? "Proof of Delivery photo is required");
          return;
      }

      setState(() { _errorText = null; _isUploading = true; });

      String? fileId;
      try {
          if (_imageFile != null) {
             fileId = await ApiConfig.uploadFile(_imageFile!.path);
          }
          
          widget.onSubmit(fileId, _notesController.text);
          if (mounted) Navigator.pop(context);

      } catch (e) {
          debugPrint("Upload failed: $e");
          if (mounted) setState(() => _errorText = "Upload failed: $e");
      } finally {
          if (mounted) setState(() => _isUploading = false);
      }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    final type = widget.stop['type'] ?? 'stop';
    final title = type == 'loading' ? t.t('finish_loading') : (type == 'unloading' ? t.t('finish_unloading') : t.t('complete_stop'));

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(title, style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color)),
            const SizedBox(height: 8),
            Text("Stop ${widget.stopIndex + 1}: ${widget.stop['address'] ?? ''}", style: AppTextStyles.body.copyWith(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 24),

            // Camera/Gallery Buttons
            Text(
                _isPodMandatory ? "${t.t('upload_pod') ?? 'Upload Proof of Delivery'} *" : "${t.t('upload_pod') ?? 'Upload Proof of Delivery'}", 
                style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 12),
            
            if (_imageFile != null)
                Stack(
                    children: [
                        ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_imageFile!, height: 160, width: double.infinity, fit: BoxFit.cover),
                        ),
                        Positioned(
                            top: 8, right: 8,
                            child: InkWell(
                                onTap: () => setState(() => _imageFile = null),
                                child: Container(
                                    padding: const EdgeInsets.all(6),
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
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                         ),
                       ),
                       const SizedBox(width: 16),
                       Expanded(
                         child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: Text(t.t('gallery')),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                         ),
                       ),
                   ],
                ),
            
            const SizedBox(height: 24),

            // Notes
            TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: t.t('notes') ?? "Notes / Remarks",
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                ),
            ),
            
            const SizedBox(height: 16),

            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w500)),
              ),

            SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                    onPressed: _isUploading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    child: _isUploading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(t.t('submit_complete') ?? "Complete & Submit", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
            )
        ],
      )
    );
  }
}
