import 'package:flutter/material.dart';

class QuickLoginDialogs {
  static final _pinRegex = RegExp(r'^\d{4}$');

  static Future<String?> showCreatePinDialog(
    BuildContext context, {
    String title = 'Set 4-digit PIN',
  }) async {
    final pinA = TextEditingController();
    final pinB = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pinA,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      hintText: '4 digits',
                    ),
                  ),
                  TextField(
                    controller: pinB,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      hintText: 'Repeat PIN',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final a = pinA.text.trim();
                    final b = pinB.text.trim();
                    if (!_pinRegex.hasMatch(a)) {
                      setState(() => error = 'PIN must be exactly 4 digits.');
                      return;
                    }
                    if (a != b) {
                      setState(() => error = 'PINs do not match.');
                      return;
                    }
                    Navigator.of(ctx).pop(a);
                  },
                  child: const Text('Save PIN'),
                ),
              ],
            );
          },
        );
      },
    );

    pinA.dispose();
    pinB.dispose();
    return result;
  }

  static Future<String?> showEnterPinDialog(
    BuildContext context, {
    String title = 'Enter 4-digit PIN',
  }) async {
    final pin = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      hintText: '4 digits',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = pin.text.trim();
                    if (!_pinRegex.hasMatch(value)) {
                      setState(() => error = 'PIN must be exactly 4 digits.');
                      return;
                    }
                    Navigator.of(ctx).pop(value);
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    pin.dispose();
    return result;
  }
}
