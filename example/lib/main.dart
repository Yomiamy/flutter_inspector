import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

import 'demos/inappwebview_demo.dart';
import 'demos/network_demo.dart';
import 'demos/objectbox_demo.dart';
import 'demos/shared_prefs_demo.dart';
import 'demos/sqlite_demo.dart';
import 'demos/webview_demo.dart';

// Enable the live system notification summarising network calls (opt-in).
// On Android this requires a notification icon + (Android 13+) the
// POST_NOTIFICATIONS permission; on iOS/macOS the user is prompted on init.
late final FlutterInspector inspector;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  inspector = FlutterInspector(
    showNetworkNotification: true,
    navigatorKey: navigatorKey,
    // Capture uncaught errors into the Console as LogLevel.error logs (opt-in).
    // This wires the three standard hooks — FlutterError.onError,
    // PlatformDispatcher.instance.onError and ErrorWidget.builder — which
    // together cover framework, asynchronous and build-time errors. No zone is
    // involved, so there is no Zone mismatch to worry about.
    captureUncaughtErrors: true,
    // Also raise a throttled system notification for uncaught errors (opt-in).
    // Requires captureUncaughtErrors above: without the hooks there is no
    // event to notify about. Uses its own notification id, channel and
    // throttler, so a crash alert never replaces the network summary — but a
    // burst of errors re-alerts at most once per throttle window. Native
    // platforms only; the web build is a no-op.
    showCrashNotification: true,
    // Record app foreground/background transitions as info logs (opt-in).
    // Each entry names the current top page (e.g. "resumed · HomePage"), so
    // the nearest lifecycle entry above a crash tells you both whether the app
    // was in the foreground and which page it was on.
    captureLifecycleEvents: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Flutter Inspector Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      navigatorObservers: [inspector.navigatorObserver],
      builder: (context, child) {
        return FlutterInspectorMagicalTap(
          onTap: () {
            final context = navigatorKey.currentContext;

            if (context == null) return;

            inspector.openDashboard();
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MyHomePage(title: 'Flutter Inspector Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  late final NetworkDemo _networkDemo;
  late final SqliteDemo _sqliteDemo;
  late final ObjectBoxDemo _objectBoxDemo;
  late final SharedPrefsDemo _sharedPrefsDemo;
  late final WebViewDemo _webViewDemo;
  late final InAppWebViewDemo _inAppWebViewDemo;

  @override
  void initState() {
    super.initState();
    _networkDemo = NetworkDemo(inspector);
    _sqliteDemo = SqliteDemo(inspector);
    _objectBoxDemo = ObjectBoxDemo(inspector);
    _sharedPrefsDemo = SharedPrefsDemo(inspector);
    _webViewDemo = WebViewDemo(inspector);
    _inAppWebViewDemo = InAppWebViewDemo(inspector);

    // Show FAB after frame builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inspector.attach(context: context);
    });
  }

  @override
  void dispose() {
    _sqliteDemo.dispose();
    _objectBoxDemo.dispose();
    super.dispose();
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
    inspector.log('Counter incremented to $_counter', level: LogLevel.info);
    inspector.database(
      DatabaseOperation.update,
      'counters',
      affectedRows: 1,
      data: {'query': 'UPDATE counters SET val = $_counter'},
    );
  }

  /// Runs a demo's seed step and surfaces its status message, if any.
  Future<void> _runSeed(Future<String?> Function() seed) async {
    final message = await seed();
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              const Text('You have pushed the button this many times:'),
              Text(
                '$_counter',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _networkDemo.makeRequest,
                child: const Text('Make Network Request'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _networkDemo.makeSlowRequest,
                child: const Text('Make Slow Network Request (3s)'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _runSeed(_sqliteDemo.seed),
                child: const Text('Seed SQLite Demo'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _runSeed(_objectBoxDemo.seed),
                child: const Text('Seed ObjectBox Demo'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _runSeed(_sharedPrefsDemo.seed),
                child: const Text('Seed SharedPreferences Demo'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _webViewDemo.open(context),
                child: const Text('Open WebView Demo'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _inAppWebViewDemo.open(context),
                child: const Text('Open InAppWebView Demo'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Second Page')),
                        body: const Center(child: Text('Second Page')),
                      ),
                    ),
                  );
                },
                child: const Text('Push New Route'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                // Fires the same observer broadcast the OS triggers on real
                // memory pressure (Android onTrimMemory, iOS
                // didReceiveMemoryWarning). With captureLifecycleEvents
                // enabled it lands on the timeline as a warning entry.
                onPressed: () => WidgetsBinding.instance.handleMemoryPressure(),
                child: const Text('Simulate Memory Pressure'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                // Throws an uncaught async error. With captureUncaughtErrors
                // enabled it is caught by PlatformDispatcher.instance.onError and
                // surfaces as a red error log in the Console tab — tap it to
                // expand the stack trace.
                onPressed: () => Future<void>.error(
                  StateError('Demo: uncaught async error'),
                  StackTrace.current,
                ),
                child: const Text('Throw Uncaught Error'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _BrokenWidgetPage(),
                    ),
                  );
                },
                child: const Text('Trigger Widget Build Error'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BrokenWidgetPage extends StatelessWidget {
  const _BrokenWidgetPage();

  @override
  Widget build(BuildContext context) {
    // Intentionally throw inside build method to trigger FlutterError.onError & ErrorWidget.builder
    throw FlutterError('Demo: Widget build error triggered inside build()');
  }
}
