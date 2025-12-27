import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerGenerator {
  static Future<BitmapDescriptor> createCustom3DMarker({required bool isDark}) async {
    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      // Size 240 allows for more detail
      const double size = 240.0;
      final double s = size / 100.0;
      
      final cx = size / 2;
      // OFFSET CY DOWN to prevent Headlight Glow from being clipped at the top (y < 0)
      final cy = (size / 2) + (30 * s); 

      // --- COLORS ---
      final cabColorCenter = const Color(0xFF2563EB); // Blue 600
      final cabColorSide = const Color(0xFF1E3A8A); // Blue 900
      
      final trailerColorCenter = const Color(0xFFFFFFFF); 
      final trailerColorSide = const Color(0xFF94A3B8);   // Slate 400

      final headlightBulbColor = const Color(0xFFFEF08A); // Yellow 200
      final beamColor = const Color(0xFFFDE047); // Yellow 300
      
      final taillightColor = const Color(0xFFEF4444); // Red 500
      final sideMarkerColor = const Color(0xFFF59E0B); // Amber 500
      final tireColor = const Color(0xFF171717); // Neutral 900

      // REDUCED WIDTHS (approx 15% reduction)
      final double trailerW = 26 * s; // Was 30*s
      final double cabW = 24 * s;     // Was 28*s
      
      // --- 1. SHADOW (Base) ---
      final shadowPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - (trailerW/2 + 2*s), cy - 35*s + 4*s, trailerW + 4*s, 95*s), 
            Radius.circular(6 * s)
        ));
      canvas.drawPath(shadowPath, Paint()..color = Colors.black.withOpacity(isDark ? 0.6 : 0.3)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0));


      // --- 2. HEADLIGHT BEAMS (Night Only) ---
      if (isDark) {
        // A. Wide Diffuse Glow (Fog light effect)
        final diffusePaint = Paint()
          ..color = beamColor.withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15.0);
        
        // Light positions closer to center now
        final lightOffset = (cabW / 2) - 4*s; 

        canvas.drawCircle(Offset(cx - lightOffset, cy - 45*s), 28*s, diffusePaint);
        canvas.drawCircle(Offset(cx + lightOffset, cy - 45*s), 28*s, diffusePaint);


        // B. Focused Projection Beams
        final beamPaint = Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, cy - 30*s),
            Offset(cx, cy - 180*s),
            [
              beamColor.withOpacity(0.5), 
              beamColor.withOpacity(0.0) 
            ],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

        // Adjust beam origin to new light positions
        final leftBeam = Path()
          ..moveTo(cx - 5*s, cy - 38*s)  // Inner edge
          ..lineTo(cx - 30*s, cy - 160*s) // Wide projection
          ..lineTo(cx + 2*s, cy - 160*s)  // Near center projection
          ..close();
        canvas.drawPath(leftBeam, beamPaint);
        
        final rightBeam = Path()
          ..moveTo(cx + 5*s, cy - 38*s)
          ..lineTo(cx + 30*s, cy - 160*s)
          ..lineTo(cx - 2*s, cy - 160*s)
          ..close();
        canvas.drawPath(rightBeam, beamPaint);
      }

      // --- 3. WHEELS ---
      // Wheel offset from center should be closer now
      final double wheelX = (trailerW / 2) + 1*s; 
      
      void drawTire(double x, double y) {
        final tireRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 3*s, height: 7*s),
          Radius.circular(1*s)
        );
        canvas.drawRRect(tireRect, Paint()..color = tireColor);
      }
      // Trailer
      drawTire(cx - wheelX, cy + 30*s); drawTire(cx + wheelX, cy + 30*s);
      drawTire(cx - wheelX, cy + 40*s); drawTire(cx + wheelX, cy + 40*s);
      drawTire(cx - wheelX, cy + 50*s); drawTire(cx + wheelX, cy + 50*s);
      // Drive
      drawTire(cx - wheelX, cy - 5*s);  drawTire(cx + wheelX, cy - 5*s);
      drawTire(cx - wheelX, cy - 14*s); drawTire(cx + wheelX, cy - 14*s);
      // Steer
      final double steerX = (cabW / 2) + 1*s;
      drawTire(cx - steerX, cy - 36*s); drawTire(cx + steerX, cy - 36*s);

      // --- 4. TRAILER BODY ---
      final trailerRect = Rect.fromCenter(center: Offset(cx, cy + 18*s), width: trailerW, height: 60*s);
      final trailerRRect = RRect.fromRectAndRadius(trailerRect, Radius.circular(3 * s));
      final trailerPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(trailerRect.left, cy),
          Offset(trailerRect.right, cy),
          [trailerColorSide, trailerColorCenter, trailerColorSide],
          [0.0, 0.5, 1.0]
        );
      canvas.drawRRect(trailerRRect, trailerPaint);
      
      // Ribs
      final ribPaint = Paint()..color = Colors.black12..strokeWidth = 0.5 * s..style = PaintingStyle.stroke;
      canvas.drawRRect(trailerRRect.deflate(2*s), ribPaint);
      for (double i = 0; i < 5; i++) {
         canvas.drawLine(Offset(trailerRect.left, trailerRect.top + 10*s + (i*10*s)), Offset(trailerRect.right, trailerRect.top + 10*s + (i*10*s)), ribPaint);
      }

      // --- 5. CAB BODY ---
      final cabRect = Rect.fromCenter(center: Offset(cx, cy - 28*s), width: cabW, height: 26*s);
      final cabRRect = RRect.fromRectAndRadius(cabRect, Radius.circular(5 * s));
      final cabPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(cabRect.left, cy),
          Offset(cabRect.right, cy),
          [cabColorSide, cabColorCenter, cabColorSide],
          [0.0, 0.5, 1.0]
        );
      canvas.drawRRect(cabRRect, cabPaint);
      
      // Air Deflector (Narrower)
      final deflectorPath = Path()
        ..moveTo(cx - 8*s, cy - 25*s) // Narrower base
        ..quadraticBezierTo(cx, cy - 30*s, cx + 8*s, cy - 25*s)
        ..lineTo(cx + 6*s, cy - 15*s)
        ..lineTo(cx - 6*s, cy - 15*s)
        ..close();
      canvas.drawPath(deflectorPath, Paint()..color = cabColorSide.withOpacity(0.5));

      // Windshield
      final glassRect = Rect.fromCenter(center: Offset(cx, cy - 34*s), width: cabW - 4*s, height: 7*s);
      canvas.drawPath(Path()..addRRect(RRect.fromRectAndRadius(glassRect, Radius.circular(4*s))), Paint()..color = Colors.black87);
      
      // Reflection
      final reflectionPath = Path()
        ..moveTo(glassRect.left + 5*s, glassRect.bottom - 2*s)
        ..lineTo(glassRect.left + 9*s, glassRect.top + 2*s)
        ..lineTo(glassRect.left + 11*s, glassRect.top + 2*s)
        ..lineTo(glassRect.left + 7*s, glassRect.bottom - 2*s)
        ..close();
      canvas.drawPath(reflectionPath, Paint()..color = Colors.white24);

      // Mirrors (Moved in)
      canvas.drawRect(Rect.fromLTWH(cx - (cabW/2 + 2*s), cy - 36*s, 2*s, 6*s), Paint()..color = Colors.black54);
      canvas.drawRect(Rect.fromLTWH(cx + (cabW/2), cy - 36*s, 2*s, 6*s), Paint()..color = Colors.black54);

      // --- 6. LIGHTS ---
      // Headlight bulbs (Moved in)
      final lightX = (cabW / 2) - 4*s;
      canvas.drawCircle(Offset(cx - lightX, cy - 39*s), 2.5*s, Paint()..color = headlightBulbColor);
      canvas.drawCircle(Offset(cx + lightX, cy - 39*s), 2.5*s, Paint()..color = headlightBulbColor);
      
      // Taillights
      final tailX = (trailerW / 2) - 3*s;
      canvas.drawRect(Rect.fromLTWH(cx - tailX - 5*s, cy + 48*s, 5*s, 2*s), Paint()..color = taillightColor);
      canvas.drawRect(Rect.fromLTWH(cx + tailX, cy + 48*s, 5*s, 2*s), Paint()..color = taillightColor);

      // Markers
      final roofMarkerPaint = Paint()..color = sideMarkerColor;
      for (int i = -1; i <= 1; i++) { // Fewer roof markers
         canvas.drawCircle(Offset(cx + (i * 4 * s), cy - 30 * s), 0.8*s, roofMarkerPaint);
      }
      if (isDark) {
         final sideX = (trailerW / 2) - 1*s;
         for (int i = 0; i < 4; i++) {
           canvas.drawCircle(Offset(cx - sideX, cy + (i * 12 * s)), 1*s, roofMarkerPaint);
           canvas.drawCircle(Offset(cx + sideX, cy + (i * 12 * s)), 1*s, roofMarkerPaint);
         }
      }

      final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      }
      
      return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
    } catch (e) {
      debugPrint("Error creating 3D marker: $e");
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
  }
}
