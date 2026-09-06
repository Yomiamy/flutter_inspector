import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/network_entry.dart';
import 'alert_throttler.dart';

/// Shows a single, continuously-updated system notification summarising network
/// activity (latest call + total count). Disabled by default; the owner enables
/// it explicitly. All platform calls degrade safely: if initialisation or
/// permission fails, the notifier silently becomes a no-op instead of crashing.
class NetworkNotifier {
  /// Creates a notifier.
  ///
  /// [plugin] can be supplied in tests to avoid the platform plugin chain.
  /// [throttler] can be supplied in tests to control timing; defaults to a
  /// production [AlertThrottler] with the standard 2-second window.
  NetworkNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    AlertThrottler? throttler,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _throttler = throttler ?? AlertThrottler(),
       _notificationId = networkNotificationId,
       _channelId = _networkChannelId,
       _channelName = _networkChannelName,
       _ongoing = true,
       _deleteLegacy = true;

  /// Creates a notifier for crash alerts.
  ///
  /// Differs from the default (network) notifier in four ways, all of which
  /// follow from crashes being *discrete events* rather than a continuously
  /// updated summary:
  /// - its own notification id, so a crash alert never overwrites the network
  ///   summary (and vice versa);
  /// - its own channel, so users can silence one category without the other;
  /// - `ongoing: false`, so the alert can be swiped away;
  /// - no legacy-channel deletion, which only ever applied to the network
  ///   channel.
  NetworkNotifier.crash({
    FlutterLocalNotificationsPlugin? plugin,
    AlertThrottler? throttler,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _throttler = throttler ?? AlertThrottler(),
       _notificationId = crashNotificationId,
       _channelId = _crashChannelId,
       _channelName = _crashChannelName,
       _ongoing = false,
       _deleteLegacy = false;

  /// Invoked when the user taps the notification (payload routing handled by
  /// the owner, e.g. opening the Network tab).
  final VoidCallback? onTap;

  final FlutterLocalNotificationsPlugin _plugin;
  final AlertThrottler _throttler;

  /// Identifies this notifier's single notification. Distinct per category so
  /// the network summary and a crash alert coexist instead of replacing one
  /// another.
  final int _notificationId;
  final String _channelId;
  final String _channelName;
  final bool _ongoing;
  final bool _deleteLegacy;

  /// Notification id of the network summary.
  @visibleForTesting
  static const int networkNotificationId = 0x6E657477; // 'netw'

  /// Notification id of a crash alert.
  @visibleForTesting
  static const int crashNotificationId = 0x63726173; // 'cras'

  static const String _networkChannelId = 'flutter_inspector_network_v2';
  static const String _networkChannelName = 'Network Inspector';

  static const String _crashChannelId = 'flutter_inspector_crash';
  static const String _crashChannelName = 'Crash Inspector';

  // The old channel ID used before T3. Kept as a named constant so the
  // deletion call below is self-documenting and easy to search/grep.
  // Android only: on init(), this channel is deleted so the system settings
  // page does not accumulate orphan channels.
  static const String _legacyChannelId = 'flutter_inspector_network';

  bool _initialized = false;
  bool _available = false;

  /// Whether the notifier successfully initialised and can post notifications.
  bool get isAvailable => _available;

  /// Initialises the plugin and requests notification permission so the host
  /// app does not have to. Safe to call once; repeat calls are no-ops. On any
  /// failure the notifier stays a no-op.
  ///
  /// Permission is requested at init time. A denied permission is the user's
  /// choice, not a failure: the notifier stays available (show() simply has no
  /// visible effect) so a later grant in system settings takes effect without
  /// re-initialising.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (_) => onTap?.call(),
      );
      _available = true;
      // Delete the legacy channel on Android so the system settings page does
      // not accumulate orphan channels. Non-Android platforms resolve to null
      // and are a natural no-op. Any failure here (missing permission, older
      // API level) must not affect the notifier's availability.
      await _deleteLegacyChannel();
      // Permission is requested after the notifier is marked available, in its
      // own guard: a denied or failed request is the user's/platform's concern,
      // not a reason to disable the notifier entirely.
      await _requestPermission();
    } catch (e) {
      _available = false;
      debugPrint('[FlutterInspector] notification init failed: $e');
    }
  }

  /// Deletes the legacy Android notification channel ([_legacyChannelId]).
  ///
  /// Android only: `resolvePlatformSpecificImplementation` returns null on
  /// all other platforms, making this a natural no-op. Any exception (e.g.
  /// older API level, missing permission) is caught and logged so it never
  /// affects [_available] or the overall init flow.
  Future<void> _deleteLegacyChannel() async {
    // Only the network notifier ever owned the legacy channel; running this
    // from the crash notifier would be a meaningless platform call.
    if (!_deleteLegacy) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.deleteNotificationChannel(channelId: _legacyChannelId);
    } catch (e) {
      debugPrint('[FlutterInspector] legacy channel deletion failed: $e');
    }
  }

  /// Requests notification permission on each platform that needs it. Wrapped in
  /// its own guard so a missing platform implementation (e.g. in tests) or a
  /// denied request never disables the notifier — it only affects whether the
  /// notification is actually shown.
  Future<void> _requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint(
        '[FlutterInspector] notification permission request failed: $e',
      );
    }
  }

  /// Builds a [NotificationDetails] for the given alert state.
  ///
  /// When [alert] is `true` (heads-up state):
  /// - Android: HIGH importance/priority, `onlyAlertOnce: false`, `silent: false`
  ///   → causes the system to display a heads-up banner.
  /// - Darwin: `presentBanner: true` → shows a foreground banner.
  ///
  /// When [alert] is `false` (silent/throttled state):
  /// - Android: `onlyAlertOnce: true`, `silent: true` (double-guard) → updates
  ///   the ongoing notification content without triggering a new alert.
  /// - Darwin: `presentBanner: false` → content update only, no banner.
  ///
  /// Both states keep the channel at HIGH importance (channel level must not
  /// change between calls) and `playSound: false`.
  ///
  /// [ongoing] defaults to `true` (the network summary is a persistent
  /// notification). Crash alerts pass `false` so the entry can be dismissed.
  @visibleForTesting
  static NotificationDetails buildDetails({
    required bool alert,
    bool ongoing = true,
    String channelId = _networkChannelId,
    String channelName = _networkChannelName,
    String channelDescription =
        'Live HTTP activity captured by Flutter Inspector',
  }) {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: ongoing,
      onlyAlertOnce: !alert,
      silent: !alert,
      playSound: false,
      showWhen: false,
    );
    final darwinDetails = DarwinNotificationDetails(
      presentAlert: alert,
      presentBanner: alert,
      presentList: true,
      presentSound: false,
    );
    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  /// Posts or updates the single network notification with [entry] and the
  /// running [totalCount]. No-op when the notifier is unavailable.
  ///
  /// The notification content (title and body) is always updated. Whether the
  /// system re-alerts the user (heads-up banner / sound) is controlled by
  /// [AlertThrottler]: at most once per 2-second window. Throttling is checked
  /// only when the notifier is available — the [_available] guard fires first
  /// so a denied-permission or uninitialised state never consumes a throttle
  /// slot.
  Future<void> showOrUpdate(NetworkEntry entry, int totalCount) async {
    if (!_available) return;
    // Throttle check is placed after the availability guard so that
    // unavailability never burns a throttle slot.
    final alert = _throttler.shouldAlert();
    try {
      final status = entry.isComplete
          ? '${entry.statusCode ?? entry.error ?? '-'}'
          : 'Pending';
      await _plugin.show(
        id: _notificationId,
        title: 'Network · $totalCount calls',
        body: '[${entry.method}] ${entry.url} · $status',
        notificationDetails: buildDetails(
          alert: alert,
          ongoing: _ongoing,
          channelId: _channelId,
          channelName: _channelName,
        ),
      );
    } catch (e) {
      debugPrint('[FlutterInspector] notification update failed: $e');
    }
  }

  /// Posts a crash alert describing [exceptionType] and [message].
  ///
  /// Mirrors [showOrUpdate]'s guard order exactly: the availability check runs
  /// first so an unavailable notifier never consumes a throttle slot. Repeated
  /// crashes within the throttle window still update the notification content;
  /// only the heads-up re-alert is suppressed.
  Future<void> showCrash({
    required String exceptionType,
    required String message,
  }) async {
    if (!_available) return;
    final alert = _throttler.shouldAlert();
    try {
      await _plugin.show(
        id: _notificationId,
        title: 'Crash · $exceptionType',
        body: _summarize(message),
        notificationDetails: buildDetails(
          alert: alert,
          ongoing: _ongoing,
          channelId: _channelId,
          channelName: _channelName,
          channelDescription: 'Uncaught errors captured by Flutter Inspector',
        ),
      );
    } catch (e) {
      debugPrint('[FlutterInspector] crash notification failed: $e');
    }
  }

  /// Collapses [message] to a single line capped at [_maxBodyLength]; a system
  /// notification shows only a couple of lines, and multi-line stack-like text
  /// renders badly.
  @visibleForTesting
  static String summarize(String message) => _summarize(message);

  static const int _maxBodyLength = 120;

  static String _summarize(String message) {
    final single = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.length <= _maxBodyLength) return single;
    return '${single.substring(0, _maxBodyLength - 1)}…';
  }

  /// Cancels the network notification, if any.
  Future<void> cancel() async {
    if (!_available) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (_) {
      // ignore
    }
  }
}
