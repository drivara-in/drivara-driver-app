import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TyreWidget extends StatelessWidget {
  final String positionKey;
  final Map<String, dynamic> details;
  final bool isSelected;
  final bool isSource;
  final VoidCallback onTap;

  const TyreWidget({
    super.key,
    required this.positionKey,
    required this.details,
    required this.isSelected,
    required this.isSource,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasTyre = details.isNotEmpty && (details['brand'] != null || details['model'] != null);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Size for the tyre widget
    const double width = 60;
    const double height = 110;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        transform: isSelected ? Matrix4.diagonal3Values(1.1, 1.1, 1.0) : Matrix4.identity(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Tyre Body (The Rubber)
            Container(
              decoration: BoxDecoration(
                gradient: hasTyre 
                  ? const LinearGradient(colors: [Color(0xFF333333), Color(0xFF111111)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
                color: hasTyre ? null : (isDark ? Colors.white10 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected 
                  ? [BoxShadow(color: Colors.green.withOpacity(0.6), blurRadius: 12, spreadRadius: 2)] 
                  : [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(2, 4))],
                border: isSelected ? Border.all(color: Colors.greenAccent, width: 2) : Border.all(color: Colors.white10, width: 1),
              ),
              child: hasTyre ? CustomPaint(
                painter: TyreTreadPainter(),
                child: Container(),
              ) : Center(child: Icon(Icons.add, color: isDark ? Colors.white30 : Colors.white70)),
            ),

            // Info Overlay (Label)
            if (hasTyre)
              Positioned(
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 0.5)
                  ),
                  child: Text(
                    positionKey,
                    style: GoogleFonts.robotoMono(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
            if (hasTyre)
              Positioned(
                bottom: 10,
                left: 4,
                right: 4,
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        details['brand'] ?? '',
                         style: GoogleFonts.oswald(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
                         textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatSerial(details['serial']),
                         style: GoogleFonts.robotoMono(fontSize: 8, color: Colors.white54),
                         textAlign: TextAlign.center,
                      ),
                    )
                  ],
                ),
              ),
              
            // Missing Tyre Label
            if (!hasTyre)
              Positioned(
                bottom: 8,
                child: Text(
                   positionKey,
                    style: GoogleFonts.robotoMono(
                        fontSize: 10, 
                        color: isDark ? Colors.white54 : Colors.grey.shade600, 
                        fontWeight: FontWeight.bold
                    ),
                ),
              )
          ],
        ),
      ),
    );
  }
  
  String _formatSerial(String? serial) {
    if (serial == null) return "-";
    if (serial.length > 5) return "...${serial.substring(serial.length - 4)}";
    return serial;
  }
}

class TyreTreadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw some stylized tread lines
    final path = Path();
    for (double y = 10; y < size.height - 10; y += 8) {
       path.moveTo(4, y);
       path.lineTo(size.width / 2, y + 4);
       path.lineTo(size.width - 4, y);
    }
    canvas.drawPath(path, paint);
    
    // Vertical grooves
    final groovePaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
      
    canvas.drawLine(Offset(size.width * 0.3, 5), Offset(size.width * 0.3, size.height-5), groovePaint);
    canvas.drawLine(Offset(size.width * 0.7, 5), Offset(size.width * 0.7, size.height-5), groovePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
