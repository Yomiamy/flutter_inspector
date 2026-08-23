import 'package:flutter/foundation.dart';

import '../models/database_entry.dart';
import '../models/log_entry.dart';
import '../models/log_level.dart';
import '../models/navigator_entry.dart';
import '../models/network_entry.dart';
import '../models/timestamped_entry.dart';

/// Chip labels for the [LogLevel]s that get their own Console tab chip.
///
/// [LogLevel.error] is deliberately absent: the `Errors only` shortcut already
/// covers it, and an `Error` chip beside it read as the same filter while
/// behaving differently (the chip lets every non-log entry through, the
/// shortcut keeps only failures). Two chips for one intent is the confusion,
/// so the narrower one is gone. Warning keeps a chip because the shortcut's
/// warning coverage comes bundled with errors and failed calls, which is not
/// the same as looking at warnings alone.
///
/// The Console tab renders one chip per entry here, so this map — not
/// [LogLevel.values] — decides which levels are selectable.
const Map<LogLevel, String> logLevelLabels = {
  LogLevel.verbose: 'Verbose',
  LogLevel.debug: 'Debug',
  LogLevel.info: 'Info',
  LogLevel.warning: 'Warning',
};

/// An immutable filter for the Console tab's merged timeline: a
/// case-insensitive [keyword] plus either a [levels] constraint or the
/// [errorsOnly] shortcut.
///
/// Mirrors `NetworkFilter`, with one structural difference: the console renders
/// a four-source stream of [TimestampedEntry], so every predicate dispatches on
/// the runtime type rather than reading fields off a single model.
///
/// **Source filtering is deliberately absent.** It is already applied upstream
/// by `FlutterInspector.mergedTimeline(sources:)`; re-implementing it here
/// would create a second copy of the same decision.
@immutable
class ConsoleFilter {
  /// Creates a filter. A blank [keyword], empty [levels] and `errorsOnly:
  /// false` match everything.
  const ConsoleFilter({
    this.keyword = '',
    this.levels = const <LogLevel>{},
    this.errorsOnly = false,
  });

  /// Substring matched against each entry's readable fields
  /// (case-insensitive).
  final String keyword;

  /// Log levels to include. Empty means "all levels".
  ///
  /// Ignored while [errorsOnly] is set — the shortcut supersedes it.
  final Set<LogLevel> levels;

  /// Whether to keep only failures: `warning`/`error` logs and failed network
  /// calls. Supersedes [levels] when set.
  final bool errorsOnly;

  /// Whether this filter would match every entry (no active constraints).
  bool get isEmpty => keyword.trim().isEmpty && levels.isEmpty && !errorsOnly;

  /// Returns whether [entry] satisfies all active constraints.
  ///
  /// Constraints combine with AND; the only OR lives inside [_matchesErrorsOnly].
  bool matches(TimestampedEntry entry) =>
      _matchesLevel(entry) && _matchesKeyword(entry);

  /// Applies the level constraint.
  ///
  /// Non-[LogEntry] types are always let through: only logs carry a
  /// [LogLevel], so constraining them by level would silently turn this into a
  /// source filter and hide every network/navigation/database event the moment
  /// a level chip is picked.
  bool _matchesLevel(TimestampedEntry entry) {
    if (errorsOnly) return _matchesErrorsOnly(entry);
    if (levels.isEmpty) return true;
    if (entry is! LogEntry) return true;
    return levels.contains(entry.level);
  }

  /// The errors-only shortcut: warning/error logs **or** failed network calls.
  ///
  /// This is a union across two mutually exclusive types — an entry is never
  /// both a [LogEntry] and a [NetworkEntry], so combining them with AND would
  /// match nothing. Navigation and database entries carry no notion of
  /// failure, so they are dropped rather than let through.
  bool _matchesErrorsOnly(TimestampedEntry entry) => switch (entry) {
    final LogEntry e =>
      e.level == LogLevel.warning || e.level == LogLevel.error,
    // Reuses the single source of truth for "did this call fail" rather than
    // restating it here.
    final NetworkEntry e => e.isFailed,
    _ => false,
  };

  /// Applies the keyword constraint against each type's readable fields.
  bool _matchesKeyword(TimestampedEntry entry) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return true;

    return switch (entry) {
      final LogEntry e =>
        e.message.toLowerCase().contains(kw) ||
            (e.stackTrace?.toLowerCase().contains(kw) ?? false),
      final NetworkEntry e =>
        e.url.toLowerCase().contains(kw) ||
            e.method.toLowerCase().contains(kw) ||
            (e.statusCode?.toString().contains(kw) ?? false),
      final NavigatorEntry e =>
        (e.routeName?.toLowerCase().contains(kw) ?? false) ||
            e.displayName.toLowerCase().contains(kw),
      final DatabaseEntry e =>
        e.tableName.toLowerCase().contains(kw) ||
            e.operation.name.toLowerCase().contains(kw),
      _ => false,
    };
  }
}

/// Returns the subset of [entries] satisfying [filter], preserving order.
List<TimestampedEntry> applyConsoleFilter(
  List<TimestampedEntry> entries,
  ConsoleFilter filter,
) {
  if (filter.isEmpty) return entries;
  return entries.where(filter.matches).toList(growable: false);
}
