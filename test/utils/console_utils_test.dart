import 'package:flutter_inspector_kit/src/models/database_entry.dart';
import 'package:flutter_inspector_kit/src/models/database_operation.dart';
import 'package:flutter_inspector_kit/src/models/log_entry.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_inspector_kit/src/models/navigator_action.dart';
import 'package:flutter_inspector_kit/src/models/navigator_entry.dart';
import 'package:flutter_inspector_kit/src/models/network_entry.dart';
import 'package:flutter_inspector_kit/src/models/timestamped_entry.dart';
import 'package:flutter_inspector_kit/src/utils/console_utils.dart';
import 'package:flutter_test/flutter_test.dart';

class _Data {
  static final errorLog = LogEntry(
    message: 'cart checkout failed',
    level: LogLevel.error,
  );

  static final infoLog = LogEntry(
    message: 'cart opened',
    level: LogLevel.info,
  );

  static final warningLog = LogEntry(
    message: 'slow response',
    level: LogLevel.warning,
  );

  static final stackTraceLog = LogEntry(
    message: 'boom',
    level: LogLevel.debug,
    stackTrace: 'at CartPage.build',
  );

  /// A successful call whose url contains "cart" — the entry that must survive
  /// an `error` level chip combined with a `cart` keyword (AC-6a).
  static final successfulCartCall = NetworkEntry(
    url: 'https://api.example.com/api/cart',
    method: 'GET',
    statusCode: 200,
  );

  static final failedCall = NetworkEntry(
    url: 'https://api.example.com/orders',
    method: 'POST',
    statusCode: 500,
  );

  static final navEntry = NavigatorEntry(
    action: NavigatorAction.push,
    routeName: '/cart',
  );

  static final dbEntry = DatabaseEntry(
    operation: DatabaseOperation.insert,
    tableName: 'cart_items',
  );

  static List<TimestampedEntry> get all => [
    errorLog,
    infoLog,
    warningLog,
    stackTraceLog,
    successfulCartCall,
    failedCall,
    navEntry,
    dbEntry,
  ];
}

void main() {
  group('ConsoleFilter.isEmpty', () {
    test('a default filter matches everything', () {
      const filter = ConsoleFilter();
      final entries = _Data.all;
      expect(filter.isEmpty, isTrue);
      // Returns the very same list, not a copy: an empty filter short-circuits.
      expect(applyConsoleFilter(entries, filter), same(entries));
    });

    test('a blank keyword is treated as no constraint', () {
      const filter = ConsoleFilter(keyword: '   ');
      expect(filter.isEmpty, isTrue);
    });
  });

  group('keyword matching (AC-1 / AC-2)', () {
    test('matches log message and stackTrace', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(keyword: 'CartPage'),
      );
      expect(result, [_Data.stackTraceLog]);
    });

    test('matches network url, method and status code', () {
      expect(
        applyConsoleFilter(_Data.all, const ConsoleFilter(keyword: 'orders')),
        [_Data.failedCall],
      );
      expect(
        applyConsoleFilter(_Data.all, const ConsoleFilter(keyword: 'post')),
        [_Data.failedCall],
      );
      expect(
        applyConsoleFilter(_Data.all, const ConsoleFilter(keyword: '500')),
        [_Data.failedCall],
      );
    });

    test('matches navigator routeName and database tableName', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(keyword: 'cart'),
      );
      expect(result, contains(_Data.navEntry));
      expect(result, contains(_Data.dbEntry));
    });

    test('is case-insensitive', () {
      expect(
        applyConsoleFilter(_Data.all, const ConsoleFilter(keyword: 'CHECKOUT')),
        [_Data.errorLog],
      );
    });
  });

  group('level matching (AC-3 / AC-4)', () {
    test('an empty level set imposes no constraint', () {
      const filter = ConsoleFilter(keyword: 'cart');
      final result = applyConsoleFilter(_Data.all, filter);
      // Every "cart" match survives regardless of level: the error log, the
      // info log, the debug log (via its `at CartPage.build` stackTrace), the
      // successful call, the nav push and the db insert. Only `failedCall`
      // and `warningLog` miss the keyword.
      expect(result, hasLength(6));
      expect(result, isNot(contains(_Data.failedCall)));
      expect(result, isNot(contains(_Data.warningLog)));
    });

    test('level constrains logs only', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(levels: {LogLevel.error}),
      );
      expect(result, contains(_Data.errorLog));
      expect(result, isNot(contains(_Data.infoLog)));
    });

    test(
      'non-log entries survive a level filter — otherwise the level chips '
      'would silently degrade into a source filter (AC-4)',
      () {
        final result = applyConsoleFilter(
          _Data.all,
          const ConsoleFilter(levels: {LogLevel.error}),
        );
        expect(result, contains(_Data.successfulCartCall));
        expect(result, contains(_Data.failedCall));
        expect(result, contains(_Data.navEntry));
        expect(result, contains(_Data.dbEntry));
      },
    );

    test('multiple levels are OR-ed within the log type', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(levels: {LogLevel.error, LogLevel.warning}),
      );
      expect(result, contains(_Data.errorLog));
      expect(result, contains(_Data.warningLog));
      expect(result, isNot(contains(_Data.infoLog)));
    });
  });

  group('errorsOnly (AC-5 / AC-5a)', () {
    test('keeps warning/error logs and failed network calls', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(errorsOnly: true),
      );
      expect(result, contains(_Data.errorLog));
      expect(result, contains(_Data.warningLog));
      expect(result, contains(_Data.failedCall));
    });

    test('drops successful calls and non-error logs', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(errorsOnly: true),
      );
      expect(result, isNot(contains(_Data.successfulCartCall)));
      expect(result, isNot(contains(_Data.infoLog)));
    });

    test(
      'drops navigator and database entries, which carry no failure notion '
      '(AC-5a)',
      () {
        final result = applyConsoleFilter(
          _Data.all,
          const ConsoleFilter(errorsOnly: true),
        );
        expect(result, isNot(contains(_Data.navEntry)));
        expect(result, isNot(contains(_Data.dbEntry)));
      },
    );

    test('supersedes the level set rather than intersecting with it', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(errorsOnly: true, levels: {LogLevel.info}),
      );
      expect(result, contains(_Data.errorLog));
      expect(result, isNot(contains(_Data.infoLog)));
    });
  });

  group('orthogonal composition (AC-6a / AC-6e)', () {
    test(
      'level + keyword: a successful /api/cart call survives an error chip, '
      'because level never applies to network entries (AC-6a)',
      () {
        final result = applyConsoleFilter(
          _Data.all,
          const ConsoleFilter(keyword: 'cart', levels: {LogLevel.error}),
        );

        expect(result, contains(_Data.successfulCartCall));
        expect(result, contains(_Data.errorLog));
        // The info log matches "cart" but fails the level constraint.
        expect(result, isNot(contains(_Data.infoLog)));
        // The failed call does not match the keyword at all.
        expect(result, isNot(contains(_Data.failedCall)));
      },
    );

    test(
      'errorsOnly + keyword: the keyword applies after the union, not to one '
      'branch of it (AC-6e)',
      () {
        final result = applyConsoleFilter(
          _Data.all,
          const ConsoleFilter(keyword: 'cart', errorsOnly: true),
        );

        // Matches the union (error log) and the keyword.
        expect(result, contains(_Data.errorLog));
        // In the union but fails the keyword.
        expect(result, isNot(contains(_Data.failedCall)));
        // Matches the keyword but is not in the union.
        expect(result, isNot(contains(_Data.successfulCartCall)));
        expect(result, isNot(contains(_Data.navEntry)));
      },
    );

    test('a filter matching nothing yields an empty list', () {
      final result = applyConsoleFilter(
        _Data.all,
        const ConsoleFilter(keyword: 'no-such-entry'),
      );
      expect(result, isEmpty);
    });
  });
}
