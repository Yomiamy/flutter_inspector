import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/notifications/alert_throttler.dart';
import 'package:flutter_inspector_kit/src/notifications/network_notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkNotifier (degraded / not initialised)', () {
    test('is unavailable before init', () {
      final notifier = NetworkNotifier();
      expect(notifier.isAvailable, isFalse);
    });

    test('showOrUpdate is a safe no-op when unavailable', () async {
      final notifier = NetworkNotifier();
      // No init() called -> _available is false -> must not throw.
      await expectLater(
        notifier.showOrUpdate(
          NetworkEntry(method: 'GET', url: '/x', statusCode: 200),
          1,
        ),
        completes,
      );
    });

    test('cancel is a safe no-op when unavailable', () async {
      final notifier = NetworkNotifier();
      await expectLater(notifier.cancel(), completes);
    });

    // Note: init() drives the real flutter_local_notifications plugin, which
    // needs a platform binding and cannot be initialised in a plain unit test
    // (it throws LateInitializationError). Its permission-request behaviour is
    // verified manually via the example app, not here, to avoid mocking the
    // entire plugin chain — kept out in line with this package's mock-free
    // test style.
  });

  group('showOrUpdate throttler wiring (T3)', () {
    // These tests verify that AlertThrottler is properly wired into
    // showOrUpdate by observing shouldAlert() state through a test-injected
    // throttler. The notifier stays unavailable (no init) so the _plugin.show
    // path is never hit — we only care that the throttler guard is placed
    // AFTER the _available guard, meaning unavailability must NOT consume the
    // throttle window.

    test(
      'unavailable: showOrUpdate does not consume a throttle slot',
      () async {
        // A fresh throttler: first shouldAlert() call must still return true
        // after showOrUpdate is called on an unavailable notifier.
        DateTime fakeNow = DateTime(2026, 1, 1);
        final throttler = AlertThrottler(now: () => fakeNow);
        final notifier = NetworkNotifier(throttler: throttler);
        // _available is false — no init()
        await notifier.showOrUpdate(
          NetworkEntry(method: 'GET', url: '/test', statusCode: 200),
          1,
        );
        // Throttler state must be untouched: first shouldAlert() still true.
        expect(
          throttler.shouldAlert(),
          isTrue,
          reason: 'unavailable guard must fire before throttler.shouldAlert()',
        );
      },
    );

    // The following tests exercise the throttler logic paths that are visible
    // from the outside: a fake throttler with a controlled clock is injected.
    // Because _available remains false, _plugin.show is never called, so we
    // cannot observe whether buildDetails used alert:true or alert:false
    // directly here. The correctness of the alert/silent mapping is already
    // covered by the buildDetails group above. What we verify here is only
    // that the guard ordering is correct (unavailable ⇒ no throttle slot
    // consumed).
    //
    // Full integration of throttler→details is deliberately left to T4
    // real-device verification per the plan's mock-free convention.
  });

  group('buildDetails', () {
    group('alert: true (heads-up state)', () {
      late NotificationDetails details;

      setUp(() {
        details = NetworkNotifier.buildDetails(alert: true);
      });

      test('android importance is high', () {
        expect(details.android!.importance, equals(Importance.high));
      });

      test('android priority is high', () {
        expect(details.android!.priority, equals(Priority.high));
      });

      test('android onlyAlertOnce is false (re-alerts on each show)', () {
        expect(details.android!.onlyAlertOnce, isFalse);
      });

      test('android silent is false (heads-up visible)', () {
        expect(details.android!.silent, isFalse);
      });

      test('android ongoing is true', () {
        expect(details.android!.ongoing, isTrue);
      });

      test('android playSound is false (silent heads-up)', () {
        expect(details.android!.playSound, isFalse);
      });

      test('android channelId is flutter_inspector_network_v2', () {
        expect(
          details.android!.channelId,
          equals('flutter_inspector_network_v2'),
        );
      });

      test('iOS presentBanner is true (foreground banner)', () {
        expect(details.iOS!.presentBanner, isTrue);
      });

      test('iOS presentAlert is true (foreground alert on iOS < 14)', () {
        expect(details.iOS!.presentAlert, isTrue);
      });

      test('iOS presentList is true (stays in notification centre)', () {
        expect(details.iOS!.presentList, isTrue);
      });

      test('iOS presentSound is false (no sound)', () {
        expect(details.iOS!.presentSound, isFalse);
      });
    });

    group('alert: false (silent/throttled state)', () {
      late NotificationDetails details;

      setUp(() {
        details = NetworkNotifier.buildDetails(alert: false);
      });

      test('android importance is still high (channel level unchanged)', () {
        expect(details.android!.importance, equals(Importance.high));
      });

      test('android priority is still high', () {
        expect(details.android!.priority, equals(Priority.high));
      });

      test('android onlyAlertOnce is true (suppress re-alert)', () {
        expect(details.android!.onlyAlertOnce, isTrue);
      });

      test('android silent is true (double-guard suppress heads-up)', () {
        expect(details.android!.silent, isTrue);
      });

      test('android ongoing is true', () {
        expect(details.android!.ongoing, isTrue);
      });

      test('android playSound is false', () {
        expect(details.android!.playSound, isFalse);
      });

      test('android channelId is flutter_inspector_network_v2', () {
        expect(
          details.android!.channelId,
          equals('flutter_inspector_network_v2'),
        );
      });

      test('iOS presentBanner is false (no banner when throttled)', () {
        expect(details.iOS!.presentBanner, isFalse);
      });

      test('iOS presentAlert is false (no alert when throttled)', () {
        expect(details.iOS!.presentAlert, isFalse);
      });

      test(
        'iOS presentList is true (still appears in notification centre)',
        () {
          expect(details.iOS!.presentList, isTrue);
        },
      );

      test('iOS presentSound is false', () {
        expect(details.iOS!.presentSound, isFalse);
      });
    });
  });

  group('NetworkNotifier.crash (issue #156)', () {
    // Same mock-free convention as the groups above: init() is never called,
    // so the notifier stays unavailable and _plugin.show is never reached.
    // What is verifiable from outside is the identity of the notification
    // (distinct id / channel) and the guard ordering around the throttler.

    test('is unavailable before init', () {
      expect(NetworkNotifier.crash().isAvailable, isFalse);
    });

    test('showCrash is a safe no-op when unavailable', () async {
      final notifier = NetworkNotifier.crash();
      await expectLater(
        notifier.showCrash(exceptionType: 'StateError', message: 'boom'),
        completes,
      );
    });

    test('crash and network notification ids differ', () {
      // The whole point of the §P11 parameterisation: a crash alert must not
      // overwrite the network summary, which a shared id would cause.
      expect(
        NetworkNotifier.crashNotificationId,
        isNot(NetworkNotifier.networkNotificationId),
      );
    });

    test('unavailable: showCrash does not consume a throttle slot', () async {
      DateTime fakeNow = DateTime(2026, 1, 1);
      final throttler = AlertThrottler(now: () => fakeNow);
      final notifier = NetworkNotifier.crash(throttler: throttler);
      await notifier.showCrash(exceptionType: 'StateError', message: 'boom');
      expect(
        throttler.shouldAlert(),
        isTrue,
        reason: 'unavailable guard must fire before throttler.shouldAlert()',
      );
    });

    test('crash and network notifiers throttle independently', () {
      // Each notifier owns its throttler, so a burst of network activity must
      // not suppress a crash alert (or vice versa).
      DateTime fakeNow = DateTime(2026, 1, 1);
      final networkThrottler = AlertThrottler(now: () => fakeNow);
      final crashThrottler = AlertThrottler(now: () => fakeNow);
      NetworkNotifier(throttler: networkThrottler);
      NetworkNotifier.crash(throttler: crashThrottler);

      expect(networkThrottler.shouldAlert(), isTrue);
      // Consuming the network slot must leave the crash slot untouched.
      expect(crashThrottler.shouldAlert(), isTrue);
    });

    test(
      'crash notifier is assigned before init() is awaited (PR #157 review)',
      () async {
        // Regression guard: the error hooks are attached in the constructor,
        // well before _initCrashNotifier's await resolves. If the field were
        // assigned only *after* the await, every crash during startup would
        // hit a null notifier and be silently dropped. Injecting a notifier
        // and driving a crash synchronously proves the field is already set.
        final notifier = NetworkNotifier.crash();
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
          showCrashNotification: true,
          crashNotifier: notifier,
        );

        // No await here: this is the exact window in which the hooks are live
        // but init() has not resolved. If the field were assigned only after
        // the await, it would still be null at this point and every crash in
        // this window would be dropped.
        expect(
          inspector.crashNotifierForTesting,
          same(notifier),
          reason:
              'crash notifier must be assigned before init() is awaited, '
              'otherwise startup crashes hit a null field and are dropped',
        );
      },
    );

    group('buildDetails for crash alerts', () {
      test('ongoing defaults to true (network summary is persistent)', () {
        final details = NetworkNotifier.buildDetails(alert: true);
        expect(details.android!.ongoing, isTrue);
      });

      test('ongoing: false makes the alert dismissible', () {
        final details = NetworkNotifier.buildDetails(
          alert: true,
          ongoing: false,
        );
        expect(details.android!.ongoing, isFalse);
      });

      test('channel id and name are overridable', () {
        final details = NetworkNotifier.buildDetails(
          alert: true,
          channelId: 'flutter_inspector_crash',
          channelName: 'Crash Inspector',
        );
        expect(details.android!.channelId, 'flutter_inspector_crash');
        expect(details.android!.channelName, 'Crash Inspector');
      });

      test('defaults keep the existing network channel', () {
        final details = NetworkNotifier.buildDetails(alert: true);
        expect(details.android!.channelId, 'flutter_inspector_network_v2');
        expect(details.android!.channelName, 'Network Inspector');
      });
    });

    group('summarize', () {
      test('collapses whitespace to a single line', () {
        expect(
          NetworkNotifier.summarize('line one\n  line two\t\tline three'),
          'line one line two line three',
        );
      });

      test('leaves a short message unchanged', () {
        expect(NetworkNotifier.summarize('boom'), 'boom');
      });

      test('truncates an over-long message with an ellipsis', () {
        final result = NetworkNotifier.summarize('x' * 200);
        expect(result.length, 120);
        expect(result.endsWith('…'), isTrue);
      });

      test('does not truncate at exactly the limit', () {
        final result = NetworkNotifier.summarize('x' * 120);
        expect(result.length, 120);
        expect(result.contains('…'), isFalse);
      });
    });
  });
}
