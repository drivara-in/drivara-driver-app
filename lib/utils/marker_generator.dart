import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerGenerator {
  static Future<BitmapDescriptor> createCustom3DMarker() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 250.0; // BIGGER Size
    final double s = size / 120.0; // Scale factor based on original design
    
    // 1. Glow / Illumination (Radial Gradient)
    final Paint glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size / 2, size / 2),
        size / 2,
        [
          Colors.blueAccent.withOpacity(0.6),
          Colors.blueAccent.withOpacity(0.0),
        ],
      );
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, glowPaint);

    // 2. 3D Truck Body
    final double cx = size / 2;
    final double cy = size / 2;
    
    // Truck Cab (Blue Rectangle)
    final Paint cabPaint = Paint()..color = Colors.blue[800]!;
    final Rect cabRect = Rect.fromCenter(center: Offset(cx, cy - (10 * s)), width: 20 * s, height: 25 * s);
    canvas.drawRRect(RRect.fromRectAndRadius(cabRect, Radius.circular(4 * s)), cabPaint);
    
    // Truck Trailer (White/Grey Rectangle)
    final Paint trailerPaint = Paint()..color = Colors.grey[200]!;
    final Rect trailerRect = Rect.fromCenter(center: Offset(cx, cy + (15 * s)), width: 24 * s, height: 40 * s);
    // Shadow for trailer
    canvas.drawRRect(RRect.fromRectAndRadius(trailerRect.shift(Offset(2 * s, 2 * s)), Radius.circular(2 * s)), Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawRRect(RRect.fromRectAndRadius(trailerRect, Radius.circular(2 * s)), trailerPaint);

    // Windshield (Black)
    canvas.drawRect(Rect.fromLTWH(cx - (8 * s), cy - (18 * s), 16 * s, 6 * s), Paint()..color = Colors.black87);
    
    // Headlights (Bright Yellow/White Beam effect) - "Illuminated"
    final Paint lightPaint = Paint()..color = Colors.yellowAccent.withOpacity(0.8)..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * s);
    // Left Light Beam
    final Path leftBeam = Path()
      ..moveTo(cx - (8 * s), cy - (22 * s))
      ..lineTo(cx - (15 * s), cy - (50 * s))
      ..lineTo(cx - (2 * s), cy - (50 * s))
      ..close();
    canvas.drawPath(leftBeam, lightPaint);
    
    // Right Light Beam
    final Path rightBeam = Path()
      ..moveTo(cx + (8 * s), cy - (22 * s))
      ..lineTo(cx + (15 * s), cy - (50 * s))
      ..lineTo(cx + (2 * s), cy - (50 * s))
      ..close();
    canvas.drawPath(rightBeam, lightPaint);
    
    // Actual Headlights (Small dots)
    canvas.drawCircle(Offset(cx - (8 * s), cy - (22 * s)), 2 * s, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + (8 * s), cy - (22 * s)), 2 * s, Paint()..color = Colors.white);

    // Convert to Image
    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) {
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
    
    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }
}
