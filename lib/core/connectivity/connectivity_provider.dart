import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectivityStatus { checking, online, offline }

class ConnectivityNotifier extends StateNotifier<ConnectivityStatus> {
  ConnectivityNotifier() : super(ConnectivityStatus.checking) {
    _check();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _check());
  }

  Timer? _timer;

  Future<void> _check() async {
    if (kIsWeb) {
      // On web we can't use dart:io, assume online — the HTTP requests
      // will naturally fail if the network is unavailable.
      state = ConnectivityStatus.online;
      return;
    }
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      state = result.isNotEmpty && result[0].rawAddress.isNotEmpty
          ? ConnectivityStatus.online
          : ConnectivityStatus.offline;
    } on SocketException {
      state = ConnectivityStatus.offline;
    } on TimeoutException {
      state = ConnectivityStatus.offline;
    } catch (_) {
      state = ConnectivityStatus.offline;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>(
  (_) => ConnectivityNotifier(),
);
