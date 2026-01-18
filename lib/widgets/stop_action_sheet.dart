import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../api_config.dart'; // For file upload
import 'package:dio/dio.dart';

class StopActionSheet extends StatefulWidget {
  final String title;
  final String uploadLabel;
  final Function(DateTime time, String? fileId, String? notes) onSubmit;
  final bool isLoading;
  final bool requireFile;

  const StopActionSheet({
    required this.title,
    required this.onSubmit,
    this.uploadLabel = "Gate Pass / Proof (Optional)",
    this.isLoading = false,
    this.requireFile = false,
    super.key
  });

  @override
  State<StopActionSheet> createState() => _StopActionSheetState();
}

class _StopActionSheetState extends State<StopActionSheet> {
  DateTime _selectedTime = DateTime.now();
  String? _uploadedFileId;
  String? _fileName;
  bool _isUploading = false;
  final TextEditingController _notesCtrl = TextEditingController();

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTime),
    );

    if (pickedTime != null) {
      final newDt = DateTime(now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);
      setState(() => _selectedTime = newDt);
    }
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
            _uploadedFileId = response.data['id']; // Adjust based on actual API response
            _fileName = fileName;
          });
       }
    } catch (e) {
      debugPrint("Upload Failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload Failed")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(widget.title, style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
            ],
          ),
          const SizedBox(height: 20),
          
          // Time Picker
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.blueAccent),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Time", style: AppTextStyles.label.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('hh:mm a').format(_selectedTime),
                        style: AppTextStyles.header.copyWith(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color),
                      )
                    ],
                  ),
                  const Spacer(),
                  const Text("Change", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Removed File Upload UI as per request
          /*
          // File Upload
          Text(widget.uploadLabel, style: AppTextStyles.label),
          const SizedBox(height: 8),
          Center(
              child: _uploadedFileId != null
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green)),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_fileName ?? "Uploaded", overflow: TextOverflow.ellipsis)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() { _uploadedFileId = null; _fileName = null; }))
                    ],
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : () => _pickImage(ImageSource.camera),
                        icon: _isUploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt),
                        label: const Text("Camera"),
                        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).cardColor, foregroundColor: Theme.of(context).textTheme.bodyLarge?.color, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: Theme.of(context).dividerColor)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : () => _pickImage(ImageSource.gallery),
                        icon: _isUploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library),
                        label: const Text("Gallery"),
                        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).cardColor, foregroundColor: Theme.of(context).textTheme.bodyLarge?.color, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: Theme.of(context).dividerColor)),
                      ),
                    ),
                  ],
              )
          ),
          
          if (widget.requireFile && _uploadedFileId == null)
             Padding(
               padding: const EdgeInsets.only(top: 8),
               child: Text("* File is required", style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
             ), 
          */

          const SizedBox(height: 20),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: "Notes (Optional)",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).cardColor
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (widget.isLoading) ? null : () {
                // Ignore file upload
                widget.onSubmit(_selectedTime, null, _notesCtrl.text);
              },
              style: AppTheme.darkTheme.elevatedButtonTheme.style!.copyWith(
                backgroundColor: MaterialStateProperty.all(AppColors.primary),
              ),
              child: widget.isLoading 
                ? const CircularProgressIndicator(color: Colors.white)
                : Text("Confirm ${widget.title.split(' ').first}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
