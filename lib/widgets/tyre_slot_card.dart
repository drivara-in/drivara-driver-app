import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TyreSlotCard extends StatelessWidget {
  final String positionKey; // e.g., "A1-L" or "A1-LO"
  final Map<String, dynamic> details; // {brand, model, serial, kms, etc.}
  final bool isSelected;
  final bool isSource;
  final VoidCallback onTap;

  const TyreSlotCard({
    super.key,
    required this.positionKey,
    required this.details,
    required this.isSelected,
    required this.isSource,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Determine status
    final hasDetails = (details['brand'] != null && details['brand'].toString().isNotEmpty) ||
                       (details['model'] != null && details['model'].toString().isNotEmpty);

    final borderColor = isSelected 
        ? Colors.blue.shade500 
        : (hasDetails ? Colors.grey.shade300 : Colors.grey.shade300);
    
    final bgColor = isSelected 
        ? Colors.blue.shade50 
        : (hasDetails ? Colors.white : Colors.grey.shade50);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
            style: hasDetails ? BorderStyle.solid : BorderStyle.none, // Dashed simulation via custom painter if needed, but solid is fine for now
          ),
          boxShadow: isSelected 
             ? [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]
             : (hasDetails ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : null),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Key & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue.shade100 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    positionKey,
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.blue.shade800 : Colors.grey.shade700,
                    ),
                  ),
                ),
                if (!hasDetails)
                   Icon(Icons.add_circle_outline, size: 16, color: Colors.blue.shade300)
              ],
            ),
            const SizedBox(height: 8),

            // Body: Brand / Model
            Expanded(
              child: hasDetails 
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        details['brand'] ?? 'Unknown',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              details['model'] ?? '-',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle_outlined, size: 24, color: Colors.grey.shade300),
                        const SizedBox(height: 4),
                        Text(
                          "Empty", 
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w600)
                        ),
                      ],
                    ),
                  ),
            ),
            
            // Footer: Serial / KM
            if (hasDetails) ...[
               const Divider(height: 12),
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   // Serial
                   Flexible(
                     child: Container(
                       padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                       decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                       child: Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           Text("SN", style: GoogleFonts.inter(fontSize: 8, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                           const SizedBox(width: 4),
                           Flexible(
                             child: Text(
                               _formatSerial(details['serial']), 
                               style: GoogleFonts.robotoMono(fontSize: 9, color: Colors.grey.shade800),
                               overflow: TextOverflow.ellipsis,
                             ),
                           ),
                         ],
                       ),
                     ),
                   ),
                   const SizedBox(width: 4),
                   // KM
                   if (details['kms'] != null)
                     Container(
                       padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                       decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade100)),
                       child: Row(
                         children: [
                            Icon(Icons.trending_up, size: 10, color: Colors.green.shade700),
                            const SizedBox(width: 2),
                            Text(
                              "${details['kms']}", 
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade800)
                            ),
                         ],
                       ),
                     )
                 ],
               )
            ]
          ],
        ),
      ),
    );
  }

  String _formatSerial(String? serial) {
    if (serial == null) return "—";
    if (serial.length > 8) return "••${serial.substring(serial.length - 4)}";
    return serial;
  }
}
