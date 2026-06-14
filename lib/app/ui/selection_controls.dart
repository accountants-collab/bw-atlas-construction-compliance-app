import 'package:flutter/material.dart';

class AppSelectionColors {
  // Pass/approved outcomes — only for explicit user-confirmed success
  static const selectedGreen = Color(0xFF2E7D32);
  static const selectedFailRed = Color(0xFFC62828);
  static const selectedFill = Color(0xFFE8F5E9);

  // Neutral acknowledged state — for selector cards and field highlights
  static const acknowledgedBlue = Color(0xFF1565C0);
  static const acknowledgedBlueFill = Color(0xFFE3F0FF);
  static const acknowledgedBlueBorder = Color(0xFFBDD4F0);

  const AppSelectionColors._();
}

InputDecoration appSelectFieldDecoration({
  required String labelText,
  required bool hasSelection,
  String? hintText,
}) {
  final borderColor = hasSelection ? AppSelectionColors.acknowledgedBlue : Colors.grey;
  final fillColor = hasSelection ? AppSelectionColors.acknowledgedBlueFill : null;

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    border: const OutlineInputBorder(),
    filled: hasSelection,
    fillColor: fillColor,
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: hasSelection ? AppSelectionColors.acknowledgedBlue : Colors.blue,
        width: 2,
      ),
    ),
  );
}

class AppChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Color selectedColor;

  const AppChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.selectedColor = AppSelectionColors.selectedGreen,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected ? selectedColor : Colors.white;
    final borderColor = selected ? selectedColor : Colors.grey.shade300;
    final textColor = selected ? Colors.white : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class AppSelectorCard extends StatelessWidget {
  final String title;
  final String value;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isSelected;

  const AppSelectorCard({
    super.key,
    required this.title,
    required this.value,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppSelectionColors.acknowledgedBlueBorder
        : Colors.grey.shade300;

    return Card(
      elevation: 0,
      color: isSelected ? AppSelectionColors.acknowledgedBlueFill : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPressed,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isSelected
                            ? AppSelectionColors.acknowledgedBlue
                            : Colors.grey.shade400,
                      ),
                      foregroundColor: isSelected
                          ? AppSelectionColors.acknowledgedBlue
                          : Colors.black54,
                      minimumSize: const Size(0, 48),
                    ),
                    icon: Icon(icon),
                    label: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
