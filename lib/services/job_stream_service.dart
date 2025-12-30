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
    int retryCount = 0;
    while (!_isClosed) {
      if (retryCount > 0) {
        debugPrint("Reconnecting to stream in 3s... (Attempt $retryCount)");
        await Future.delayed(const Duration(seconds: 3));
      }
      if (_isClosed) break;

      _client = http.Client();
      final token = await ApiConfig.getAuthToken();
      if (token == null) {
         debugPrint("JobStreamService: Token is null, waiting...");
         await Future.delayed(const Duration(seconds: 2));
         continue;
      }

      final url = Uri.parse('${ApiConfig.baseUrl}/driver/jobs/$jobId/tracking/stream');

      try {
        debugPrint("Connecting to stream: $url");
        final request = http.Request('GET', url);
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['Accept'] = 'text/event-stream';

        final response = await _client!.send(request);

        if (response.statusCode != 200) {
          debugPrint("Stream connection failed: ${response.statusCode}");
          // Don't crash, just retry
          retryCount++;
          continue;
        }

        // Reset retry count on successful connection
        retryCount = 0;

        await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
            if (_isClosed) break;
            if (line.startsWith('data:')) {
               final data = line.substring(5).trim();
               if (data == '"ok"' || data == '"keep-alive"') continue;
               try {
                  final json = jsonDecode(data);
                  if (!_controller!.isClosed) _controller?.add(json);
               } catch (e) {
                  // Ignore parse errors
               }
            }
        }
      } catch (e) {
        debugPrint("Stream Disconnected: $e");
        // Loop will continue and retry
        retryCount++;
      } finally {
        _client?.close();
      }
    }
  }

  void dispose() {
    _isClosed = true;
    _client?.close();
    _controller?.close();
  }
}
