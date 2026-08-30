import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/ui/dashboard/tabs/console/log_detail_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime(2026, 6, 20, 10, 30, 0);

  LogEntry fullEntry() => LogEntry(
    message: 'Something went wrong',
    level: LogLevel.error,
    stackTrace: '#0  main (file:///lib/main.dart:10:5)\n#1  runApp',
    data: {'exceptionType': 'StateError', 'source': 'zone'},
    timestamp: t,
  );

  LogEntry minimalEntry() =>
      LogEntry(message: 'Just a message', level: LogLevel.info, timestamp: t);

  group('LogDetailView', () {
    testWidgets('renders message, level, timestamp, stackTrace and data', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: LogDetailView(entry: fullEntry())),
      );

      // AppBar title contains level and timestamp
      expect(find.textContaining('[error]'), findsOneWidget);

      // General section
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Something went wrong'), findsWidgets);

      // Stack Trace section with SelectableText
      expect(find.text('Stack Trace'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);

      // Data section — KeyValueTable renders the entries
      expect(find.text('Data'), findsOneWidget);
      expect(find.textContaining('exceptionType'), findsOneWidget);
    });

    testWidgets('null stackTrace and null data do not crash', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LogDetailView(entry: minimalEntry())),
      );

      // Should render without throwing
      expect(find.text('General'), findsOneWidget);

      // Stack Trace section must NOT appear when stackTrace is null
      expect(find.text('Stack Trace'), findsNothing);

      // Data section shows emptyLabel when data is null
      expect(find.text('Data'), findsOneWidget);
      // KeyValueTable emptyLabel — '(no data)'
      expect(find.text('(no data)'), findsOneWidget);
    });

    testWidgets('Copy concise writes buildLogPlainText to clipboard', (
      tester,
    ) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(home: LogDetailView(entry: fullEntry())),
      );

      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy concise'));
      await tester.pumpAndSettle();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('=== General ==='));
      expect(clipboardText, contains('Something went wrong'));
      expect(clipboardText, contains('=== Stack Trace ==='));
      expect(clipboardText, contains('=== Data ==='));
    });

    testWidgets('share menu contains Copy concise and Share items', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: LogDetailView(entry: fullEntry())),
      );

      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();

      expect(find.text('Copy concise'), findsOneWidget);
      expect(find.text('Share concise…'), findsOneWidget);
      // No cURL option
      expect(find.text('Copy as cURL'), findsNothing);
    });
  });
}
