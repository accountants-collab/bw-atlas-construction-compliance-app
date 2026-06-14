import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Art04GapsScreen extends StatelessWidget {
  const Art04GapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ART04 - Door gaps')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This screen is deprecated',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ART04 gap measurements are now captured directly inside the Inspection flow '
                  '(Door gaps incorrect → Fail/Critical → Top/Bottom/Left/Right mm).',
                  style: TextStyle(color: Colors.black54, height: 1.3),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}