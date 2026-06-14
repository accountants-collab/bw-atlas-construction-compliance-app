import 'package:flutter/material.dart';

import '../../content/info_content.dart';

class InfoPageScaffold extends StatelessWidget {
  final InfoPageContent content;
  final Widget? drawer;

  const InfoPageScaffold({
    super.key,
    required this.content,
    this.drawer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(content.title)),
      drawer: drawer,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final horizontal = wide ? 24.0 : 16.0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
                children: [
                  _HeroSummary(subtitle: content.subtitle),
                  const SizedBox(height: 12),
                  for (final section in content.sections) ...[
                    _InfoSectionCard(section: section),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  final String subtitle;

  const _HeroSummary({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFF5F8FC),
        border: Border.all(color: const Color(0xFFD7E3F4)),
      ),
      child: Text(
        subtitle,
        style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _InfoSectionCard extends StatelessWidget {
  final InfoSection section;

  const _InfoSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            if (section.paragraphs.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final paragraph in section.paragraphs) ...[
                SelectableText(
                  paragraph,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 6),
              ],
            ],
            if (section.bullets.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final bullet in section.bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.circle, size: 8, color: Colors.black54),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          bullet,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
