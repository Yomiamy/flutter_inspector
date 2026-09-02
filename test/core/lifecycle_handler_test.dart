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

  test(
    'memory pressure: a throwing topPageLabel never reaches FlutterError',
    () {
      var logged = false;
      final h = LifecycleHandler(
        onLog: (message, {level = LogLevel.info, stackTrace, data}) {
          logged = true;
        },
        topPageLabel: () => throw StateError('resolve failed'),
      );
      handler = h;
      h.attach();

      // 🔴 這個斷言的選擇是實測出來的，不是想當然耳：
      //
      // 1. 不能用上面 `guard: onLog throws` 的 _HostObserver 手法——binding 的
      //    handleMemoryPressure() 為每個 observer 各自包了 try-catch
      //    （didChangeAppLifecycleState 的廣播迴圈則沒有），例外不會中斷廣播。
      // 2. 也不能只斷言 returnsNormally + 不產生 log——binding 那層 try-catch
      //    會把例外接走，所以拿掉本類別的 guard 這兩個斷言照樣通過（已用
      //    mutation test 證實：移除 try-catch 後 15 個測試全綠）。
      //
      // 唯一能分辨「guard 在不在」的可觀察差異是 FlutterError：沒有 guard 時，
      // binding 會把例外轉成 FlutterErrorDetails 報上去；有 guard 時不會。
      final captured = <FlutterErrorDetails>[];
      final saved = FlutterError.onError;
      FlutterError.onError = captured.add;
      addTearDown(() => FlutterError.onError = saved);

      WidgetsBinding.instance.handleMemoryPressure();

      expect(captured, isEmpty);
      expect(logged, isFalse);
    },
  );

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
class _HostObserver with WidgetsBindingObserver {
  _HostObserver(this.onStateChange);

  final VoidCallback onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChange();
  }
}
