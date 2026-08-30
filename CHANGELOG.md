## 2.4.0

### Added
* **Stack traces are normalized before you read them**: A Flutter stack trace is mostly framework plumbing — dozens of consecutive `package:flutter/…` and `dart:…` frames burying the two lines of your own code that actually matter. Log detail views now show a *concise* stack trace by default, collapsing each run of framework-internal frames into a single `[... N frames of framework internals]` marker. The first and last frame of every collapsed run are deliberately kept, so the boundary between your code and the framework — the part that tells you where control crossed over — is never lost.
* **Asynchronous gaps are marked explicitly**: `<asynchronous suspension>` separators are rendered as `<-- async gap -->`, so a stack trace broken across an `await` reads as one causal chain instead of two unrelated fragments.
* **Raw / concise toggle, and exports follow what you see**: The log detail view carries a **Show raw / Show concise** switch, and the copy and share actions export whichever form is currently displayed — so a stack trace pasted into a ticket matches the one being discussed. `buildLogPlainText` defaults to the concise form and accepts `isConcise: false` for the untouched original. The raw stack trace is never mutated; normalization is purely a presentation-layer projection.
* **Log entries record the active route**: `LogEntry` gains an `activeRoute` field, populated automatically with the top-most page at the moment the log was recorded, and shown in log detail views and plain-text exports. Where a log fired is often the missing half of why it fired — an error logged from `CheckoutPage` and the same error logged from a background refresh are different bugs.

### Fixed
* **The Console `Error` level chip no longer overlaps `⚡ Errors only`**: Both filters existed and claimed to isolate failures, but only `⚡ Errors only` spanned every source — the `Error` level chip silently constrained logs alone, so picking it hid failed network calls that the other chip kept. The redundant level chip is gone, leaving one unambiguous failure filter.

## 2.3.0

### Added
* **Storage tab — browse and edit key-value stores**: A new dashboard tab lists the contents of `SharedPreferences`, `FlutterSecureStorage` and friends, with a search field over keys and values and a selector to switch between registered stores. Entries can be edited, deleted individually, or wiped in bulk, so a stale token or a stuck feature flag can be cleared on-device instead of through an `adb shell` or a reinstall. The tab only appears once at least one source is registered.
* **`KeyValueBrowserSource` — pluggable storage adapters**: Register stores through `FlutterInspector(keyValueSources: [...])` or `registerKeyValueSource(...)`, mirroring how `DatabaseBrowserSource` already works. The package ships no implementation and takes no dependency on any storage plugin — the README carries copy-paste adapter examples for `SharedPreferences` and `FlutterSecureStorage`, and each adapter takes an optional `name` so two stores of the same kind stay distinguishable in the selector. When a source cannot enumerate its keys (`readAll()` is unsupported on some platforms for secure storage), the tab surfaces a retryable error rather than an empty list, so "cannot enumerate" is never mistaken for "nothing stored".
* **Confirmation before every write**: Edits, deletes and clear-all each require an explicit confirmation. Editing runs a type-validation step first, so a mistyped value is rejected before the confirmation dialog appears rather than after it. Clear-all names the source and the entry count it is about to wipe, and is disabled while a store is still loading — so a destructive action can never be authorised against another source's data.
* **Writes are logged to the Console timeline**: A successful write is recorded as an `info` log carrying the key, source and type, so a change made while debugging does not become a mystery later. Cancelled and failed writes leave no log — the audit trail only ever claims what actually landed. Old and new values are masked unless the host sets `redactSensitiveData: false`, since the log is shareable and a key-value source may hold secrets.

## 2.2.0

### Added
* **Console search and level filtering**: The Console tab now carries a search field above the timeline, matching a case-insensitive keyword against each entry's readable fields — log messages and stack traces, network URLs/methods/status codes, route names, and database tables and operations. A per-`LogLevel` chip row (`Verbose`, `Debug`, `Info`, `Warning`, `Error`) narrows logs further, and an `⚡ Errors only` chip isolates failures across types: `warning`/`error` logs together with failed network calls. Level chips only constrain log entries, so picking one does not silently hide network, navigation, or database events.
* **Jump back to the full timeline**: While a filter is active, tapping any row clears every filter and scrolls the unfiltered timeline to that same entry — so a row found by searching can be read back in its surrounding context instead of in isolation.

### Fixed
* **Long-press bookmarking now survives filtering**: Bookmarking a row by long-press stopped working once a search or level filter was applied. Filtered rows accept long-press again, alongside the new tap-to-jump gesture.
* **Search field text is cleared on jump-back**: Jumping from a filtered row back to the full timeline reset the filter but left the typed keyword visible in the search field, so the UI showed an active search over unfiltered results.

## 2.1.0

### Added
* **Dashboard error badges**: The Console and Network tabs now show a badge with the current error count, so problems are visible without opening each tab. Badges update live as new entries arrive.

### Fixed
* **`navigatorKey` is now declared `required`**, matching the behaviour that [2.0.0](#200) already introduced. The parameter has been mandatory since the dashboard started routing through it, but the constructor still accepted its omission — so the failure surfaced as a dashboard that silently would not open, rather than as an error. It is now caught at compile time. Code that already passes a `navigatorKey` is unaffected.
* **Reported package version**: `FlutterInspector.version` and the header of every exported diagnostic report reported `1.9.0` on the 2.0.0 release. The version constant is now in sync with the published package version.

### Docs
* **`navigatorKey` wiring is now shown in both READMEs' Initialize example** — previously neither did, so following them produced an inspector whose dashboard could not open. Both now also note that passing the same key to `MaterialApp` is required and not compiler-checkable.
* The Traditional Chinese README additionally had a stale `openDashboard(context)` call (an API removed in 2.0.0) and an outdated install version — both corrected.
* The 2.0.0 entry below has been expanded: it described the `openDashboard` signature change but not the resulting `navigatorKey` requirement.

## 2.0.0

### BREAKING CHANGES
* **`openDashboard()` no longer takes a `BuildContext`, and `navigatorKey` became mandatory as a result.** The dashboard now resolves its context from `navigatorKey` instead of receiving one at the call site, so an inspector constructed without that key cannot open the dashboard at all — magical tap, floating button, and notification tap each become a silent no-op.

  The constructor still accepted its omission in this release, so the requirement was enforced only at runtime, without an error explaining the failure. It is declared `required` from 2.1.0 onward.

  **Migration** — pass a key to the inspector, and the *same* key to your `MaterialApp`:

  ```dart
  final navigatorKey = GlobalKey<NavigatorState>();

  final inspector = FlutterInspector(navigatorKey: navigatorKey);

  MaterialApp(navigatorKey: navigatorKey, /* ... */);
  ```

  Also drop the argument at every call site: `openDashboard(context)` → `openDashboard()`.

  > This entry was expanded in 2.1.0. It originally read only "Removed the `BuildContext` parameter … as it is no longer required for opening the inspector", which described the signature change but omitted that the context requirement had moved to `navigatorKey` rather than disappeared.

### Added
* **Timeline Bookmark**: Long-press any timeline entry in the Console tab to bookmark it. A push-pin indicator is displayed, and a new "Bookmarks" filter chip allows isolating bookmarked entries. Diagnostic reports now prefix bookmarked entries with a 📌 icon.

## 1.9.0

### Added
* **Slow network request indicator**: Network requests exceeding a configurable time threshold are now visually marked with a `🐢 SLOW` indicator in the Network tab to easily spot performance bottlenecks.
* **Configurable slow request threshold**: The threshold for marking a request as slow can now be configured via the `slowRequestThreshold` parameter on the `FlutterInspector` constructor (defaults to 2 seconds).

### Fixed
* **Constructor validation**: `FlutterInspector` now rejects negative `slowRequestThreshold` values.

## 1.8.0

### Added
* **App lifecycle markers**: `FlutterInspector(captureLifecycleEvents: true)` records every app lifecycle transition (`resumed` / `inactive` / `paused` / `detached`, plus `hidden` on Flutter 3.13+) as an `info` Console log, so crashes and stalled network calls can be read against whether the app was in the foreground. Each entry names the current top-most page (e.g. `App lifecycle: resumed · HomePage (/home)`) so repeated home/back switches stay distinguishable without cross-referencing the Navigator tab. Opt-in and disabled by default; `detach()` removes the observer.

### Changed
* **Error rows are tinted in the merged Timeline**: error-level logs and failed network calls now carry a faint red row background in the Console tab, so they're spottable while scrolling instead of relying on text colour alone. Warnings keep their orange text but stay un-tinted, so a warning-heavy app doesn't wash the whole list out.

### Fixed
* **Inspector routes no longer pollute the Navigator tab**: opening a detail view or bottom sheet inside the dashboard (log/network details, table rows, cell details, the export sheet) was recorded as navigation in the *host app's* history, so the more thoroughly you investigated, the noisier the Navigator tab became — the export sheet even wrote itself into the report it was about to produce. Every route the dashboard opens is now tagged with a shared prefix that the observer filters on. Host app navigation is untouched, including unnamed routes.

## 1.7.1

### Fixed
* **Duplicate uncaught error logs**: `FlutterError.onError` and `ErrorWidget.builder` previously logged the same build-crash `FlutterErrorDetails` twice; an object-identity guard now dedupes them while still logging each distinct crash.

## 1.7.0

### Added
* **WebView inline debugging**: introduced `WebViewBridgeAdapter` and injected JS bridge payload to seamlessly capture and translate a WebView's `console.*`, `window.onerror`, `fetch`, and `XMLHttpRequest` activity into the native Console and Network tabs.
* **First-class provenance metadata**: network and log entries now include `origin` (e.g., `NetworkOrigin.webview` vs `NetworkOrigin.dio`) and `pageUrl` fields, clearly distinguishing native HTTP traffic from WebView traffic in the detail views.

### Fixed
* **WebView bridge reliability**: capped raw bridge message size before JSON decoding to prevent memory spikes, and properly guarded `XHR` response text reads for non-text response types.

## 1.6.0

### Changed
* **Diagnostic report Timeline**: the exported report's separate "Logs" section is now a chronological mixed **Timeline** that interleaves log, network, navigation, and database entries by timestamp (newest first), surfacing cross-layer causality at a glance. The independent Network / Navigation / Database detail sections remain below it.
* **"Errors & warnings only" now filters the whole Timeline**: previously the toggle restricted only the log section; it now keeps error-signal entries across the entire Timeline stream (logs plus failed/errored network calls), while the detail sections are unaffected.

### Fixed
* **Timeline one-liner hardening**: report one-liners are now guarded against CRLF injection and malformed-URL leaks.

## 1.5.0

### Added
* **One-tap diagnostic report**: the dashboard app bar now has an export action that builds a single Markdown report — device/app header, current route stack, and the log / network / navigation / database sections — and hands it to the system share sheet. Three independent filters: time window (last 5m / last 1h / all), which sources to include, and an optional "errors & warnings only" toggle for the log section (off by default). Nothing is written to disk.
* **`DiagnosticInfoSource`**: optional injection point for device and app metadata (`FlutterInspector(diagnosticInfoSource: ...)`). This package stays free of any device-info plugin — hosts supply the values themselves, and the report header degrades to `N/A` when no source is registered. Follows the same host-injection shape as `DatabaseBrowserSource`.

## 1.4.0

### Added
* **Network error aggregation summary**: the Network tab now shows a collapsible banner above the call list that groups failed/errored requests by status code (falling back to error type for transport failures where `statusCode` is `null`), with a per-group count and first/last-seen time range. Tapping a group card filters the call list down to just that error; tapping again clears the filter. The banner aggregates from the same keyword/method/status-filtered list shown below it, so counts always match what's visible.

### Fixed
* **Scrollable TabBar alignment on Material 3**: the dashboard's tab bar now sets `tabAlignment: TabAlignment.start`, fixing tabs rendering centered/misaligned in scrollable mode under Material 3.

## 1.3.1

### Changed
* **Code quality & performance optimization**: Refactored major dashboard tabs (Console, Network, Navigator, Database) to eliminate large helper methods and decompose them into lightweight, specialized, and reusable private Widget classes, improving rendering efficiency.
* **UI widgets consolidation**: Extracted shared `DetailSection` (with `DetailKeyValueRow`) and `ErrorCard` widgets to eliminate cross-file duplicate code.
* **Centralized log level colors**: Moved log level color mapping from ConsoleTab's helper methods into a unified `LogLevelColor` extension.

## 1.3.0

### Added
* **Structured DioException error capture**: `FlutterInspectorDioInterceptor.onError` now preserves the machine-readable `errorType` (`DioExceptionType`) and the `errorStackTrace` (stringified stack trace) instead of discarding them.
* **Exception Details section**: the Network detail view now displays an "Exception Details" card section for failed requests. It clearly distinguishes between transport-layer failures (where the request did not reach the server, showing `statusCode == null`) and server-side responses (where the server returned an error status code). It also provides a monospace-styled, copyable stack trace for debugging.
* **Text export support**: `buildPlainText` exports now include the `Error Type` and the `Stack Trace` when present, improving the diagnostic value of shared logs.

## 1.2.1

### Fixed
* **Console tab clear button**: clearing the Console tab's merged timeline now wipes all four underlying sources (log, network, navigator, database) instead of only logs. Previously, network/navigator/database entries would reappear after clearing because they share the same buffers rendered in the Console tab's merged timeline.

## 1.2.0

### Added
* **Navigator active route stack visualization**: the Navigator tab now offers an "Active Stack" / "Event History" toggle. Active Stack derives the current route stack live from the recorded push/pop/replace/remove events and renders it top-first as vertical cards, with the current screen highlighted; Event History remains the original raw event log, unchanged.

## 1.1.0

### Added
* **Merged cross-layer timeline**: the Console tab now interleaves logs, network, navigation, and database events on a single timestamp-sorted timeline (newest first), with a filter chip per source to narrow it down. The same view is exposed programmatically via `FlutterInspector.mergedTimeline({sources})`, which returns `List<TimestampedEntry>` sorted by `timestamp` descending. Filter with the new `TimelineSource` enum (`log` / `network` / `nav` / `db`); a shared `displayTime` (`HH:mm:ss.mmm`) helper is available on every timeline entry.
* **Sensitive-data redaction**: a new `redactSensitiveData` constructor flag on `FlutterInspector` (defaults to `true`) masks sensitive headers — `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key` (matched case-insensitively) — with `••••` across every Network share/export path (copy as cURL, copy as text, system share sheet). Secure by default; pass `redactSensitiveData: false` to opt out. Headers shown live inside the dashboard are unaffected.

### Changed
* The Console timeline is now assembled by merging the four event buffers at render time instead of mirroring network and navigation events into the Console as separate log strings. As a result, `FlutterInspectorDioInterceptor` no longer emits an extra `debug`-level Console log per request, and `FlutterInspectorNavigatorObserver` no longer mirrors route changes as `warning`-level logs (both introduced in 0.2.4) — those events still appear on the merged timeline via their own buffers, without the duplicate log entries.

## 1.0.0

### Added
* **Network Request Replay**: You can now resend captured HTTP requests directly within the Network detail view. It replays the request locally using the same Dio client (carrying the same headers, base URL, and interceptors). Replayed requests automatically show up as new entries in the Network tab, marked with a dedicated "Replay" label.

### Changed
* **Breaking Change**: `FlutterInspector` constructor no longer takes a `dio` parameter, and does not provide a default fallback Dio. To use the Network Request Replay feature, you must explicitly pass the source `Dio` instance when creating `FlutterInspectorDioInterceptor`.
* **Dio Interceptor Signature**: `FlutterInspectorDioInterceptor` now takes an optional named `sourceDio` parameter (`FlutterInspectorDioInterceptor(inspector, {sourceDio: dio})`). Without passing the `sourceDio`, the "Resend" action in the Network detail view will be disabled.

## 0.3.1

### Documentation
* Refreshed the README screenshots: re-captured the database browser view and added Uncaught Error and Database Browse captures sourced from the example app.
* Removed the legacy Database (operation-log) screenshot in favor of the Database Browse capture, and re-flowed the Screenshots grid to a clean 3-column layout.

## 0.3.0

### Added
* **Uncaught error capture (opt-in)**: pass `captureUncaughtErrors: true` to `FlutterInspector(...)` to capture uncaught errors from `FlutterError.onError`, `PlatformDispatcher.instance.onError` (including unawaited `Future` errors) and `ErrorWidget.builder` as `LogLevel.error` logs in the Console tab. Defaults to **off**; when on, every hook chains/wraps the existing host handler — errors are always forwarded downstream, never swallowed.
* **Expandable Console error logs**: tapping a Console log that carries a `stackTrace` or structured `data` now opens a detail view (`LogDetailView`) showing the message, level, timestamp, a selectable/copyable stack trace, and the structured data — with copy/share actions.
* Expandable Console rows now show a trailing chevron, matching the Network tab, so it is clear at a glance which logs open a detail view.

### Fixed
* A log carrying an empty-string `stackTrace` is no longer treated as expandable, so it neither appears tappable in the Console nor renders an empty stack-trace section in the detail view.

## 0.2.4

### Added
* Network requests and responses captured by `FlutterInspectorDioInterceptor` are now mirrored to the Console tab (at `debug` level), so HTTP traffic is visible alongside other logs.
* `FlutterInspectorNavigatorObserver` now mirrors route changes (push / pop / replace / remove) to the Console tab at `warning` level, in addition to the Navigator history.

### Changed
* Adjusted the `LogLevel.debug` text color in the Console tab to blue-grey for better visibility.

### Fixed
* Fixed the `Status` row in the Network detail view's General section so its value aligns with the other fields (Method, URL, Duration, etc.) instead of starting at an inconsistent position.

## 0.2.3

### Fixed
* Fixed foreground notification banner on macOS where the host app `AppDelegate` failed to cast to `UNUserNotificationCenterDelegate`. macOS hosts must now explicitly conform and handle the callback.
* Resolved a race condition during cold-starts where network notifications logged before the notifier finished initialization were lost.
* Fixed the `README.md` setup instructions to separate iOS and macOS delegate compliance procedures.

## 0.2.2

### Added
* `FlutterInspectorNavigatorObserver` now resolves route `widgetType` and name natively by default.
* Added support to filter out the internal `DashboardModal` route (`flutter_inspector_dashboard`) from the Navigator history logs to prevent UI noise.
* Added a `Makefile` for automated common Flutter development tasks.

### Changed
* Refactored project directory structure: renamed internal `flutter_inspector_impl.dart` to `flutter_inspector.dart` and `integrations` directory to `interceptors`.

### Fixed
* Fixed a bug in the example app where null navigator context could crash the app when attempting to open the dashboard modal.

## 0.2.1

### Fixed
* Raised `dio` lower bound to `^5.2.0` to match the actual API usage (`DioException`), fixing the pub.dev downgrade analysis.
* Restored WASM compatibility: web builds now use the browser Web Share API (`package:web`) instead of `share_plus`, and the network notifier resolves to a no-op stub on web, keeping `dart:io` out of the web import graph.
* Dismissing the web share sheet (`AbortError`) is now treated as a cancel instead of a failure, so it no longer triggers the clipboard fallback.

## 0.2.0

### Added
* Database table browser with two-level navigation (table list page and row grid view).
* Multi-direction scrolling (horizontal and vertical) in row grid view.
* Local column sorting with NULLs always sorted to the end in both directions.
* Dialog value preview and copy for individual grid cell values.
* Pagination for row grid (200 rows limit with 'Load More' button).
* Public `DatabaseBrowserSource`, `DatabaseTableInfo`, and `DatabaseTablePage` classes.
* `FlutterInspector.registerDatabaseSource` and constructor parameter `databaseSources` to dynamically registry third-party databases (e.g. SQLite, ObjectBox).

### Changed
* Redesigned Database tab from chronological operation list to database table list view.

## 0.1.0

Initial release on pub.dev (package renamed from `flutter_inspector` to `flutter_inspector_kit`).

* Console, Network, Navigator, and Database inspectors behind a single unified API.
* In-app overlay FAB and full-screen Dashboard.
* `Dio` interceptor for network traffic capture.
* `MagicalTap` widget for gesture-based invocation.
* Network notification heads-up banner: silent heads-up on Android (HIGH priority channel) and foreground banner on iOS, with automatic dismissal and visual feedback.
* Notification throttling: consecutive network calls within a 2-second window update the notification in place without re-alerting.
* Android notification channel `flutter_inspector_network_v2` (HIGH importance); the legacy `flutter_inspector_network` channel is automatically deleted during upgrade.
* Dio interceptor updates the pending request entry in place when its response or error arrives (no duplicate "Pending" entries); `logNetwork` gained an optional `replaces` parameter and returns the stored entry.
