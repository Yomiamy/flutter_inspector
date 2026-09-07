import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../inspectors/log_inspector.dart';
import '../inspectors/navigator_inspector.dart';
import '../inspectors/navigator_stack_resolver.dart';
import '../models/database_browser_source.dart';
import '../models/database_entry.dart';
import '../models/database_operation.dart';
import '../models/diagnostic_info.dart';
import '../models/key_value_browser_source.dart';
import '../models/log_entry.dart';
import '../sources/operation_log_source.dart';
import '../models/log_level.dart';
import '../models/navigator_entry.dart';
import '../models/network_entry.dart';
import '../models/timestamped_entry.dart';
import '../notifications/network_notifier.dart';
import '../observers/navigator_observer.dart';
import '../ui/dashboard/dashboard_modal.dart';
import 'inspector_overlay_manager.dart';
import 'inspector_registry.dart';
import 'lifecycle_handler.dart';
import 'uncaught_error_handler.dart';
import '../version.dart';

/// The core entry point for the Flutter Inspector.
class FlutterInspector {
  /// Package version.
  static const String version = packageVersion;

  /// Optional widget for a 5th tab in the dashboard.
  final Widget? customTab;

  /// The title of the custom tab.
  final String customTabTitle;

  /// How many consecutive taps trigger the dashboard via MagicalTap.
  final int magicalTapCount;

  /// Whether to surface a live system notification summarising network calls.
  /// Defaults to `false` so apps opt in explicitly (and avoid permission
  /// prompts they didn't ask for).
  final bool showNetworkNotification;

  /// Whether to surface a system notification when an uncaught error is
  /// captured. Defaults to `false` so apps opt in explicitly.
  ///
  /// **Requires [captureUncaughtErrors] (or a manual [setupErrorHandlers]
  /// call).** Without the error hooks attached there is nothing to notify
  /// about, so this flag alone has no effect — it is deliberately not made to
  /// enable capture on its own, since installing global error hooks is the
  /// host's decision.
  ///
  /// Alerts are throttled independently of [showNetworkNotification], and use
  /// their own notification id and channel, so a crash alert never replaces
  /// the network summary.
  final bool showCrashNotification;

  /// Navigator key used to route to the dashboard.
  ///
  /// This is **required**: [openDashboard] resolves its [BuildContext] from
  /// this key, so the dashboard cannot be opened without it — by a magical
  /// tap, by the floating button, or by a notification tap.
  ///
  /// The same key must also be passed to your [MaterialApp] (or [WidgetsApp]),
  /// otherwise it never gets a mounted context:
  ///
  /// ```dart
  /// final navigatorKey = GlobalKey<NavigatorState>();
  /// final inspector = FlutterInspector(navigatorKey: navigatorKey);
  ///
  /// MaterialApp(navigatorKey: navigatorKey, /* ... */);
  /// ```
  final GlobalKey<NavigatorState> navigatorKey;

  /// Whether to capture uncaught errors from the three standard Flutter hooks
  /// ([FlutterError.onError], [PlatformDispatcher.instance.onError],
  /// [ErrorWidget.builder]) and turn them into [LogLevel.error] log entries.
  ///
  /// Defaults to `false` so the package never touches host error handlers
  /// unless the host opts in. When `true`, all hooks chain/wrap the existing
  /// host handler — the error is always forwarded downstream, never swallowed.
  ///
  /// Notes:
  /// - The hooks capture whatever handler is installed at construction time.
  ///   If the host installs its own [FlutterError.onError] /
  ///   [PlatformDispatcher.instance.onError] *after* constructing the inspector,
  ///   that later handler replaces the inspector's wrapper and capture silently
  ///   stops (the host always wins — nothing breaks). Construct the inspector
  ///   after installing any custom handlers.
  /// - Enable this on a single, app-wide inspector. The dedup guard is
  ///   per-instance, so creating multiple capture-enabled inspectors layers the
  ///   hooks and records the same error once per instance (host errors still
  ///   forward correctly — just duplicated logs).
  /// - The error hooks are not torn down: once attached they remain for the
  ///   process lifetime ([detach] does not restore them). The `_old*` handlers
  ///   are kept solely to chain to, not to restore.
  final bool captureUncaughtErrors;

  /// Whether to record app lifecycle transitions (`resumed` / `inactive` /
  /// `paused` / `detached`, plus `hidden` on Flutter 3.13+) as [LogLevel.info]
  /// log entries, so a crash or a stalled request can be read against whether
  /// the app was in the foreground at that moment.
  ///
  /// Each entry names the current top-most page so repeated home/back switches
  /// stay distinguishable without cross-referencing the Navigator tab, e.g.
  /// `App lifecycle: resumed · HomePage (/home)`. The page is a best-effort
  /// replay of the navigation history; when it cannot be resolved the suffix is
  /// simply omitted.
  ///
  /// Defaults to `false` so the package registers no observer unless the host
  /// opts in.
  ///
  /// Notes:
  /// - When `true`, the inspector registers a [WidgetsBindingObserver] at
  ///   construction time, so the binding must already exist — construct the
  ///   inspector after `WidgetsFlutterBinding.ensureInitialized()` / `runApp`.
  ///   (Any real app satisfies this; it is the same precondition the host
  ///   already meets before calling `runApp`.)
  /// - Enable this on a single, app-wide inspector. Each enabled instance keeps
  ///   its own observer and its own buffer, so multiple instances each record
  ///   their own copy (correct per instance, just duplicated across them).
  /// - Unlike the error hooks, this observer *is* torn down: [detach] removes
  ///   it from [WidgetsBinding.instance]. Removing one observer from the
  ///   binding's list cannot affect the host's own observers.
  /// - This flag also covers **memory pressure**: the same observer records an
  ///   OS memory-pressure warning as a [LogLevel.warning] entry, the only
  ///   OOM/LMK precursor Dart can see. It shares this flag rather than getting
  ///   its own because both are callbacks on one observer with one attach/
  ///   detach lifecycle. Android delivers it via `onTrimMemory`, iOS via
  ///   `didReceiveMemoryWarning`; Web effectively never fires it.
  final bool captureLifecycleEvents;

  /// Whether to mask sensitive headers (e.g. `Authorization`, `Cookie`,
  /// `Set-Cookie`, `X-Api-Key`) in all share/export paths (cURL, plain text).
  ///
  /// Defaults to `true` so secrets never leak to the clipboard, a share sheet,
  /// or a screenshot unless the host explicitly opts out.
  final bool redactSensitiveData;

  /// Supplies device and app metadata for the diagnostic report header.
  ///
  /// Defaults to `null`, in which case the header degrades to `N/A`. This
  /// package depends on no device-info plugin (and never on `dart:io`); hosts
  /// that want a populated header implement [DiagnosticInfoSource] themselves.
  final DiagnosticInfoSource? diagnosticInfoSource;

  /// The duration threshold for considering a network request as "slow".
  /// Slow requests receive visual indicators in the dashboard.
  /// Defaults to 2 seconds.
  final Duration slowRequestThreshold;

  late final UncaughtErrorHandler _uncaughtErrorHandler;
  late final LifecycleHandler _lifecycleHandler;
  late final InspectorRegistry _registry;
  late final FlutterInspectorNavigatorObserver _navigatorObserver;
  late final OperationLogSource _operationLogSource;
  final List<DatabaseBrowserSource> _customDatabaseSources = [];
  final List<KeyValueBrowserSource> _keyValueSources = [];
  late final InspectorOverlayManager _overlayManager;
  final Set<TimestampedEntry> _bookmarkedEntries = <TimestampedEntry>{};

  /// Unmodifiable view of currently bookmarked entries.
  Set<TimestampedEntry> get bookmarkedEntries =>
      Set.unmodifiable(_bookmarkedEntries);

  /// Checks if an entry is bookmarked.
  bool isBookmarked(TimestampedEntry entry) =>
      _bookmarkedEntries.contains(entry);

  /// Toggles bookmark state for an entry.
  void toggleBookmark(TimestampedEntry entry) {
    if (_bookmarkedEntries.contains(entry)) {
      _bookmarkedEntries.remove(entry);
    } else {
      _bookmarkedEntries.add(entry);
    }
  }

  /// Clears all bookmarks.
  void clearBookmarks() => _bookmarkedEntries.clear();

  /// The observer to be added to MaterialApp's navigatorObservers.
  FlutterInspectorNavigatorObserver get navigatorObserver => _navigatorObserver;

  /// Exposed for internal testing.
  @visibleForTesting
  InspectorRegistry get registry => _registry;

  /// Retrieves the current console logs.
  List<LogEntry> get logEntries => _registry.log.entries;

  /// The log inspector, for level-filtered reads.
  ///
  /// [logEntries] covers the common case; the diagnostic report needs
  /// [LogInspector.entriesAtLevel] as well, and [registry] is test-only.
  LogInspector get logInspector => _registry.log;

  /// Retrieves the current network logs.
  List<NetworkEntry> get networkEntries => _registry.network.entries;

  /// The navigator inspector used by [navigatorObserver] to buffer events.
  NavigatorInspector get navigatorInspector => _registry.navigator;

  /// Retrieves the current navigator history.
  List<NavigatorEntry> get navigatorEntries => _registry.navigator.entries;

  /// Retrieves the current database logs.
  List<DatabaseEntry> get databaseEntries => _registry.database.entries;

  /// Retrieves the registered database browser sources.
  List<DatabaseBrowserSource> get databaseSources =>
      List.unmodifiable([_operationLogSource, ..._customDatabaseSources]);

  /// Retrieves the registered key-value browser sources.
  ///
  /// Empty unless the host app registers one — the package ships no built-in
  /// key-value source, so there is no default entry here.
  List<KeyValueBrowserSource> get keyValueSources =>
      List.unmodifiable(_keyValueSources);

  /// Creates a new FlutterInspector instance.
  ///
  /// This should typically be instantiated once at app startup and retained
  /// globally. It maintains its own internal buffers and state.
  ///
  /// [slowRequestThreshold] marks completed requests as slow when their
  /// duration is greater than or equal to this value. Defaults to 2 seconds.
  FlutterInspector({
    this.customTab,
    this.customTabTitle = 'Custom',
    this.magicalTapCount = 5,
    this.showNetworkNotification = false,
    this.showCrashNotification = false,
    required this.navigatorKey,
    this.captureUncaughtErrors = false,
    this.captureLifecycleEvents = false,
    this.redactSensitiveData = true,
    this.diagnosticInfoSource,
    this.slowRequestThreshold = const Duration(seconds: 2),
    int bufferSize = 500,
    NetworkNotifier? notifier,
    NetworkNotifier? crashNotifier,
    List<DatabaseBrowserSource>? databaseSources,
    List<KeyValueBrowserSource>? keyValueSources,
  }) {
    if (slowRequestThreshold.isNegative) {
      throw ArgumentError.value(
        slowRequestThreshold,
        'slowRequestThreshold',
        'must not be negative',
      );
    }
    _overlayManager = InspectorOverlayManager(onFabTap: (_) => openDashboard());
    _registry = InspectorRegistry(bufferSize: bufferSize);
    // Notifications hang off the error handler's own callback rather than
    // log(): only uncaught errors should alert, not a host's manual
    // log(level: error) call.
    _uncaughtErrorHandler = UncaughtErrorHandler(
      onLog: (message, {required level, stackTrace, data}) {
        log(message, level: level, stackTrace: stackTrace, data: data);
        if (showCrashNotification) _notifyCrash(message, data);
      },
    );
    if (captureUncaughtErrors) setupErrorHandlers();
    _lifecycleHandler = LifecycleHandler(
      onLog: log,
      topPageLabel: _currentTopPageLabel,
    );
    if (captureLifecycleEvents) _lifecycleHandler.attach();
    _navigatorObserver = FlutterInspectorNavigatorObserver(this);
    _operationLogSource = OperationLogSource(_registry.database);
    if (keyValueSources != null) {
      _keyValueSources.addAll(keyValueSources);
    }
    if (databaseSources != null) {
      _customDatabaseSources.addAll(databaseSources);
    }

    if (showNetworkNotification) {
      _initNetworkNotifier(notifier: notifier);
    }
    if (showCrashNotification) {
      _initCrashNotifier(notifier: crashNotifier);
    }
  }

  /// Crash notifier. Assigned synchronously (before `init()` is awaited) so
  /// this field is never null once the constructor returns.
  ///
  /// **This does not make startup crashes notify.** The notifier stays
  /// unavailable until `init()` resolves, so [NetworkNotifier.showCrash]
  /// no-ops during that window either way — the assignment order only moves
  /// where the call stops, not whether a notification appears. Fixing the
  /// window for real needs queue-and-flush; it is a documented known
  /// limitation instead. See `docs/features/2026-09-06-crash-notification.md`
  /// §6.5.
  NetworkNotifier? _crashNotifier;

  /// The crash notifier, exposed so tests can assert it is assigned
  /// synchronously (before [NetworkNotifier.init] is awaited).
  @visibleForTesting
  NetworkNotifier? get crashNotifierForTesting => _crashNotifier;

  Future<void> _initCrashNotifier({NetworkNotifier? notifier}) async {
    final crash =
        notifier ?? NetworkNotifier.crash(onTap: _openConsoleFromNotification);
    _crashNotifier = crash;
    await crash.init();
  }

  void _notifyCrash(String message, Map<String, dynamic>? data) {
    _crashNotifier?.showCrash(
      exceptionType: data?['exceptionType']?.toString() ?? 'Error',
      message: message,
    );
  }

  Future<void> _initNetworkNotifier({NetworkNotifier? notifier}) async {
    final networkNotifier =
        notifier ??
        NetworkNotifier.network(onTap: _openNetworkFromNotification);
    await networkNotifier.init();
    // Wire onAdd only after init() resolves. init() never rejects (it catches
    // and swallows platform errors internally), so this callback always runs.
    // Requests that arrive before init completes are not forwarded to the
    // notifier — which is correct, since _available isn't true until init
    // succeeds, so showOrUpdate would no-op on them anyway. This just avoids
    // holding a callback that fires into an uninitialised notifier.
    _registry.network.onAdd = (entry, total) {
      networkNotifier.showOrUpdate(entry, total);
    };
    final entries = _registry.network.entries;

    if (entries.isNotEmpty) {
      networkNotifier.showOrUpdate(entries.first, entries.length);
    }
  }

  /// Registers a database browser source.
  void registerDatabaseSource(DatabaseBrowserSource source) {
    _customDatabaseSources.add(source);
  }

  /// Registers a key-value browser source.
  void registerKeyValueSource(KeyValueBrowserSource source) {
    _keyValueSources.add(source);
  }

  /// Mounts the FAB overlay onto the screen.
  void attach({required BuildContext context, bool visible = true}) {
    _overlayManager.attach(context: context, visible: visible);
  }

  /// Removes the FAB overlay, and the lifecycle observer when
  /// [captureLifecycleEvents] is enabled.
  void detach() {
    _overlayManager.detach();
    _lifecycleHandler.detach();
  }

  /// Records a log message.
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _registry.log.add(
      LogEntry(
        message: message,
        level: level,
        stackTrace: stackTrace,
        data: data,
        activeRoute: _currentTopPageLabel(),
      ),
    );
  }

  /// Attaches the three standard Flutter error hooks, chaining/wrapping any
  /// existing host handler so errors are always forwarded downstream.
  ///
  /// Idempotent: the dedup flag ensures hooks are attached at most once, so an
  /// error never produces two log entries even when [captureUncaughtErrors] and
  /// a manual [setupErrorHandlers] call are combined.
  @visibleForTesting
  void setupErrorHandlers() {
    _uncaughtErrorHandler.attach();
  }

  /// Records a network request or response, returning the stored entry.
  ///
  /// Pass the entry returned for the pending request as [replaces] when
  /// logging its completed counterpart, so the pending entry is updated in
  /// place instead of producing a duplicate list item.
  NetworkEntry logNetwork(NetworkEntry entry, {NetworkEntry? replaces}) {
    return _registry.network.add(entry, replaces: replaces);
  }

  /// Records a database operation.
  void database(
    DatabaseOperation operation,
    String tableName, {
    Map<String, dynamic>? data,
    int? affectedRows,
  }) {
    _registry.database.add(
      DatabaseEntry(
        operation: operation,
        tableName: tableName,
        data: data,
        affectedRows: affectedRows,
      ),
    );
  }

  /// Cross-layer merged timeline: reads the four buffers filtered by [sources],
  /// merged and sorted by timestamp descending (newest first). Defaults to all
  /// sources. Thin forward to [InspectorRegistry.mergedTimeline].
  List<TimestampedEntry> mergedTimeline({
    Set<TimelineSource> sources = const {
      TimelineSource.log,
      TimelineSource.network,
      TimelineSource.nav,
      TimelineSource.db,
    },
  }) => _registry.mergedTimeline(sources: sources);

  /// Best-effort label for the current top-most page, for the lifecycle log
  /// suffix. Replays [navigatorEntries] and formats the top route as
  /// `displayName (routeName)`, dropping the `(routeName)` part when the route
  /// has no name. Returns `null` when the stack cannot be resolved (empty
  /// history), so the caller omits the suffix rather than inventing one.
  String? _currentTopPageLabel() {
    final stack = NavigatorStackResolver().resolve(navigatorEntries);
    if (stack.isEmpty) return null;
    final top = stack.first;
    final route = top.routeName;
    return (route == null || route.isEmpty)
        ? top.displayName
        : '${top.displayName} ($route)';
  }

  /// Opens the full-screen dashboard modal.
  ///
  /// [initialIndex] selects the starting tab: Console (0), Network (1),
  /// Navigator (2), Database (3). Optional tabs are appended after these, so
  /// the indices above never shift: Storage (when [keyValueSources] is not
  /// empty), then a custom tab (when one is provided).
  void openDashboard({int initialIndex = 0}) {
    // navigatorKey is required, but its context is only mounted once the app
    // has built its Navigator — a call before first frame is still a no-op.
    final context = navigatorKey.currentContext;
    if (context == null) return;
    DashboardModal.show(context, this, initialIndex: initialIndex);
  }

  /// Opens the dashboard on the Network tab in response to a notification tap.
  void _openNetworkFromNotification() {
    openDashboard(initialIndex: 1);
  }

  /// Opens the dashboard on the Console tab in response to a crash
  /// notification tap — that is where the error and its stack trace landed.
  void _openConsoleFromNotification() {
    openDashboard(initialIndex: 0);
  }

  /// Clears all console logs.
  void clearLogs() {
    _registry.log.clear();
    clearBookmarks();
  }

  /// Clears all network logs.
  void clearNetwork() {
    _registry.network.clear();
    clearBookmarks();
  }

  /// Clears all navigator history.
  void clearNavigator() {
    _registry.navigator.clear();
    clearBookmarks();
  }

  /// Clears all database logs.
  void clearDatabase() {
    _registry.database.clear();
    clearBookmarks();
  }
}
