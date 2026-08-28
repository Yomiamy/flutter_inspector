import 'package:flutter/foundation.dart';

import 'log_level.dart';
import 'timestamped_entry.dart';

/// An immutable record of a single console log, displayed in the Console tab.
@immutable
class LogEntry implements TimestampedEntry {
  /// Creates a log entry. [timestamp] defaults to the moment of creation.
  LogEntry({
    required this.message,
    this.level = LogLevel.info,
    this.stackTrace,
    this.data,
    this.activeRoute,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// When the log was recorded.
  @override
  final DateTime timestamp;

  /// Severity of the log.
  final LogLevel level;

  /// The log message body.
  final String message;

  /// Optional stack trace captured alongside the message.
  final String? stackTrace;

  /// Optional structured payload attached to the log.
  final Map<String, dynamic>? data;

  /// The active route at the time the log was recorded.
  final String? activeRoute;

  /// Returns a copy of this entry with the given fields replaced.
  LogEntry copyWith({
    DateTime? timestamp,
    LogLevel? level,
    String? message,
    String? stackTrace,
    Map<String, dynamic>? data,
    String? activeRoute,
  }) {
    return LogEntry(
      timestamp: timestamp ?? this.timestamp,
      level: level ?? this.level,
      message: message ?? this.message,
      stackTrace: stackTrace ?? this.stackTrace,
      data: data ?? this.data,
      activeRoute: activeRoute ?? this.activeRoute,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LogEntry &&
        other.timestamp == timestamp &&
        other.level == level &&
        other.message == message &&
        other.stackTrace == stackTrace &&
        other.activeRoute == activeRoute &&
        mapEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(timestamp, level, message, stackTrace, data, activeRoute);

  @override
  String toString() => 'LogEntry(${level.name}, $message, $timestamp, activeRoute: $activeRoute)';
}
