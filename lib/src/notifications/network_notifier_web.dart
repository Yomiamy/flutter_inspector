import 'package:flutter/foundation.dart';

import '../models/network_entry.dart';
import 'alert_throttler.dart';

/// Web stub of [NetworkNotifier]: a permanent no-op.
///
/// The notifier has never configured web initialization settings, so web
/// builds have never shown notifications. This stub preserves that behaviour
/// while keeping `flutter_local_notifications` (which transitively imports
/// `dart:io`) out of the web import graph for WASM compatibility.
class NetworkNotifier {
  /// Creates a no-op notifier. Parameters mirror the native implementation so
  /// call sites compile unchanged; [plugin] is accepted but never used.
  NetworkNotifier({Object? plugin, AlertThrottler? throttler, this.onTap});

  /// Creates a no-op crash notifier. Mirrors the native named constructor so
  /// shared call sites compile on web.
  NetworkNotifier.crash({
    Object? plugin,
    AlertThrottler? throttler,
    this.onTap,
  });

  /// Invoked when the user taps the notification. Never fires on web.
  final VoidCallback? onTap;

  /// Notification id of the network summary. Mirrors the native constant so
  /// shared code and tests can reference it on web.
  @visibleForTesting
  static const int networkNotificationId = 0x6E657477; // 'netw'

  /// Notification id of a crash alert.
  @visibleForTesting
  static const int crashNotificationId = 0x63726173; // 'cras'

  /// Always `false`: notifications are not supported on the web build.
  bool get isAvailable => false;

  /// No-op; the notifier stays unavailable.
  Future<void> init() async {}

  /// No-op.
  Future<void> showOrUpdate(NetworkEntry entry, int totalCount) async {}

  /// No-op.
  Future<void> showCrash({
    required String exceptionType,
    required String message,
  }) async {}

  /// No-op.
  Future<void> cancel() async {}
}
