import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';

class JobStreamService {
  final String jobId;
  http.Client? _client;
  StreamController<Map<String, dynamic>>? _controller;
  bool _isClosed = false;

  JobStreamService({required this.jobId});

  Stream<Map<String, dynamic>> connect() {
    _controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: _startStream,
      onCancel: dispose,
    );
    return _controller!.stream;
  }

  void _startStream() async {
    if (_isClosed) return;
    
    _client = http.Client();
    final token = await ApiConfig.getAuthToken();
    // Use the driver-specific streaming endpoint
    final url = Uri.parse('${ApiConfig.baseUrl}/driver/jobs/$jobId/tracking/stream');

    try {
      debugPrint("Connecting to stream: $url");
      final request = http.Request('GET', url);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'text/event-stream';

      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        debugPrint("Stream failed: ${response.statusCode}");
        _controller?.addError("Stream failed: ${response.statusCode}");
        return;
      }

      response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('data:')) {
             final data = line.substring(5).trim();
             if (data == '"ok"' || data == '"keep-alive"') return;
             try {
                final json = jsonDecode(data);
                _controller?.add(json);
             } catch (e) {
                // debugPrint("Stream Parse Error: $e");
             }
          }
        }, onError: (e) {
           debugPrint("Stream Error: $e");
           _controller?.addError(e);
        });

    } catch (e) {
      debugPrint("Stream Connection Error: $e");
      if (!_isClosed) _controller?.addError(e);
    }
  }

  void dispose() {
    _isClosed = true;
    _client?.close();
    _controller?.close();
  }
}
