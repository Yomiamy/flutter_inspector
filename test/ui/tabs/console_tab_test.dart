import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/src/core/flutter_inspector.dart';
import 'package:flutter_inspector_kit/src/extensions/log_level_color_extension.dart';
import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console/log_detail_view.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console_tab.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/network/network_detail_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsoleTab', () {
    // ---- Preserved log-only tests (still valid under default All filter) ----

    testWidgets('displays logs and supports clearing', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('Test message 1', level: LogLevel.info);
      inspector.log('Test message 2', level: LogLevel.error);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Test message 1'), findsOneWidget);
      expect(find.text('Test message 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('Test message 1'), findsNothing);
      expect(find.text('Test message 2'), findsNothing);
    });

    testWidgets(
      'clearing wipes all four merged-timeline sources, not just logs',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.log('log msg', level: LogLevel.info);
        inspector.registry.navigator.add(
          NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
        );
        inspector.logNetwork(
          NetworkEntry(
            method: 'GET',
            url: 'https://api.test/x',
            statusCode: 200,
            isComplete: true,
          ),
        );
        inspector.registry.database.add(
          DatabaseEntry(
            operation: DatabaseOperation.insert,
            tableName: 'users',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConsoleTab(inspector: inspector)),
          ),
        );

        expect(find.text('log msg'), findsOneWidget);
        expect(find.textContaining('/home'), findsOneWidget);
        expect(find.textContaining('https://api.test/x'), findsOneWidget);
        expect(find.textContaining('users'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.delete));
        await tester.pump();

        expect(find.text('log msg'), findsNothing);
        expect(find.textContaining('/home'), findsNothing);
        expect(find.textContaining('https://api.test/x'), findsNothing);
        expect(find.textContaining('users'), findsNothing);
      },
    );

    testWidgets('tapping error log with stackTrace opens LogDetailView', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log(
        'Error occurred',
        level: LogLevel.error,
        stackTrace: 'line 1\nline 2\nline 3',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Error occurred'), findsOneWidget);
      expect(find.byType(LogDetailView), findsNothing);

      await tester.tap(find.text('Error occurred'));
      await tester.pumpAndSettle();

      expect(find.byType(LogDetailView), findsOneWidget);
    });

    testWidgets('tapping error log with data opens LogDetailView', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log(
        'Error with data',
        level: LogLevel.error,
        data: {'key': 'value'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('Error with data'), findsOneWidget);
      expect(find.byType(LogDetailView), findsNothing);

      await tester.tap(find.text('Error with data'));
      await tester.pumpAndSettle();

      expect(find.byType(LogDetailView), findsOneWidget);
    });

    testWidgets('shows a chevron only on expandable rows', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      // Expandable: has a stackTrace.
      inspector.log('Expandable', level: LogLevel.error, stackTrace: 'x');
      // Non-expandable: plain info with neither stackTrace nor data.
      inspector.log('Flat', level: LogLevel.info);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Exactly one chevron, and it belongs to the expandable row's tile.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      final expandableTile = find.ancestor(
        of: find.text('Expandable'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: expandableTile,
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping pure info log without stackTrace or data does not navigate',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.log('Pure info', level: LogLevel.info);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConsoleTab(inspector: inspector)),
          ),
        );

        expect(find.text('Pure info'), findsOneWidget);
        expect(find.byType(LogDetailView), findsNothing);

        // Try to tap the log entry.
        final tile = find.byType(ListTile).first;
        await tester.tap(tile);
        await tester.pumpAndSettle();

        // LogDetailView should not appear because onTap is null.
        expect(find.byType(LogDetailView), findsNothing);
      },
    );

    // ---- New merged-timeline tests ----

    testWidgets('filter chip Network shows only network rows', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('a log', level: LogLevel.info);
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Default All filter: both visible.
      expect(find.text('a log'), findsOneWidget);
      expect(find.textContaining('https://api.test/x'), findsOneWidget);

      // Switch to Network filter.
      await tester.tap(find.widgetWithText(FilterChip, 'Network'));
      await tester.pump();

      expect(find.text('a log'), findsNothing);
      expect(find.textContaining('https://api.test/x'), findsOneWidget);
    });

    testWidgets('All filter shows mixed sources sorted newest-first', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      final tLog = DateTime(2026, 6, 26, 10, 0, 0); // oldest
      final tNav = DateTime(2026, 6, 26, 10, 0, 1);
      final tNet = DateTime(2026, 6, 26, 10, 0, 2);
      final tDb = DateTime(2026, 6, 26, 10, 0, 3); // newest

      inspector.registry.log.add(LogEntry(message: 'log msg', timestamp: tLog));
      inspector.registry.navigator.add(
        NavigatorEntry(
          action: NavigatorAction.push,
          routeName: '/home',
          timestamp: tNav,
        ),
      );
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
          timestamp: tNet,
        ),
      );
      inspector.registry.database.add(
        DatabaseEntry(
          operation: DatabaseOperation.insert,
          tableName: 'users',
          timestamp: tDb,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // All four sources present.
      expect(find.text('log msg'), findsOneWidget);
      expect(find.textContaining('/home'), findsOneWidget);
      expect(find.textContaining('https://api.test/x'), findsOneWidget);
      expect(find.textContaining('users'), findsOneWidget);

      // Newest-first: db row above network above nav above log.
      final dbY = tester.getTopLeft(find.textContaining('users')).dy;
      final netY = tester
          .getTopLeft(find.textContaining('https://api.test/x'))
          .dy;
      final navY = tester.getTopLeft(find.textContaining('/home')).dy;
      final logY = tester.getTopLeft(find.text('log msg')).dy;

      expect(dbY, lessThan(netY));
      expect(netY, lessThan(navY));
      expect(navY, lessThan(logY));
    });

    testWidgets('network row taps into NetworkDetailView', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.byType(NetworkDetailView), findsNothing);

      await tester.tap(find.textContaining('https://api.test/x'));
      await tester.pumpAndSettle();

      expect(find.byType(NetworkDetailView), findsOneWidget);
    });

    testWidgets('network row tap forwards redactSensitiveData', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
        redactSensitiveData: false,
      );
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/x',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      await tester.tap(find.textContaining('https://api.test/x'));
      await tester.pumpAndSettle();

      final view = tester.widget<NetworkDetailView>(
        find.byType(NetworkDetailView),
      );
      expect(view.redactSensitiveData, isFalse);
    });

    testWidgets('tints only error logs and failed network rows', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('boom', level: LogLevel.error);
      inspector.log('heads up', level: LogLevel.warning);
      inspector.log('all good', level: LogLevel.info);
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/fail',
          statusCode: 500,
          isComplete: true,
        ),
      );
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/ok',
          statusCode: 200,
          isComplete: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      Color? tileColorOf(Finder text) => tester
          .widget<ListTile>(
            find.ancestor(of: text, matching: find.byType(ListTile)),
          )
          .tileColor;

      expect(tileColorOf(find.text('boom')), isNotNull);
      expect(tileColorOf(find.text('all good')), isNull);
      expect(
        tileColorOf(find.textContaining('https://api.test/fail')),
        isNotNull,
      );
      expect(tileColorOf(find.textContaining('https://api.test/ok')), isNull);

      // Warnings stay text-only: an orange label but no tint, so a
      // warning-heavy timeline does not wash out and hide the errors.
      expect(tileColorOf(find.text('heads up')), isNull);
      expect(
        tester.widget<Text>(find.text('heads up')).style?.color,
        LogLevel.warning.color,
      );
    });

    testWidgets('nav and db rows are not tappable (no chevron)', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.navigator.add(
        NavigatorEntry(action: NavigatorAction.push, routeName: '/home'),
      );
      inspector.registry.database.add(
        DatabaseEntry(operation: DatabaseOperation.insert, tableName: 'users'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      // Neither nav nor db row shows a chevron.
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      // Tapping the nav row navigates nowhere.
      await tester.tap(find.textContaining('/home'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkDetailView), findsNothing);
      expect(find.byType(LogDetailView), findsNothing);

      // Tapping the db row navigates nowhere.
      await tester.tap(find.textContaining('users'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkDetailView), findsNothing);
      expect(find.byType(LogDetailView), findsNothing);
    });

    testWidgets('each row shows displayTime (HH:mm:ss.mmm)', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.registry.log.add(
        LogEntry(
          message: 'tm',
          timestamp: DateTime(2026, 6, 26, 14, 30, 1, 123),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      expect(find.text('14:30:01.123'), findsOneWidget);
    });
  });

  group('ConsoleTab search and level filters', () {
    Future<void> pumpTab(WidgetTester tester, FlutterInspector inspector) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConsoleTab(inspector: inspector)),
          ),
        );

    /// The chip row scrolls horizontally and is wider than the 800px test
    /// viewport, so the level chips sit off-screen until scrolled to — same as
    /// a user dragging the row.
    Future<void> tapChip(WidgetTester tester, String label) async {
      await tester.scrollUntilVisible(
        find.widgetWithText(FilterChip, label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, label));
      await tester.pumpAndSettle();
    }

    testWidgets('the keyword narrows the timeline across sources', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('cart opened', level: LogLevel.info);
      inspector.log('unrelated noise', level: LogLevel.info);

      await pumpTab(tester, inspector);
      expect(find.text('unrelated noise'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'cart');
      await tester.pumpAndSettle();

      expect(find.text('cart opened'), findsOneWidget);
      expect(find.text('unrelated noise'), findsNothing);
    });

    testWidgets('a filter matching nothing shows No matches', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('only entry', level: LogLevel.info);

      await pumpTab(tester, inspector);
      await tester.enterText(find.byType(TextField), 'zzz-no-such-entry');
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets(
      'a level chip keeps network rows visible, so it never degrades into a '
      'source filter',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.log('an info log', level: LogLevel.info);
        inspector.logNetwork(
          NetworkEntry(
            method: 'GET',
            url: 'https://api.test/cart',
            statusCode: 200,
            isComplete: true,
          ),
        );

        await pumpTab(tester, inspector);
        await tapChip(tester, 'Warning');

        // The info log fails the level constraint...
        expect(find.text('an info log'), findsNothing);
        // ...but the successful call is not a log, so level never applied.
        expect(find.textContaining('https://api.test/cart'), findsOneWidget);
      },
    );

    testWidgets('errors only drops successful calls and healthy logs', (
      tester,
    ) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('an info log', level: LogLevel.info);
      inspector.log('a broken thing', level: LogLevel.error);
      inspector.logNetwork(
        NetworkEntry(
          method: 'GET',
          url: 'https://api.test/ok',
          statusCode: 200,
          isComplete: true,
        ),
      );
      inspector.logNetwork(
        NetworkEntry(
          method: 'POST',
          url: 'https://api.test/broken',
          statusCode: 500,
          isComplete: true,
        ),
      );

      await pumpTab(tester, inspector);
      await tapChip(tester, '⚡ Errors only');

      expect(find.text('a broken thing'), findsOneWidget);
      expect(find.textContaining('https://api.test/broken'), findsOneWidget);
      expect(find.text('an info log'), findsNothing);
      expect(find.textContaining('https://api.test/ok'), findsNothing);
    });

    testWidgets(
      'there is no Error level chip, so Errors only is the single entry point '
      'for looking at failures',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.log('a broken thing', level: LogLevel.error);

        await pumpTab(tester, inspector);

        // The neighbouring level chips are still there...
        expect(find.widgetWithText(FilterChip, 'Warning'), findsOneWidget);
        expect(find.widgetWithText(FilterChip, 'Info'), findsOneWidget);
        // ...but the one that used to sit beside the shortcut and read as the
        // same filter is gone.
        expect(find.widgetWithText(FilterChip, 'Error'), findsNothing);
        expect(
          find.widgetWithText(FilterChip, '\u26a1 Errors only'),
          findsOneWidget,
        );
      },
    );
  });

  group('ConsoleTab jump back to the full timeline', () {
    testWidgets('tapping a filtered row clears every filter', (tester) async {
      final inspector = FlutterInspector(
        navigatorKey: GlobalKey<NavigatorState>(),
      );
      inspector.log('cart opened', level: LogLevel.info);
      inspector.log('unrelated noise', level: LogLevel.info);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConsoleTab(inspector: inspector)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'cart');
      await tester.pumpAndSettle();
      expect(find.text('unrelated noise'), findsNothing);

      await tester.tap(find.text('cart opened'));
      await tester.pumpAndSettle();

      // Filters are gone, so the surrounding context is back on screen.
      expect(find.text('unrelated noise'), findsOneWidget);
      expect(find.text('cart opened'), findsOneWidget);
    });

    testWidgets(
      'tapping a filtered row also clears the search field text, not just '
      'the filter state',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.log('cart opened', level: LogLevel.info);
        inspector.log('unrelated noise', level: LogLevel.info);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConsoleTab(inspector: inspector)),
          ),
        );

        await tester.enterText(find.byType(TextField), 'cart');
        await tester.pumpAndSettle();

        await tester.tap(find.text('cart opened'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, isEmpty);
      },
    );

    testWidgets(
      'long-press still bookmarks while a filter is active, since taking over '
      'the tap must not take over every gesture',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.log('cart opened', level: LogLevel.info);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConsoleTab(inspector: inspector)),
          ),
        );

        await tester.enterText(find.byType(TextField), 'cart');
        await tester.pumpAndSettle();
        expect(inspector.bookmarkedEntries, isEmpty);

        await tester.longPress(find.text('cart opened'));
        await tester.pumpAndSettle();

        expect(inspector.bookmarkedEntries, hasLength(1));
      },
    );

    testWidgets(
      'tapping an unfiltered row still opens the detail view rather than '
      'jumping',
      (tester) async {
        final inspector = FlutterInspector(
          navigatorKey: GlobalKey<NavigatorState>(),
        );
        inspector.logNetwork(
          NetworkEntry(
            method: 'GET',
            url: 'https://api.test/x',
            statusCode: 200,
            isComplete: true,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ConsoleTab(inspector: inspector)),
          ),
        );

        await tester.tap(find.textContaining('https://api.test/x'));
        await tester.pumpAndSettle();

        expect(find.byType(NetworkDetailView), findsOneWidget);
      },
    );
  });
}
