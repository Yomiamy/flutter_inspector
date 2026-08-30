# 🔍 Flutter Inspector

[![pub package](https://img.shields.io/pub/v/flutter_inspector_kit.svg)](https://pub.dev/packages/flutter_inspector_kit)
[![platform](https://img.shields.io/badge/platform-flutter-blue.svg)](https://pub.dev/packages/flutter_inspector_kit)

**Language / 語言**: [English](README.md) | [繁體中文](README.zh-TW.md)

In-app, multi-inspector debugging overlay for Flutter apps — logs, network, navigation, and database, all behind one unified API.

## 📦 Features

| Feature | Description | Use Case Example |
|---|---|---|
| 🪵 **Console** | Capture logs across five severity levels (`verbose` / `debug` / `info` / `warning` / `error`), with optional structured data and stack traces; stack traces are shown in their concise form by default, with the raw trace one toggle away | QA says "tapping checkout does nothing" — open Console, spot a red error entry in the timeline; tap in to see the structured error detail, response body, and the stack trace with framework noise collapsed, so the frames from your own code are what you read first |
| 📌 **Timeline Bookmark** | Long-press any timeline entry to bookmark it with a visual indicator, then quickly filter the view to show only bookmarked items | Found a suspicious request while scrolling through hundreds of logs? Bookmark it, then toggle the "Bookmarks" chip to isolate it alongside other key events without losing track of your place in the timeline |
| 🧵 **Merged Timeline** | Console tab interleaves logs, network, navigation, and database events on one timestamp-sorted timeline, with per-source filter chips; error logs and failed network calls carry a faint red row tint so they stand out while scrolling | Continuing the checkout case — switch the source chip to "All" and scroll back along the timeline to inspect the request that got 401: check what token was in the `Authorization` header, what params were sent, and compare with backend expectations to pinpoint why the server rejected it — all without switching tabs or manually comparing timestamps |
| 📡 **Network** | Intercept HTTP traffic via Dio; inspect structured request/response details; search/filter by URL, method, or status; share as cURL | A page shows up completely blank — open the Network tab to find the API returned an error, so there's no data to display; tap in to inspect request params and response body, then copy as a runnable cURL command and paste it into a bug ticket for the backend team to reproduce |
| 🔄 **Network Replay** | Resend a captured request using the original Dio instance (same headers, base URL, interceptors); replayed entries are auto-labeled | Re-trigger a failed API call on-device to verify a server-side hotfix without restarting the app or rebuilding the user flow |
| 🐢 **Slow Request Indicator** | Network requests that exceed a configurable time threshold are flagged with a `🐢 SLOW` visual marker in the Network tab | Easily spot endpoints that are slowing down your app, and track down performance bottlenecks without digging through logs manually |
| 🚨 **Structured Network Errors** | Failed requests show an **Exception Details** section distinguishing transport-layer failures (device offline / DNS / timeout) from server-side errors (4xx/5xx), with copyable stack traces | Instantly tell whether "Failed" means the device lost connectivity or the server returned 500 — no more guessing during QA |
| 📊 **Error Aggregation Summary** | Network tab shows a collapsible banner that groups failed/errored requests by status code (or error type for transport failures), with per-group counts and time range; tap a group to filter the call list down to just that error | A page is flooded with dozens of failed calls — glance at the summary banner to see "12× 401", "3× timeout", tap the 401 group to isolate exactly those calls instead of scrolling through the full list |
| 🩺 **Diagnostic Report** | Export a single Markdown report — device/app header, current route stack, and the logs / network / navigation / database sections — filtered by time window (5m / 1h / all), source, and an optional errors-only toggle; straight to the share sheet, nothing written to disk | QA reproduces a bug and, instead of screenshotting four tabs and hand-typing the OS version, taps Export once and pastes a complete report into the Jira ticket |
| 🌐 **WebView Inline Debugging** | Bridge a WebView's own `console.*`, `window.onerror`/`unhandledrejection`, and `fetch`/`XMLHttpRequest` activity into the same Console and Network tabs used for native logs and Dio traffic — dependency-free, wire your own `webview_flutter` or `flutter_inappwebview` to `WebViewBridgeAdapter` | A hybrid screen misbehaves and you can't tell if the bug is in Flutter or the embedded web page — see the WebView's JS errors and its `fetch`/`XHR` calls inline in Console/Network, tagged by origin, so you know instantly which side to fix without attaching Chrome DevTools to the WebView |
| 🛡️ **Sensitive-Data Redaction** | Secure by default — sensitive headers (`Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`) are masked in every share/export path | Safely share network logs with teammates or attach them to Jira tickets without leaking tokens or session cookies |
| 🧭 **Navigator** | Track route pushes, pops, and replacements automatically; toggle between **Event History** (raw log) and **Active Stack** (live route-stack visualization). The dashboard's own routes are filtered out, so investigating never pollutes the history | Verify deep-link routing, confirm back-stack correctness, or diagnose "why did the user land on this screen?" during a QA walkthrough — and since opening detail views doesn't write into the history, the stack you read after ten minutes of digging is still your app's, not a log of your own investigation |
| 🗄️ **Database** | Record insert / update / delete / query operations with affected-row counts and payloads; browse real tables via pluggable `DatabaseBrowserSource` (SQLite / ObjectBox adapters provided) | Verify that a "Save" action actually wrote the expected rows; browse local SQLite tables on-device without pulling the `.db` file |
| 🔑 **Storage** | Browse, edit, delete and clear key-value stores via pluggable `KeyValueBrowserSource` (SharedPreferences / SecureStorage adapter examples provided); every write is confirmed, and successful writes are logged | Check whether a stale token or a stuck feature flag is behind the bug — and clear it on-device, without an adb shell |
| 🧵 **Readable Stack Traces** | Framework-internal frames collapse into a `[... N frames of framework internals]` marker (boundary frames preserved) and async suspensions render as `<-- async gap -->`; a raw/concise toggle switches the view, and the share menu exports either form explicitly | An uncaught error produces 40 lines of `package:flutter/…` around the two lines of your own code that matter — the concise view puts your frames back on screen without scrolling, and the raw form is one tap away when you need the full trace |
| 🧭 **Log Route Context** | Every log entry records the top-most page at the moment it was written, shown in detail views and exports | The same "token refresh failed" error means different things from the checkout screen and from a background refresh — the recorded route tells the two apart when reading the timeline later |
| 🛑 **Uncaught Error Capture** *(opt-in)* | Automatically turn uncaught errors into `error`-level Console logs via three Flutter hooks (build/layout/paint, async, `ErrorWidget`); chains existing handlers — never swallows errors | An unawaited `Future` throws deep inside a third-party package — no `try/catch` anywhere near it. Uncaught error capture logs it automatically with a full stack trace, so it shows up in Console without any manual instrumentation |
| ⏱️ **App Lifecycle Markers** *(opt-in)* | Record every `resumed` / `inactive` / `paused` / `detached` transition as an `info` Console log, each naming the top-most page at that moment, interleaved into the merged Timeline | A batch of requests fails with timeouts that nobody can reproduce at a desk — read the Timeline and an `App lifecycle: paused · CheckoutPage` marker sits right before them, so the OS froze the network while the user switched away; the backend was never at fault. Equally useful in reverse: confirming a "refresh on resume" actually fires, and on which page |
| 🔔 **Live Notification** *(opt-in)* | A system notification summarising the latest API call and the running total; tap to jump straight to the Network tab | Monitor API traffic in real-time while navigating the app — no need to keep the dashboard open; also useful for verifying whether the number of API calls per operation is reasonable (e.g., a single page load triggering dozens of calls hints at redundant requests) |
| 👆 **Magical Tap & Floating Button** | Open the dashboard with a hidden multi-tap gesture or a draggable in-app FAB | Embed in a release build as a hidden diagnostic entry point — when QA or users hit an issue, trigger the inspector on the spot for initial error triage without rebuilding a debug version or tracing through source code |
| 🧩 **Custom Tab** | Inject your own widget as a 5th dashboard tab via `FlutterInspector(customTab: ..., customTabTitle: ...)` — sits alongside Console / Network / Navigator / Database | Surface app-specific debug tooling right next to the built-in inspectors — a feature-flag toggle panel, the current auth/session state, or a "clear cache" button — so your team's ad-hoc diagnostics live in one place instead of a separate debug screen |

## 📱 Screenshots

|Home|Console|Network|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/home.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/console.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network.png?raw=true"/>|

|Network Detail|Navigator|Uncaught Error|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network_detail.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/navigator.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/uncaught_error.png?raw=true"/>|

|Database Browse|||
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/database_browse.png?raw=true"/>|||

## 🪚 Usage

### Add to pubspec.yaml

```yaml
dependencies:
  flutter_inspector_kit: ^2.4.0
```

Then run `flutter pub get`.

### Initialize

Create a single shared `FlutterInspector` instance and wire it into your app. A `navigatorKey` is **required** — the inspector routes to the dashboard through it — so create one, pass it to the inspector, and pass **the same key** to your `MaterialApp`. Then register the navigator observer to track routes, and wrap your app in `FlutterInspectorMagicalTap` so a hidden gesture can open the dashboard from anywhere.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

// 1. One key, shared by the inspector and the MaterialApp.
final navigatorKey = GlobalKey<NavigatorState>();

final inspector = FlutterInspector(
  // Required: the dashboard is opened through this key.
  navigatorKey: navigatorKey,
  // Optional: configure threshold for marking requests as "🐢 SLOW" (defaults to 2s)
  slowRequestThreshold: const Duration(seconds: 3),
);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 2. The same key — without this the dashboard has no context to open in.
      navigatorKey: navigatorKey,
      // 3. Track navigation events
      navigatorObservers: [inspector.navigatorObserver],
      // 4. A hidden gesture opens the dashboard from anywhere
      builder: (context, child) {
        return FlutterInspectorMagicalTap(
          onTap: () => inspector.openDashboard(),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MyHomePage(),
    );
  }
}
```

That's it? Yes, that's it.

> **Both halves are required.** `navigatorKey` is a compile-time requirement on the constructor, but passing it to `MaterialApp` is not something the compiler can check. Miss that second step and the key never gets a mounted context, so `openDashboard()` silently does nothing — via magical tap, floating button, or notification tap alike.

### Floating button

Prefer a visible trigger? Attach the inspector once the first frame is built to show a draggable floating button that opens the dashboard.

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    inspector.attach(context: context);
  });
}
```

Remove it again with `inspector.detach()`.

### Add a custom tab

Inject your own widget as a 5th dashboard tab, sitting alongside the built-in Console / Network / Navigator / Database tabs. Use it to surface app-specific diagnostics — a feature-flag panel, the current auth state, a "clear cache" button, etc.

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  customTab: const MyDebugPanel(),
  customTabTitle: 'Flags', // defaults to 'Custom'
);
```

The widget is built lazily when its tab is first shown and can be any Flutter widget — including stateful ones with their own controllers.

### Log network requests

#### With Dio

Add the interceptor to your `Dio` instance and every request/response is captured automatically. Pass the `sourceDio` instance to enable the **Resend (Replay)** feature in the Network detail view.

```dart
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));
```

##### Multiple Dio Instances

If your app uses multiple `Dio` instances (e.g., `authDio` for authenticated API calls, `publicDio` for public assets), register the interceptor on each instance and make sure to pass the respective instance as `sourceDio`:

```dart
// Authenticated API client
final authDio = Dio();
authDio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: authDio));

// Public API client
final publicDio = Dio();
publicDio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: publicDio));
```

This guarantees that replaying a request in the Network detail view uses the exact same `Dio` instance, maintaining the correct baseUrl, interceptors, and authentication state.

#### With other HTTP clients

Build a `NetworkEntry` yourself and pass it in:

```dart
inspector.logNetwork(entry);
```

To show an in-flight request that later resolves, log the pending entry first, then log the completed one with `replaces` so it updates in place instead of duplicating:

```dart
final pending = inspector.logNetwork(NetworkEntry(method: 'GET', url: url));
// ...after the response arrives:
inspector.logNetwork(completedEntry, replaces: pending);
```

### Inside the Network tab

- **Search & filter**: filter the call list by URL, method, or status code (case-insensitive); method and status (`2xx`/`3xx`/`4xx`/`5xx`/`Failed`) chips narrow it further.
- **Error summary banner**: a collapsible banner above the call list groups failed/errored requests by status code (or error type for transport failures — offline/timeout/DNS), showing a per-group count and first/last-seen time range. Tap a group card to filter the list down to just that error; tap again to clear the filter.
- **Call details**: tap any call for a structured view — General (method, URL, status with color coding, duration, request/response sizes), Query Parameters, Headers, and JSON-pretty bodies. Truncated bodies are clearly marked. Failed requests display an **Exception Details** section distinguishing between transport-layer failures and server-side errors, with a copyable stack trace.
- **Sharing**: copy the call as a runnable `cURL` command, copy the full details as text, or open the system share sheet (native via `share_plus`, web via the browser Web Share API — falls back to the clipboard when unavailable).
- **Replay / Resend**: for requests captured with a `sourceDio` provided to the interceptor, you can trigger a "Resend" action in the detail view to replay the request locally using the same Dio client (carrying the same headers, base URL, and interceptors). Replayed requests automatically show up as new entries with a dedicated "Replay" label.

### Redact sensitive headers

Every share/export path in the Network detail view — copy as `cURL`, copy as text, and the system share sheet — **masks sensitive headers by default**, so secrets never leak to the clipboard, a share sheet, or a screenshot. The masked keys are `Authorization`, `Cookie`, `Set-Cookie`, and `X-Api-Key` (matched case-insensitively); their values are replaced with `••••`.

This is controlled by the `redactSensitiveData` constructor flag, which defaults to `true`. Pick one of the two configurations below.

Secure by default — sensitive headers are masked in shared/exported output:

```dart
final inspector = FlutterInspector(navigatorKey: navigatorKey);
```

Or opt out (e.g. internal builds where you need the raw values):

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  redactSensitiveData: false,
);
```

The flag only affects shared/exported text — the headers shown live inside the dashboard are always the real values.

### WebView inline debugging

Bridge a WebView's own `console.*`, `window.onerror`/`unhandledrejection`, and `fetch`/`XMLHttpRequest` activity into the same Console and Network tabs used for native logs and Dio traffic — one more event source, not a second system. The package stays dependency-free: you bring your own WebView package (`webview_flutter` or `flutter_inappwebview`) and wire it to `WebViewBridgeAdapter` yourself.

Every integration follows the same three steps:

1. Create `final adapter = WebViewBridgeAdapter(inspector);` — a translator that turns bridge messages into existing `LogEntry` / `NetworkEntry` objects via `inspector.log` / `inspector.logNetwork`. It holds no buffer and does no redaction of its own.
2. Wire your WebView package's channel/handler (named via the `kWebViewBridgeChannelName` constant, i.e. `'FlutterInspectorBridge'`) to call `adapter.handleMessage(rawMessageString)`.
3. Inject the `inspectorWebViewBridgeJs` payload into the page — it hooks `console.*`, `window.onerror`, `unhandledrejection`, `fetch`, and `XMLHttpRequest`, and posts one JSON envelope per event back through the channel.

#### With `webview_flutter`

```dart
final adapter = WebViewBridgeAdapter(inspector);
controller
  ..addJavaScriptChannel(
    kWebViewBridgeChannelName, // 'FlutterInspectorBridge'
    onMessageReceived: (m) => adapter.handleMessage(m.message),
  )
  ..setNavigationDelegate(NavigationDelegate(
    onPageStarted: (_) => controller.runJavaScript(inspectorWebViewBridgeJs),
  ));
```

Working demo: [`example/lib/demos/webview_demo.dart`](example/lib/demos/webview_demo.dart).

#### With `flutter_inappwebview`

```dart
final adapter = WebViewBridgeAdapter(inspector);
// AT_DOCUMENT_START injection catches even the page's earliest logs.
controller.addUserScript(userScript: UserScript(
  source: inspectorWebViewBridgeJs,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
));
controller.addJavaScriptHandler(
  handlerName: kWebViewBridgeChannelName,
  callback: (args) {
    // The page can call this handler directly — validate before forwarding.
    final raw = args.isNotEmpty ? args.first : null;
    if (raw is String) adapter.handleMessage(raw);
  },
);
```

Working demo: [`example/lib/demos/inappwebview_demo.dart`](example/lib/demos/inappwebview_demo.dart) — its page fires a log during document load, proving the document-start injection catches activity that `webview_flutter`'s wiring misses.

#### Provenance: telling WebView traffic apart from native

Every bridged request is tagged first-class: `NetworkEntry.origin` is `NetworkOrigin.webview` (native Dio traffic defaults to `NetworkOrigin.dio`) and `NetworkEntry.pageUrl` carries the issuing page's `location.href`. Both show up as **Origin** / **Page URL** rows in the Network detail view. Bridged log entries carry the same marking in `LogEntry.data` (`origin` / `pageUrl`), visible in the log detail view's Data section.

#### Injection timing: know what each package can and can't catch

The two packages inject at genuinely different points, and that changes what you see:

- **`flutter_inappwebview`**'s `UserScript` with `AT_DOCUMENT_START` runs before the page's own scripts, so it catches logs/errors/requests fired during the page's earliest initialization.
- **`webview_flutter`**'s `runJavaScript` only runs from `onPageStarted`, which fires *after* navigation has already begun — any `console.*` / error / fetch activity before that point is missed. This is a real gap, not a rounding error; if you need the page's earliest activity, use `flutter_inappwebview`.

#### Limitations

- **Main frame only** — iframes and Service Workers are not bridged; only the top-level page's JS is hooked.
- **`setOnConsoleMessage` is a console-only fallback** — it doesn't cover errors or network activity, so it isn't the primary path here; the injected bridge JS is what drives all four event types.
- **Replay is unavailable for WebView network entries** — the Network detail view's "Resend" action requires a `sourceDio` instance. WebView traffic isn't captured through Dio, so `sourceDio` is always `null` and Replay correctly stays disabled — the same degradation already used for any entry without a `sourceDio`.

#### Redaction

WebView network entries are ordinary `NetworkEntry` objects flowing through the same buffer as Dio-captured traffic, so they're masked by the exact same [`redactSensitiveData`](#redact-sensitive-headers) rules described above — same masked keys, same opt-out flag, same code path. There is no separate redaction step for WebView traffic to configure or forget.

### Live notification (opt-in)

A continuously-updated system notification can summarise the latest call and the running total. It is **disabled by default** — enable it explicitly:

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  showNetworkNotification: true,
);
```

Once enabled, the inspector requests notification permission for you when it initialises — the host app does not need to add any permission-handling code.

**Notification behaviour**:

- **Android**: appears as a silent heads-up banner (no sound or vibration) when a new API call arrives. The banner animates in and dismisses automatically. Subsequent calls within a 2-second window silently update the notification content without re-alerting. After 2 seconds, the next call triggers another heads-up alert.
- **iOS / macOS**: displays a foreground banner when a new API call arrives, throttled the same way as Android. **This requires one line of setup in your `AppDelegate` — see [Required iOS / macOS setup](#required-ios--macos-setup) below.** Without it, iOS silently suppresses the foreground banner (the entry is still delivered to Notification Center).
- The notification uses a dedicated high-priority Android channel (`flutter_inspector_network_v2`) — if you upgrade from an earlier version, the old notification channel is automatically deleted and will not appear in system settings.

**Tapping the notification opens the dashboard on the Network tab** — this uses the same required `navigatorKey` you already wired up in [Initialize](#initialize), so there is nothing extra to configure:

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey, // required — already set up during Initialize
  showNetworkNotification: true,
);
```

As with any dashboard entry point, the tap only routes if that same key was also passed to your `MaterialApp`.

<details>
<summary>Android setup (required)</summary>

`flutter_local_notifications` relies on Java 8+ APIs, so your app's Gradle module must enable [core library desugaring](https://developer.android.com/studio/write/java8-support#library-desugaring) — this is needed whether or not notifications are enabled, otherwise the app will not build. In `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        multiDexEnabled = true
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Also ensure a notification icon exists at `@mipmap/ic_launcher` (default Flutter apps already have it). On Android 13+ the `POST_NOTIFICATIONS` runtime permission is requested automatically when the inspector initialises.

</details>

#### Required iOS / macOS setup

On iOS / macOS, the user is prompted for notification permission when the inspector initialises. The permission alone is **not** enough to show a banner while your app is in the **foreground**: the system only presents a foreground notification when a `UNUserNotificationCenterDelegate` returns it from `willPresentNotification`.

##### iOS Setup
`FlutterAppDelegate` on iOS already implements that forwarding and conforms to `UNUserNotificationCenterDelegate`, so your host app only needs to assign it in `AppDelegate.swift`:

```swift
import UserNotifications // add this import

// ...inside application(_:didFinishLaunchingWithOptions:), before `return super...`:
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
}
```

##### macOS Setup
Unlike iOS, `FlutterAppDelegate` on macOS does **not** conform to `UNUserNotificationCenterDelegate`. You must explicitly declare compliance and implement the callback in `macos/Runner/AppDelegate.swift`:

```swift
import UserNotifications // add this import

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    super.applicationDidFinishLaunching(notification)
  }

  // Handle foreground notifications on macOS
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .sound])
  }
}
```

See [`example/ios/Runner/AppDelegate.swift`](example/ios/Runner/AppDelegate.swift) and [`example/macos/Runner/AppDelegate.swift`](example/macos/Runner/AppDelegate.swift) for working references. **Without this setup no foreground banner appears on iOS / macOS** — the notification is still delivered silently to Notification Center, and tapping it still works.

If permission is denied or the platform isn't supported, the notifier degrades silently to a no-op — it never crashes your app.

### Log messages

```dart
inspector.log('User signed in', level: LogLevel.info);

inspector.log(
  'Payment failed',
  level: LogLevel.error,
  data: {'orderId': 'A123', 'amount': 4200},
  stackTrace: stackTrace.toString(),
);
```

Available levels: `verbose`, `debug`, `info`, `warning`, `error`.

### Read the merged timeline

The **Console** tab already interleaves logs, network, navigation, and database events on a single timeline (newest first), with a filter chip per source. Error-level logs and failed network calls are given a faint red row background so they're spottable while scrolling a long timeline — warnings keep their orange text but stay un-tinted, so a warning-heavy app doesn't wash the whole list out.

To narrow a long timeline, the tab also offers:

- **Search** — a case-insensitive keyword matched against each entry's readable fields: log messages and stack traces, network URLs, methods and status codes, route names, and database tables and operations.
- **Level chips** — `Verbose`, `Debug`, `Info`, `Warning`. These constrain *log* entries only, so picking one narrows your logs without hiding network, navigation, or database events. There is deliberately no `Error` level chip: it would have hidden failed network calls that `⚡ Errors only` keeps, leaving two chips that both claimed to isolate failures but disagreed on what counts as one.
- **`⚡ Errors only`** — isolates failures across types: `warning`/`error` logs together with failed network calls.
- **Tap to jump back** — while a filter is active, tapping any row clears every filter and scrolls the full timeline to that same entry, so a row you found by searching can be read back in its surrounding context. Long-press still bookmarks the row, filtered or not.

You can also read that same merged view programmatically:

```dart
// All sources, newest first.
final entries = inspector.mergedTimeline();

// Filter to specific sources only.
final networkAndLogs = inspector.mergedTimeline(
  sources: {TimelineSource.network, TimelineSource.log},
);

for (final entry in entries) {
  // displayTime is a shared HH:mm:ss.mmm helper on every TimestampedEntry.
  print('${entry.displayTime}  $entry');
}
```

`mergedTimeline` returns `List<TimestampedEntry>` sorted by `timestamp` descending. Available sources: `TimelineSource.log`, `.network`, `.nav`, `.db` (defaults to all). The entries are the live buffer objects, so a pending network call that later completes is reflected on the next read.

### Readable stack traces

A Flutter stack trace is mostly framework plumbing. Log detail views therefore show a **concise** stack trace by default: each run of consecutive `package:flutter/…` or `dart:…` frames collapses into a single marker, and asynchronous suspensions are labelled explicitly.

```text
#0      CheckoutPage._submit (package:my_app/checkout/checkout_page.dart:88:5)
#1      _rootRunUnary (dart:async/zone.dart:1407:47)
  [... 14 frames of framework internals]
#16     _WidgetsFlutterBinding.handleEvent (package:flutter/src/gestures/binding.dart:475:19)
  <-- async gap -->
#17     CheckoutPage.build.<anonymous closure> (package:my_app/checkout/checkout_page.dart:120:9)
```

The first and last frame of every collapsed run are kept on purpose — that boundary is where control crossed between your code and the framework, which is usually the part worth reading.

A **Show raw / Show concise** button in the detail view switches between the two forms. Exporting is a separate, explicit choice: the share menu offers **Copy concise**, **Copy raw**, **Share concise** and **Share raw**, and each exports the form its menu item names regardless of what is currently on screen — so you can read the concise trace while pasting the raw one into an issue tracker. The stored trace is never modified — normalization is a presentation-layer projection only.

The same helpers are available programmatically:

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

// Collapse framework noise in any stack trace string.
final concise = normalizeStackTrace(rawStackTrace);

// Full plain-text export of a log entry; concise by default.
final text = buildLogPlainText(entry);
final verbatim = buildLogPlainText(entry, isConcise: false);
```

### Where a log came from

Every `LogEntry` records the top-most page at the moment it was written, in its `activeRoute` field — populated automatically, with no wiring on your side. It shows up in the log detail view and in plain-text exports.

```dart
inspector.log('Token refresh failed', level: LogLevel.error);
// entry.activeRoute == 'CheckoutPage'
```

The same error logged from a checkout screen and from a background refresh are usually different bugs; the route is what tells them apart after the fact.

### Uncaught error capture (opt-in)

By default you have to log errors yourself. Enable **uncaught error capture** to have the inspector automatically turn uncaught errors into `error`-level Console logs — no manual `try/catch` needed.

It is **disabled by default** so the package never touches your error handling unless you ask. Enable it on the constructor:

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  captureUncaughtErrors: true,
);
```

This wires three standard Flutter hooks — `FlutterError.onError` (build/layout/paint errors), `PlatformDispatcher.instance.onError` (uncaught async errors, including unawaited `Future` errors), and `ErrorWidget.builder` (which widget failed to build). Together they cover framework, asynchronous and build-time errors without wrapping `runApp` in a custom zone, so there is no `Zone mismatch` to manage.

> **Errors are never swallowed.** Every hook **chains/wraps** your existing handler rather than replacing it: the inspector records the error and then forwards it downstream (your handler, or Flutter's default presentation — debug red screen / release grey screen unchanged). The capture is purely additive.

Captured errors appear as red logs in the **Console** tab. Tap any log that carries a stack trace or structured data to open a detail view with a copyable stack trace and the structured payload, plus copy/share actions.

### App lifecycle markers (opt-in)

Enable **lifecycle capture** to record every foreground/background transition as an `info`-level Console log, so a crash or a stalled request can be read against whether the app was in the foreground at that moment:

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  captureLifecycleEvents: true,
);
```

It is **disabled by default**, and `detach()` removes the observer again. Each transition (`resumed` / `inactive` / `paused` / `detached`, plus `hidden` on Flutter 3.13+) becomes one entry, which the merged Timeline interleaves with network, navigation and database events automatically.

Each entry also names the current top-most page, so repeated home/back switches stay distinguishable in the Console without jumping to the Navigator tab:

```text
App lifecycle: resumed · HomePage (/home)
App lifecycle: paused · CheckoutPage
```

The page is a best-effort replay of the navigation history; when it cannot be resolved (empty history), the suffix is simply omitted.

> The observer is registered with `WidgetsBinding.instance.addObserver`, which appends to a list — your app's own `WidgetsBindingObserver`s keep receiving their callbacks untouched.

### Track navigation

Nothing to do here — routes are tracked automatically once you register `inspector.navigatorObserver` in `navigatorObservers` (see [Initialize](#initialize)). Pushes, pops, and replacements all show up in the Navigator tab.

The Navigator tab offers two views, toggled via chips at the top:

- **Event History**: the raw log of push/pop/replace/remove events (the original behavior).
- **Active Stack**: the current route stack, derived live from the event history and rendered top-first as vertical cards — the topmost card (the current screen) is highlighted. Shows "Empty stack history" when no routes have been recorded yet.

The dashboard's own routes — log/network detail views, table and cell details, the export sheet — are excluded from this history, so investigating a bug never shows up as navigation in your app's route stack. Your app's routes are recorded exactly as before, including unnamed ones.

### Track database operations

Record database operations so you can review them in the dashboard.

```dart
inspector.database(
  DatabaseOperation.update,
  'users',
  affectedRows: 1,
  data: {'query': 'UPDATE users SET name = ? WHERE id = ?'},
);
```

Available operations: `insert`, `update`, `delete`, `query`.

### Browse database tables

You can browse tables and rows directly from the Database tab. By default, operations logged via `inspector.database(...)` are grouped into virtual tables.

To browse real databases (e.g. SQLite, ObjectBox), implement `DatabaseBrowserSource` and register it.

#### SQLite Adapter Example
Here is a complete, copy-pasteable implementation of `DatabaseBrowserSource` for `sqflite`:

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteBrowserSource implements DatabaseBrowserSource {
  SqfliteBrowserSource(this._db, {this.name = 'SQLite database'});

  final Database _db;

  @override
  final String name;

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    final List<Map<String, Object?>> tables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    final List<DatabaseTableInfo> result = [];
    for (final table in tables) {
      final name = table['name'] as String;
      final countResult = await _db.rawQuery('SELECT COUNT(*) as count FROM "$name"');
      final rowCount = Sqflite.firstIntValue(countResult);
      result.add(DatabaseTableInfo(name: name, rowCount: rowCount));
    }
    return result;
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final countResult = await _db.rawQuery('SELECT COUNT(*) as count FROM "$tableName"');
    final totalRows = Sqflite.firstIntValue(countResult) ?? 0;

    final List<Map<String, Object?>> queryResult = await _db.rawQuery(
      'SELECT * FROM "$tableName" LIMIT ? OFFSET ?',
      [limit, offset],
    );

    if (queryResult.isEmpty) {
      final tableInfo = await _db.rawQuery('PRAGMA table_info("$tableName")');
      final columns = tableInfo.map((info) => info['name'] as String).toList();
      return DatabaseTablePage(
        columns: columns,
        rows: const [],
        totalRows: totalRows,
      );
    }

    final columns = queryResult.first.keys.toList();
    final rows = queryResult.map((map) {
      return columns.map((col) => map[col]).toList();
    }).toList();

    return DatabaseTablePage(
      columns: columns,
      rows: rows,
      totalRows: totalRows,
    );
  }
}
```

#### ObjectBox Adapter Example
For ObjectBox, since Box/Entity represents a table and reflection is not available at runtime to convert entities to map, you can register entities manually:

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:objectbox/objectbox.dart';

class ObjectBoxEntityInfo<T> {
  ObjectBoxEntityInfo({
    required this.name,
    required this.box,
    required this.toMap,
  });

  final String name;
  final Box<T> box;
  final Map<String, dynamic> Function(T) toMap;
}

class ObjectBoxBrowserSource implements DatabaseBrowserSource {
  ObjectBoxBrowserSource({
    required this.entities,
    this.name = 'ObjectBox database',
  });

  final List<ObjectBoxEntityInfo> entities;

  @override
  final String name;

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    return entities.map((e) {
      return DatabaseTableInfo(
        name: e.name,
        rowCount: e.box.count(),
      );
    }).toList();
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final entityInfo = entities.firstWhere((e) => e.name == tableName);
    final totalRows = entityInfo.box.count();

    // Query with offset and limit
    final query = entityInfo.box.query().build();
    query.limit = limit;
    query.offset = offset;
    final items = query.find();
    query.close();

    if (items.isEmpty) {
      return DatabaseTablePage(
        columns: [],
        rows: const [],
        totalRows: totalRows,
      );
    }

    final maps = items.map((item) => entityInfo.toMap(item)).toList();
    final columns = maps.first.keys.toList();
    final rows = maps.map((map) => columns.map((col) => map[col]).toList()).toList();

    return DatabaseTablePage(
      columns: columns,
      rows: rows,
      totalRows: totalRows,
    );
  }
}
```

#### Registration
You can register these sources when initializing `FlutterInspector` or dynamically at runtime:

```dart
// At initialization
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  databaseSources: [SqfliteBrowserSource(db)],
);

// Or dynamically
inspector.registerDatabaseSource(SqfliteBrowserSource(db));
```

### 🔑 Browse key-value storage

`SharedPreferences`, `FlutterSecureStorage` and friends hold the state behind
most "stuck on a screen" reports — a stale token, a feature flag left on, a
cache key that never got cleared. The **Storage** tab lists those keys and lets
you edit, delete or wipe them on-device.

The tab only appears once you register at least one `KeyValueBrowserSource`.
As with `DatabaseBrowserSource`, the package ships no implementation and takes
no dependency on any storage plugin — you inject the adapter.

Every write requires an explicit confirmation — edits add a validation step
before it, so a mistyped value is caught before the confirmation appears — and
is recorded as an `info` log in the Console timeline once it succeeds, so a
change made while debugging never becomes a mystery later. A cancelled or
failed write leaves no log — the trail only ever claims what actually landed. Values in that log are masked unless
the host sets `redactSensitiveData: false`, since the log is shareable and a
key-value source may hold tokens.

#### SharedPreferences Adapter Example

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsBrowserSource implements KeyValueBrowserSource {
  SharedPrefsBrowserSource(this._prefs, {this.name = 'SharedPreferences'});

  final SharedPreferences _prefs;

  // Shown in the source selector. Pass a distinct name when registering more
  // than one store, or they are indistinguishable there.
  @override
  final String name;

  @override
  Future<List<KeyValueEntry>> listAll() async {
    return _prefs.getKeys().map((key) {
      final value = _prefs.get(key);
      return KeyValueEntry(key: key, value: value, type: _typeOf(value));
    }).toList();
  }

  @override
  Future<void> setValue(String key, Object? value) async {
    // The value already arrives parsed into the entry's original type.
    final ok = switch (value) {
      final String v => await _prefs.setString(key, v),
      final int v => await _prefs.setInt(key, v),
      final double v => await _prefs.setDouble(key, v),
      final bool v => await _prefs.setBool(key, v),
      final List<String> v => await _prefs.setStringList(key, v),
      _ => false,
    };
    _check(ok, 'write $key');
  }

  @override
  Future<void> remove(String key) async {
    _check(await _prefs.remove(key), 'remove $key');
  }

  @override
  Future<void> clear() async {
    _check(await _prefs.clear(), 'clear');
  }

  // SharedPreferences signals failure by returning false, not by throwing.
  // Swallowing it would let the audit log claim a write that never landed.
  void _check(bool ok, String what) {
    if (!ok) throw StateError('SharedPreferences failed to $what');
  }

  KeyValueType _typeOf(Object? value) => switch (value) {
    int() => KeyValueType.int,
    double() => KeyValueType.double,
    bool() => KeyValueType.bool,
    List<String>() => KeyValueType.stringList,
    _ => KeyValueType.string,
  };
}
```

#### FlutterSecureStorage Adapter Example

Secure storage only holds strings, so every entry is `KeyValueType.string`.

> `readAll()` is not supported on every platform. Let the failure propagate —
> the Storage tab renders it as a retryable error instead of an empty list, so
> "cannot enumerate" is never mistaken for "nothing stored".

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageBrowserSource implements KeyValueBrowserSource {
  SecureStorageBrowserSource(this._storage, {this.name = 'SecureStorage'});

  final FlutterSecureStorage _storage;

  @override
  final String name;

  @override
  Future<List<KeyValueEntry>> listAll() async {
    final all = await _storage.readAll();
    return all.entries
        .map(
          (e) => KeyValueEntry(
            key: e.key,
            value: e.value,
            type: KeyValueType.string,
          ),
        )
        .toList();
  }

  @override
  Future<void> setValue(String key, Object? value) =>
      _storage.write(key: key, value: '$value');

  @override
  Future<void> remove(String key) => _storage.delete(key: key);

  @override
  Future<void> clear() => _storage.deleteAll();
}
```

#### Registration

```dart
// At initialization
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  keyValueSources: [SharedPrefsBrowserSource(prefs)],
);

// Or dynamically
inspector.registerKeyValueSource(SecureStorageBrowserSource(storage));
```

### Export a diagnostic report

Open the dashboard and tap the **share icon** in the app bar. Pick which sources to
include, a time window (last 5m / last 1h / all), and optionally "errors & warnings
only", then hit **Share report** — a Markdown report goes straight to the system
share sheet. Nothing is written to disk.

The report leads with a single chronological **Timeline** that interleaves the log,
network, navigation, and database entries you selected by timestamp (newest first),
so cross-layer causality reads at a glance; the per-source Network / Navigation /
Database detail sections follow below it. The "errors & warnings only" toggle filters
this whole Timeline down to error signals (log errors/warnings plus failed network
calls), leaving those detail sections untouched.

The report inherits your `redactSensitiveData` setting, and its header states
`Redaction: enabled` / `disabled` so whoever receives it knows what was masked.

#### Populating the device / app header (optional)

This package depends on **no** device-info plugin (and never touches `dart:io`, so it
stays WASM-compatible). Without a source, the header degrades to `N/A` and the report
is still produced in full.

To fill it in, add `package_info_plus` and `device_info_plus` **to your own app**, then
implement `DiagnosticInfoSource`:

```dart
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Note: This example is mobile-only due to its dart:io Platform usage.
// It will not compile on Web/WASM.
class AppDiagnosticInfoSource implements DiagnosticInfoSource {
  @override
  Future<DiagnosticInfo> collect() async {
    final pkg = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();

    String? deviceModel;
    String? osVersion;

    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      deviceModel = ios.utsname.machine;
      osVersion = 'iOS ${ios.systemVersion}';
    } else if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      deviceModel = '${android.manufacturer} ${android.model}';
      osVersion = 'Android ${android.version.release}';
    }

    return DiagnosticInfo(
      appVersion: '${pkg.version}+${pkg.buildNumber}',
      deviceModel: deviceModel,
      osVersion: osVersion,
    );
  }
}
```

Then pass it in:

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  diagnosticInfoSource: AppDiagnosticInfoSource(),
);
```

## 🕹️ Example

A complete, runnable integration lives in the [`example/`](example/) directory:

```sh
cd example
flutter run
```

## 📄 License

This project is licensed under the terms described in the [LICENSE](LICENSE) file.
