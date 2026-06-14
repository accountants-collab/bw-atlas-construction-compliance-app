import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BwBookingPromoCard extends StatelessWidget {
  final EdgeInsetsGeometry? margin;

  const BwBookingPromoCard({
    super.key,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B3D2E), Color(0xFF147A5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B3D2E),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Need certified specialists to do the work for you?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Book BW Atlas directly for fire door surveys, installation, remedial works, and maintenance support.',
              style: TextStyle(color: Colors.white, height: 1.35),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0B3D2E),
              ),
              onPressed: () => context.go('/book-services'),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Request a Quote'),
            ),
          ],
        ),
      ),
    );
  }
}
