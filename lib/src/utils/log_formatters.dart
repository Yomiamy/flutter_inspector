import '../models/log_entry.dart';
import '../models/timestamped_entry.dart';

/// Pure formatting helpers for the Console inspector. No Flutter dependencies,
/// so everything here is unit-testable in isolation.

/// Projects [entry] onto a single dense line for the diagnostic report's
/// `## Timeline` section: `[HH:mm:ss.mmm] [LOG/{level}] {message}`.
///
/// The message is flattened onto one line: a log body can carry its own ```
/// fence (LLM output, a pasted snippet), and the timeline renders entries as
/// plain list items, not fenced blocks — keeping the fence off line-start is
/// what stops it opening a code block that swallows the rest of the report.
///
/// When a stack trace is present, up to its first three non-blank frames follow
/// on their own `  │ ` lines, enough to place the failure without dragging the
/// whole trace into an at-a-glance view.
String buildLogOneLiner(LogEntry entry) {
  // \r\n?|\n covers CRLF, lone \r and lone \n — CommonMark treats a lone
  // carriage return as a line ending too, so leaving it behind would let an
  // embedded ``` fence back onto line-start.
  final message = entry.message.replaceAll(RegExp(r'\r\n?|\n'), ' ');
  final activeRouteStr =
      entry.activeRoute != null ? ' (Active Route: ${entry.activeRoute})' : '';
  final b = StringBuffer(
    '[${entry.displayTime}] [LOG/${entry.level.name}] $message$activeRouteStr',
  );

  final stackTrace = entry.stackTrace;
  if (stackTrace != null) {
    // 找出最相關的 App Callstack (過濾掉 framework 與 async gap)
    final appFrames = stackTrace
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .where((l) =>
            !l.contains('package:flutter/') &&
            !l.contains('dart:') &&
            !l.contains('<asynchronous suspension>'));
            
    // 若全都是 framework (雖然機率極低)，則 fallback 拿前 3 行；否則拿前 3 行 App Frames
    final frames = (appFrames.isNotEmpty ? appFrames : stackTrace.split('\n').where((l) => l.trim().isNotEmpty)).take(3);

    for (final frame in frames) {
      b.write('\n  │ ${frame.trim()}');
    }
  }
  return b.toString();
}

/// Builds a full plain-text export of [entry] covering general info,
/// stack trace, and data sections.
String buildLogPlainText(LogEntry entry, {bool isConcise = true}) {
  final b = StringBuffer()
    ..writeln('=== General ===')
    ..writeln('Message: ${entry.message}')
    ..writeln('Level: ${entry.level.name}')
    ..writeln('Timestamp: ${entry.timestamp.toIso8601String()}');

  if (entry.activeRoute != null) {
    b.writeln('Active Route: ${entry.activeRoute}');
  }

  b.writeln('\n=== Stack Trace ===');
  final stackTrace = entry.stackTrace;
  if (stackTrace != null && stackTrace.isNotEmpty) {
    b.writeln(isConcise ? normalizeStackTrace(stackTrace) : stackTrace);
  } else {
    b.writeln('(none)');
  }

  b.writeln('\n=== Data ===');
  final data = entry.data;
  if (data != null && data.isNotEmpty) {
    data.forEach((k, v) => b.writeln('$k: $v'));
  } else {
    b.writeln('(none)');
  }

  return b.toString().trimRight();
}

/// Normalizes a stack trace string by collapsing consecutive framework-internal frames
/// and converting asynchronous suspension gaps into a readable format.
String normalizeStackTrace(String rawStack) {
  final lines = rawStack.split('\n');
  final result = <String>[];
  int collapsedCount = 0;

  void flushCollapsed() {
    if (collapsedCount > 0) {
      result.add('  [... $collapsedCount frames of framework internals]');
      collapsedCount = 0;
    }
  }

  for (final line in lines) {
    if (line.trim().isEmpty) continue;

    if (line.contains('<asynchronous suspension>')) {
      flushCollapsed();
      result.add('  <-- async gap -->');
    } else if (line.contains('package:flutter/') || line.contains('dart:')) {
      collapsedCount++;
    } else {
      flushCollapsed();
      result.add(line);
    }
  }
  flushCollapsed();
  return result.join('\n');
}
