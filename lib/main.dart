import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:firebase_core/firebase_core.dart';

import 'app/app.dart';
import 'core/env/app_environment.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final env = AppEnvironmentRuntime.current;

  await Hive.initFlutter();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // Local/testing mode: continue without Firebase on platforms
    // not configured in firebase_options.dart.
  }

  if (env.verboseLogging) {
    // ignore: avoid_print
    print('Starting app in ${env.environment.name} environment');
    // ignore: avoid_print
    print('API base URL: ${env.apiBaseUrl}');
  }

  runApp(const ProviderScope(child: FDApp()));
}