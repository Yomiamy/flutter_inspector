import 'package:flutter_test/flutter_test.dart';
// Import through the package entry point only, exactly as the README tells
// consumers to. This fails to compile if a documented helper or the types it
// takes stop being exported.
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

class _Data {
  static const String rawStackTrace =
      '#0      main (package:my_app/main.dart:10:3)\n'
      '#1      _rootRun (dart:async/zone.dart:1399:47)\n'
      '#2      _CustomZone.run (dart:async/zone.dart:1301:19)\n'
      '#3      _runZoned (dart:async/zone.dart:1841:10)\n'
      '#4      runZoned (dart:async/zone.dart:1788:10)\n'
      '#5      handle (package:flutter/src/widgets/binding.dart:20:5)';
}

void main() {
  test('README helper example compiles against the public entry point', () {
    final concise = normalizeStackTrace(_Data.rawStackTrace);
    expect(concise, contains('frames of framework internals'));

    final entry = LogEntry(
      level: LogLevel.error,
      message: 'boom',
      stackTrace: _Data.rawStackTrace,
    );

    final text = buildLogPlainText(entry);
    final verbatim = buildLogPlainText(entry, isConcise: false);

    expect(text, contains('frames of framework internals'));
    expect(verbatim, contains('dart:async/zone.dart:1301:19'));
  });
}
