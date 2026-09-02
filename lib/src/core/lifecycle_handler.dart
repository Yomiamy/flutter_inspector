import 'package:flutter/widgets.dart';

import '../models/log_level.dart';
import 'uncaught_error_handler.dart' show LogCallback;

/// Records app lifecycle transitions as [LogLevel.info] log entries, and
/// memory pressure warnings as [LogLevel.warning] entries.
///
/// Registers itself on [WidgetsBinding.instance] as an observer. Flutter keeps
/// observers in a list, so the host app's own observers keep receiving their
/// callbacks unaffected.
class LifecycleHandler with WidgetsBindingObserver {
  /// The function called to log a lifecycle transition.
  final LogCallback onLog;

  /// Optional supplier of a label for the current top-most page, appended to
  /// the log message so a background/foreground switch reads as the page it
  /// happened on (e.g. `App lifecycle: resumed · HomePage (/home)`).
  ///
  /// Returns `null` when the top page cannot be resolved (empty history, or a
  /// best-effort replay that came up empty); the message then omits the suffix
  /// rather than inventing one.
  final String? Function()? topPageLabel;

  bool _attached = false;

  /// Creates a new LifecycleHandler instance.
  LifecycleHandler({required this.onLog, this.topPageLabel});

  /// Registers this handler as a [WidgetsBindingObserver].
  ///
  /// Idempotent: the `_attached` flag ensures a single state change is never
  /// recorded twice by the same instance.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Removes this handler from [WidgetsBinding.instance].
  ///
  /// Safe to call when not attached, and safe to call twice.
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      final page = topPageLabel?.call();
      final suffix = (page == null || page.isEmpty) ? '' : ' · $page';
      onLog('App lifecycle: ${state.name}$suffix', level: LogLevel.info);
    } catch (e, s) {
      debugPrintStack(
        stackTrace: s,
        label: 'inspector lifecycle log failed: $e',
      );
    }
  }

  /// Records the OS-reported memory pressure as a [LogLevel.warning] entry.
  ///
  /// This is the only OOM/LMK precursor available to Dart — the actual RSS
  /// figure needs a platform channel — and it arrives as a discrete, timestamped
  /// event, so it lands on the merged timeline next to the network, route and
  /// database entries that preceded it. Warning rather than info: it is a
  /// precursor signal, not a state transition, so it has to surface through the
  /// existing error/warning filters instead of sinking into the info stream.
  ///
  /// Platform coverage: Android reports it via `onTrimMemory`, iOS via
  /// `didReceiveMemoryWarning`. Web effectively never fires it.
  @override
  void didHaveMemoryPressure() {
    try {
      final page = topPageLabel?.call();
      final suffix = (page == null || page.isEmpty) ? '' : ' · $page';
      onLog('Memory pressure$suffix', level: LogLevel.warning);
    } catch (e, s) {
      // The binding wraps each observer in its own try-catch here (unlike the
      // lifecycle broadcast), so this guard is not what keeps the host's
      // observers running — it keeps a throwing `topPageLabel` from surfacing
      // as a FlutterError the host never caused.
      debugPrintStack(
        stackTrace: s,
        label: 'inspector memory pressure log failed: $e',
      );
    }
  }
}
