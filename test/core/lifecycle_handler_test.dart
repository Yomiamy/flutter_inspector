import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/src/core/lifecycle_handler.dart';
import 'package:flutter_inspector_kit/src/models/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LifecycleHandler? handler;

  tearDown(() {
    handler?.detach();
    handler = null;
  });

  test('attach: state change produces one info log with the state name', () {
    var callCount = 0;
    LogLevel? lastLevel;
    String? lastMessage;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
        lastLevel = level;
        lastMessage = message;
      },
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(callCount, 1);
    expect(lastLevel, LogLevel.info);
    expect(lastMessage, contains('resumed'));
  });

  test('all five states are recorded', () {
    final messages = <String>[];
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        messages.add(message);
      },
    );
    handler = h;
    h.attach();

    const states = [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.hidden,
    ];
    for (final state in states) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
    }

    expect(messages.length, 5);
    for (var i = 0; i < states.length; i++) {
      expect(messages[i], contains(states[i].name));
    }
  });

  test('idempotent: attach twice records a state change once', () {
    var callCount = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler = h;
    h.attach();
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(callCount, 1);
  });

  test('detach: no further logs after detach', () {
    var callCount = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    h.detach();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    expect(callCount, 1);
    expect(() => h.detach(), returnsNormally);
  });

  test('not attached: state change produces no log', () {
    var callCount = 0;
    handler = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );

    // 刻意不呼叫 attach()。
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(callCount, 0);
  });

  test('guard: onLog throws does not propagate', () {
    var hostCalled = false;
    final hostObserver = _HostObserver(() => hostCalled = true);

    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        throw StateError('onLog failed');
      },
    );
    handler = h;

    // 註冊順序刻意讓 handler 排在 hostObserver 之前：binding 的廣播迴圈沒有
    // per-observer try-catch，handler 若讓例外逃逸，迴圈會在 hostObserver
    // 之前中斷。倒過來註冊會讓 hostCalled 恆為 true，測不到 guard 是否存在。
    h.attach();
    WidgetsBinding.instance.addObserver(hostObserver);
    addTearDown(() => WidgetsBinding.instance.removeObserver(hostObserver));

    expect(
      () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
      returnsNormally,
    );
    expect(hostCalled, isTrue);
  });

  test('topPageLabel: non-empty label is appended after " · "', () {
    String? lastMessage;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        lastMessage = message;
      },
      topPageLabel: () => 'HomePage (/home)',
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    expect(lastMessage, 'App lifecycle: resumed · HomePage (/home)');
  });

  test('topPageLabel: null and empty both omit the suffix', () {
    final messages = <String>[];
    final labels = <String?>['', null];
    var i = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        messages.add(message);
      },
      topPageLabel: () => labels[i++],
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );

    // 空字串與 null 都不加 " · " 尾巴，退回純狀態訊息。
    expect(messages, ['App lifecycle: paused', 'App lifecycle: resumed']);
  });

  test('memory pressure: produces one warning log', () {
    var callCount = 0;
    LogLevel? lastLevel;
    String? lastMessage;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
        lastLevel = level;
        lastMessage = message;
      },
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleMemoryPressure();

    expect(callCount, 1);
    // warning 而非 info：這是 OOM/LMK 前導信號，必須能被既有的
    // warning/error 過濾與高亮機制撈起來，不能沉在資訊流裡。
    expect(lastLevel, LogLevel.warning);
    expect(lastMessage, contains('Memory pressure'));
  });

  test('memory pressure: non-empty label is appended after " · "', () {
    String? lastMessage;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        lastMessage = message;
      },
      topPageLabel: () => 'HomePage (/home)',
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleMemoryPressure();

    expect(lastMessage, 'Memory pressure · HomePage (/home)');
  });

  test('memory pressure: null and empty label both omit the suffix', () {
    final messages = <String>[];
    final labels = <String?>['', null];
    var i = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        messages.add(message);
      },
      topPageLabel: () => labels[i++],
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleMemoryPressure();
    WidgetsBinding.instance.handleMemoryPressure();

    expect(messages, ['Memory pressure', 'Memory pressure']);
  });

  test('memory pressure: not attached produces no log', () {
    var callCount = 0;
    handler = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );

    // 刻意不呼叫 attach()。
    WidgetsBinding.instance.handleMemoryPressure();

    expect(callCount, 0);
  });

  test('memory pressure: no further logs after detach', () {
    var callCount = 0;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        callCount++;
      },
    );
    handler = h;
    h.attach();

    WidgetsBinding.instance.handleMemoryPressure();
    h.detach();
    WidgetsBinding.instance.handleMemoryPressure();

    expect(callCount, 1);
  });

  test('memory pressure: a throwing topPageLabel is caught by the guard', () {
    var logged = false;
    var hostCalled = false;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        logged = true;
      },
      topPageLabel: () => throw StateError('resolve failed'),
    );
    handler = h;
    h.attach();

    // 🔴 斷言兩件事，因為 binding 的行為隨 SDK 版本而異：
    //
    // - Flutter >=3.10.0（本套件的 SDK 下限）到 3.41.x：
    //   handleMemoryPressure() 逐一呼叫 observer，**沒有** per-observer
    //   try-catch。例外逃逸會中斷廣播，排在本 handler 之後註冊的 observer
    //   全部收不到——與 didChangeAppLifecycleState 完全同型，所以沿用上面
    //   `guard: onLog throws` 的 _HostObserver 手法（註冊順序同樣刻意讓
    //   handler 排在 hostObserver 之前）。
    // - Flutter 3.44.0 起：binding 補上 per-observer try-catch，此時
    //   hostCalled 不論有無 guard 都為 true，該斷言失去鑑別力；改由
    //   FlutterError 有沒有收到回報來分辨（沒 guard 時 binding 會把例外
    //   轉成 FlutterErrorDetails 報上去）。
    //
    // 兩個斷言並存，整個支援範圍內才都真的驗得到 guard 存在。
    final hostObserver = _HostObserver(() => hostCalled = true);
    WidgetsBinding.instance.addObserver(hostObserver);
    addTearDown(() => WidgetsBinding.instance.removeObserver(hostObserver));

    final captured = <FlutterErrorDetails>[];
    final saved = FlutterError.onError;
    FlutterError.onError = captured.add;
    addTearDown(() => FlutterError.onError = saved);

    expect(
      () => WidgetsBinding.instance.handleMemoryPressure(),
      returnsNormally,
    );

    expect(hostCalled, isTrue);
    expect(captured, isEmpty);
    expect(logged, isFalse);
  });

  test('topPageLabel: a throwing supplier is caught, does not propagate', () {
    var logged = false;
    final h = LifecycleHandler(
      onLog: (message, {level = LogLevel.info, stackTrace, data}) {
        logged = true;
      },
      topPageLabel: () => throw StateError('resolve failed'),
    );
    handler = h;
    h.attach();

    expect(
      () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
      returnsNormally,
    );
    // supplier 拋錯落入既有 try-catch，該次 log 被吞（與 onLog 拋錯同路徑），
    // 但不向宿主傳播。
    expect(logged, isFalse);
  });
}

/// Minimal host observer, proving [LifecycleHandler] never crowds out the
/// other observers registered on the binding.
///
/// Both callbacks report through the same hook: each test registers this after
/// the handler and triggers only one of the two broadcasts, so whichever fires
/// is the one under test.
class _HostObserver with WidgetsBindingObserver {
  _HostObserver(this.onStateChange);

  final VoidCallback onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChange();
  }

  @override
  void didHaveMemoryPressure() {
    onStateChange();
  }
}
