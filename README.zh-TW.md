# 🔍 Flutter Inspector

[![pub package](https://img.shields.io/pub/v/flutter_inspector_kit.svg)](https://pub.dev/packages/flutter_inspector_kit)
[![platform](https://img.shields.io/badge/platform-flutter-blue.svg)](https://pub.dev/packages/flutter_inspector_kit)

**Language / 語言**: [English](README.md) | [繁體中文](README.zh-TW.md)

嵌入 App 內的多合一偵錯疊層工具，為 Flutter App 提供 logs、network、navigation 與 database 的檢視，全部收攏在單一統一 API 之後。

## 📦 功能

| 功能 | 說明 | 使用情境範例 |
|---|---|---|
| 🪵 **Console** | 擷取五種嚴重程度（`verbose` / `debug` / `info` / `warning` / `error`）的 log，可選帶結構化資料與 stack trace | QA 回報「點結帳沒反應」——打開 Console，在時間軸上一眼看到紅色錯誤項目；點進去查看結構化錯誤細節、response body 與完整 stack trace，理解到底哪裡出錯 |
| 🧵 **Merged Timeline** | Console 分頁把 logs、network、navigation 與 database 事件交錯排在同一條依時間戳排序的時間軸上，並提供各來源的 filter chip；error 等級的 log 與失敗的 network 呼叫會帶淡紅底色，捲動長時間軸時一眼就能認出 | 延續結帳案例——把來源 chip 切到「All」，沿時間軸往回捲，檢視那個拿到 401 的請求：看 `Authorization` header 帶了什麼 token、送了哪些參數，和後端預期比對，精準定位伺服器為何拒絕——全程不用切分頁或手動比對時間戳 |
| 📡 **Network** | 透過 Dio 攔截 HTTP 流量；檢視結構化的 request/response 細節；依 URL、method 或 status 搜尋／篩選；以 cURL 分享 | 某個頁面整片空白——打開 Network 分頁發現 API 回了錯誤，所以根本沒資料可顯示；點進去檢視 request 參數與 response body，再複製成可直接執行的 cURL 指令，貼進 bug ticket 讓後端團隊重現 |
| 🔄 **Network Replay** | 用原始的 Dio 實例重送一個已擷取的請求（沿用相同 headers、base URL、interceptors）；重送的項目會自動標記 | 在裝置上重觸一個失敗的 API 呼叫，驗證伺服器端的 hotfix，不必重啟 App 或重走一遍使用者流程 |
| 🚨 **Structured Network Errors** | 失敗的請求會顯示 **Exception Details** 區塊，區分傳輸層失敗（裝置離線／DNS／逾時）與伺服器端錯誤（4xx/5xx），並附可複製的 stack trace | 立刻分辨「Failed」到底是裝置斷線還是伺服器回了 500——QA 期間不必再靠猜 |
| 📊 **Error Aggregation Summary** | Network 分頁會顯示一個可收合的橫幅，依 status code（傳輸層失敗則依 error type）將失敗／錯誤的請求分組，附各組計數與時間範圍；點某一組即把呼叫列表篩選到只剩該錯誤 | 頁面被幾十筆失敗呼叫灌爆——瞄一眼摘要橫幅看到「12× 401」「3× timeout」，點 401 那組就把那些呼叫獨立出來，不必在整份列表裡捲來捲去 |
| 🩺 **Diagnostic Report** | 匯出單一份 Markdown 報告——裝置／App 標頭、當前 route stack，以及 logs / network / navigation / database 各區段——可依時間窗（5m / 1h / all）、來源與可選的僅錯誤開關篩選；直接送進分享面板，不寫入磁碟 | QA 重現 bug 後，不用截四個分頁的圖再手打 OS 版本，按一次 Export 就把完整報告貼進 Jira ticket |
| 🌐 **WebView Inline Debugging** | 把 WebView 自身的 `console.*`、`window.onerror`/`unhandledrejection` 與 `fetch`/`XMLHttpRequest` 活動橋接進與原生 log、Dio 流量共用的同一個 Console 與 Network 分頁——零相依，自行把你的 `webview_flutter` 或 `flutter_inappwebview` 接到 `WebViewBridgeAdapter` | 混合式頁面出狀況，你分不清 bug 在 Flutter 還是內嵌網頁——直接在 Console/Network 內看到 WebView 的 JS 錯誤與 `fetch`/`XHR` 呼叫，並依 origin 標記，立刻知道該修哪一側，不必把 Chrome DevTools 掛到 WebView 上 |
| 🛡️ **Sensitive-Data Redaction** | 預設即安全——敏感 headers（`Authorization`、`Cookie`、`Set-Cookie`、`X-Api-Key`）在每一條分享／匯出路徑上都會被遮罩 | 放心把 network log 分享給隊友或附進 Jira ticket，不會外洩 token 或 session cookie |
| 🧭 **Navigator** | 自動追蹤 route 的 push、pop 與 replace；可在 **Event History**（原始 log）與 **Active Stack**（即時 route-stack 視覺化）之間切換。dashboard 自身的 route 會被濾掉，查 bug 不會反過來污染這份歷史 | 驗證 deep-link 路由、確認 back-stack 正確性，或在 QA 走查時診斷「使用者為什麼會落到這個畫面？」——而且因為點開詳情頁不會寫進歷史，翻查十分鐘後看到的 stack 仍然是你 App 的，不是你自己查問題的軌跡 |
| 🗄️ **Database** | 記錄 insert / update / delete / query 操作，含受影響筆數與 payload；透過可插拔的 `DatabaseBrowserSource` 瀏覽真實資料表（已提供 SQLite / ObjectBox adapter） | 驗證「儲存」動作是否真的寫進預期的資料列；在裝置上直接瀏覽本地 SQLite 資料表，不必把 `.db` 檔拉出來 |
| 🧵 **可讀的 Stack Trace** | 框架內部 frame 摺疊為 `[... N frames of framework internals]`（保留頭尾邊界 frame），非同步中斷點顯示為 `<-- async gap -->`；raw／concise 可一鍵切換，複製與分享匯出當下顯示的那一種 | 一個未捕捉錯誤吐出 40 行 `package:flutter/…`，把真正重要的兩行自家程式碼淹沒——concise 版本讓你不用捲動就看到自己的 frame，需要完整堆疊時再一鍵切回 raw |
| 🧭 **Log Route 脈絡** | 每筆 log 都記錄寫入當下最上層的頁面，顯示於詳情頁與匯出內容 | 同樣一則「token refresh failed」，發生在結帳頁與發生在背景刷新是兩回事——記錄下來的 route 讓你事後讀時間軸時分得出來 |
| 🛑 **Uncaught Error Capture** *(需 opt-in)* | 透過三個 Flutter hook（build/layout/paint、async、`ErrorWidget`）自動把未捕捉的錯誤轉成 `error` 等級的 Console log；串接既有 handler——絕不吞錯 | 某個未 await 的 `Future` 在第三方套件深處拋錯——附近完全沒有 `try/catch`。Uncaught error capture 自動連同完整 stack trace 記錄下來，不用任何手動埋點就出現在 Console |
| ⏱️ **App Lifecycle Markers** *(需 opt-in)* | 把每一次 `resumed` / `inactive` / `paused` / `detached` 轉換記錄成 `info` 等級的 Console log，各自標註當下最上層的頁面，並交錯進合併時間軸 | 一批請求以 timeout 失敗，在辦公桌前卻怎麼都重現不了——翻時間軸，`App lifecycle: paused · CheckoutPage` 這筆就卡在它們前面，代表使用者切走了、OS 把網路凍結，根本不是後端的問題。反過來也好用：確認「回到前景就刷新」真的有觸發，而且是在哪一頁觸發 |
| 🔔 **Live Notification** *(需 opt-in)* | 一則系統通知摘要最新一筆 API 呼叫與累計總數；點一下直接跳到 Network 分頁 | 在 App 內導覽時即時監看 API 流量——不必一直開著 dashboard；也適合驗證每個操作的 API 呼叫數是否合理（例如單一頁面載入就觸發數十筆呼叫，暗示有重複請求） |
| 👆 **Magical Tap & Floating Button** | 用隱藏的多次點擊手勢，或可拖曳的 App 內 FAB 打開 dashboard | 內嵌進 release build 作為隱藏的診斷入口——當 QA 或使用者遇到問題，當場觸發 inspector 做初步錯誤分流，不必重建 debug 版或翻原始碼 |
| 🧩 **Custom Tab** | 透過 `FlutterInspector(customTab: ..., customTabTitle: ...)` 注入你自己的 widget 作為第 5 個 dashboard 分頁——與 Console / Network / Navigator / Database 並列 | 把 App 專屬的偵錯工具擺在內建 inspector 旁邊——feature-flag 開關面板、當前 auth/session 狀態、或「清快取」按鈕——讓團隊的臨時診斷全集中在一處，不必另開一個 debug 畫面 |

## 📱 螢幕截圖

|Home|Console|Network|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/home.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/console.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network.png?raw=true"/>|

|Network Detail|Navigator|Uncaught Error|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network_detail.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/navigator.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/uncaught_error.png?raw=true"/>|

|Database Browse|||
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/database_browse.png?raw=true"/>|||

## 🪚 使用方式

### 加入 pubspec.yaml

```yaml
dependencies:
  flutter_inspector_kit: ^2.4.0
```

接著執行 `flutter pub get`。

### 初始化

建立單一個共用的 `FlutterInspector` 實例並接進你的 App。`navigatorKey` 是**必填**的——inspector 透過它路由到 dashboard——所以請建立一把 key，傳給 inspector，並把**同一把 key** 也傳給你的 `MaterialApp`。接著註冊 navigator observer 以追蹤 route，並用 `FlutterInspectorMagicalTap` 包住你的 App，讓隱藏手勢能從任何地方打開 dashboard。

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

// 1. 一把 key，inspector 與 MaterialApp 共用。
final navigatorKey = GlobalKey<NavigatorState>();

final inspector = FlutterInspector(
  // 必填：dashboard 透過這把 key 開啟。
  navigatorKey: navigatorKey,
  // 選填：設定判定為「🐢 SLOW」的門檻（預設 2 秒）
  slowRequestThreshold: const Duration(seconds: 3),
);

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 2. 同一把 key——少了這行，dashboard 就沒有可開啟的 context。
      navigatorKey: navigatorKey,
      // 3. 追蹤導航事件
      navigatorObservers: [inspector.navigatorObserver],
      // 4. 隱藏手勢可從任何地方打開 dashboard
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

就這樣？對，就這樣。

> **兩個步驟缺一不可。** `navigatorKey` 在建構子上是編譯期強制的，但「有沒有傳給 `MaterialApp`」編譯器檢查不到。漏了第二步，這把 key 永遠拿不到已掛載的 context，`openDashboard()` 就會靜默無反應——不論是 magical tap、浮動按鈕，還是點通知都一樣。

### Floating button

偏好看得見的觸發方式？在第一幀建立後 attach inspector，顯示一顆可拖曳、點了會打開 dashboard 的浮動按鈕。

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    inspector.attach(context: context);
  });
}
```

用 `inspector.detach()` 即可再次移除。

### 加入自訂分頁

注入你自己的 widget 作為第 5 個 dashboard 分頁，與內建的 Console / Network / Navigator / Database 分頁並列。用它來呈現 App 專屬的診斷內容——feature-flag 面板、當前 auth 狀態、「清快取」按鈕等等。

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  customTab: const MyDebugPanel(),
  customTabTitle: 'Flags', // defaults to 'Custom'
);
```

該 widget 會在其分頁首次顯示時才 lazy 建立，可以是任何 Flutter widget——包括自帶 controller 的 stateful widget。

### 記錄 network 請求

#### 搭配 Dio

把 interceptor 加進你的 `Dio` 實例，每一筆 request/response 就會自動被擷取。傳入 `sourceDio` 實例即可在 Network 詳情頁啟用 **Resend (Replay)** 功能。

```dart
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));
```

##### 多個 Dio 實例

若你的 App 使用多個 `Dio` 實例（例如 `authDio` 給需要認證的 API 呼叫、`publicDio` 給公開資源），請在每個實例上都註冊 interceptor，並確實把各自對應的實例當作 `sourceDio` 傳入：

```dart
// Authenticated API client
final authDio = Dio();
authDio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: authDio));

// Public API client
final publicDio = Dio();
publicDio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: publicDio));
```

這能保證在 Network 詳情頁重送請求時，用的是完全相同的 `Dio` 實例，維持正確的 baseUrl、interceptors 與認證狀態。

#### 搭配其他 HTTP client

自行建立 `NetworkEntry` 並傳入：

```dart
inspector.logNetwork(entry);
```

若要顯示一個進行中、稍後才 resolve 的請求，先記錄 pending 項目，等 response 回來後再用 `replaces` 記錄完成的項目，讓它就地更新而非重複：

```dart
final pending = inspector.logNetwork(NetworkEntry(method: 'GET', url: url));
// ...after the response arrives:
inspector.logNetwork(completedEntry, replaces: pending);
```

### 在 Network 分頁裡

- **搜尋與篩選**：依 URL、method 或 status code 篩選呼叫列表（不分大小寫）；method 與 status（`2xx`/`3xx`/`4xx`/`5xx`/`Failed`）chip 可再進一步縮小範圍。
- **錯誤摘要橫幅**：呼叫列表上方一個可收合的橫幅，依 status code（傳輸層失敗則依 error type——離線/逾時/DNS）將失敗／錯誤的請求分組，顯示各組計數與首見/末見時間範圍。點某張分組卡即把列表篩選到只剩該錯誤；再點一次即清除篩選。
- **呼叫細節**：點任一筆呼叫進入結構化檢視——General（method、URL、附色彩標示的 status、duration、request/response 大小）、Query Parameters、Headers 與 JSON 美化過的 body。被截斷的 body 會清楚標示。失敗的請求會顯示一個 **Exception Details** 區塊，區分傳輸層失敗與伺服器端錯誤，並附可複製的 stack trace。
- **分享**：把呼叫複製為可執行的 `cURL` 指令、把完整細節複製為文字，或開啟系統分享面板（原生透過 `share_plus`、web 透過瀏覽器 Web Share API——不可用時退回剪貼簿）。
- **Replay / Resend**：對於 interceptor 有提供 `sourceDio` 而擷取的請求，你可以在詳情頁觸發「Resend」動作，用同一個 Dio client（帶著相同 headers、base URL 與 interceptors）在本地重送請求。重送的請求會自動以帶「Replay」標籤的新項目出現。

### 遮罩敏感 headers

Network 詳情頁的每一條分享／匯出路徑——複製為 `cURL`、複製為文字、以及系統分享面板——**預設都會遮罩敏感 headers**，讓 secret 絕不外洩到剪貼簿、分享面板或截圖。被遮罩的 key 是 `Authorization`、`Cookie`、`Set-Cookie` 與 `X-Api-Key`（不分大小寫比對）；其值會被替換成 `••••`。

這由 `redactSensitiveData` 這個建構參數控制，預設為 `true`。以下兩種配置擇一使用。

預設即安全——敏感 headers 在分享／匯出的輸出中會被遮罩：

```dart
final inspector = FlutterInspector(navigatorKey: navigatorKey);
```

或選擇退出（例如需要原始值的內部建置版）：

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  redactSensitiveData: false,
);
```

這個 flag 只影響分享／匯出的文字——dashboard 內即時顯示的 headers 永遠是真實值。

### WebView inline debugging

把 WebView 自身的 `console.*`、`window.onerror`/`unhandledrejection` 與 `fetch`/`XMLHttpRequest` 活動橋接進與原生 log、Dio 流量共用的同一個 Console 與 Network 分頁——多一個事件來源，不是另一套系統。本套件維持零相依：你自備 WebView 套件（`webview_flutter` 或 `flutter_inappwebview`），並自行把它接到 `WebViewBridgeAdapter`。

每種整合都遵循相同的三個步驟：

1. 建立 `final adapter = WebViewBridgeAdapter(inspector);`——一個透過 `inspector.log` / `inspector.logNetwork` 把橋接訊息轉成既有 `LogEntry` / `NetworkEntry` 物件的翻譯器。它不持有 buffer，自身也不做 redaction。
2. 把你的 WebView 套件的 channel/handler（以 `kWebViewBridgeChannelName` 常數命名，即 `'FlutterInspectorBridge'`）接到呼叫 `adapter.handleMessage(rawMessageString)`。
3. 把 `inspectorWebViewBridgeJs` payload 注入頁面——它會 hook `console.*`、`window.onerror`、`unhandledrejection`、`fetch` 與 `XMLHttpRequest`，並將每個事件以一個 JSON envelope 透過 channel 回傳。

#### 搭配 `webview_flutter`

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

可運作的 demo：[`example/lib/demos/webview_demo.dart`](example/lib/demos/webview_demo.dart)。

#### 搭配 `flutter_inappwebview`

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

可運作的 demo：[`example/lib/demos/inappwebview_demo.dart`](example/lib/demos/inappwebview_demo.dart)——其頁面會在 document 載入期間就觸發一筆 log，證明 document-start 注入能捕捉到 `webview_flutter` 接線方式會漏掉的活動。

#### Provenance：把 WebView 流量與原生流量區分開

每一筆被橋接的請求都會被 first-class 地標記：`NetworkEntry.origin` 為 `NetworkOrigin.webview`（原生 Dio 流量預設為 `NetworkOrigin.dio`），而 `NetworkEntry.pageUrl` 帶著發出請求頁面的 `location.href`。兩者都會以 **Origin** / **Page URL** 列出現在 Network 詳情頁。被橋接的 log 項目則在 `LogEntry.data`（`origin` / `pageUrl`）帶著相同標記，可在 log 詳情頁的 Data 區段看到。

#### 注入時機：搞清楚各套件能與不能捕捉什麼

這兩個套件的注入點確實不同，而這會改變你看到的內容：

- **`flutter_inappwebview`** 的 `UserScript` 搭配 `AT_DOCUMENT_START` 會在頁面自身的 script 之前執行，因此能捕捉到頁面最早期初始化期間觸發的 log/error/request。
- **`webview_flutter`** 的 `runJavaScript` 只會從 `onPageStarted` 執行，而該時機在導覽已經開始*之後*才觸發——在那之前的任何 `console.*` / error / fetch 活動都會漏掉。這是個真實的缺口，不是可忽略的誤差；若你需要頁面最早期的活動，請用 `flutter_inappwebview`。

#### 限制

- **僅主 frame**——iframe 與 Service Worker 不會被橋接；只有頂層頁面的 JS 會被 hook。
- **`setOnConsoleMessage` 只是 console 專用的退路**——它不涵蓋 error 或 network 活動，所以不是這裡的主要路徑；驅動全部四種事件類型的是被注入的 bridge JS。
- **WebView network 項目無法 Replay**——Network 詳情頁的「Resend」動作需要一個 `sourceDio` 實例。WebView 流量並非透過 Dio 擷取，所以 `sourceDio` 永遠是 `null`，Replay 也正確地維持停用——與任何沒有 `sourceDio` 的項目採用相同的降級處理。

#### Redaction

WebView network 項目是流經與 Dio 擷取流量相同 buffer 的一般 `NetworkEntry` 物件，因此會被完全相同的 [`redactSensitiveData`](#遮罩敏感-headers) 規則遮罩——相同的遮罩 key、相同的 opt-out flag、相同的程式碼路徑。沒有另一套針對 WebView 流量、需要另外設定或可能忘記設定的 redaction 步驟。

### Live notification（需 opt-in）

一則持續更新的系統通知可摘要最新一筆呼叫與累計總數。它**預設停用**——請明確啟用：

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  showNetworkNotification: true,
);
```

一旦啟用，inspector 會在初始化時替你請求通知權限——host App 不需要加任何權限處理程式碼。

**通知行為**：

- **Android**：新的 API 呼叫抵達時以無聲 heads-up 橫幅出現（無聲音或震動）。橫幅會滑入並自動消失。2 秒窗內的後續呼叫會無聲更新通知內容而不再次提示。2 秒後，下一筆呼叫會再觸發一次 heads-up 提示。
- **iOS / macOS**：新的 API 呼叫抵達時顯示前景橫幅，節流方式與 Android 相同。**這需要在你的 `AppDelegate` 加一行設定——見下方 [必要的 iOS / macOS 設定](#必要的-ios--macos-設定)。** 少了它，iOS 會靜默地抑制前景橫幅（該項目仍會送達 Notification Center）。
- 通知使用專屬的高優先權 Android channel（`flutter_inspector_network_v2`）——若你從較早的版本升級，舊的通知 channel 會自動被刪除，不會出現在系統設定中。

**點通知就會打開 dashboard 並停在 Network 分頁**——這用的是你在[初始化](#初始化)時已經接好的那把必填 `navigatorKey`，不需要額外設定：

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey, // 必填——初始化時已設定
  showNetworkNotification: true,
);
```

與其他 dashboard 入口一樣，只有在同一把 key 也傳給了 `MaterialApp` 時，這個點擊才會真的路由過去。

<details>
<summary>Android 設定（必要）</summary>

`flutter_local_notifications` 依賴 Java 8+ 的 API，所以你 App 的 Gradle module 必須啟用 [core library desugaring](https://developer.android.com/studio/write/java8-support#library-desugaring)——無論是否啟用通知都需要，否則 App 無法 build。在 `android/app/build.gradle.kts` 中：

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

同時確保 `@mipmap/ic_launcher` 存在一個通知圖示（預設 Flutter App 本來就有）。在 Android 13+ 上，`POST_NOTIFICATIONS` runtime 權限會在 inspector 初始化時自動請求。

</details>

#### 必要的 iOS / macOS 設定

在 iOS / macOS 上，使用者會在 inspector 初始化時被提示通知權限。光有權限**不足以**在你 App 處於**前景**時顯示橫幅：系統只有在 `UNUserNotificationCenterDelegate` 從 `willPresentNotification` 回傳通知時才會呈現前景通知。

##### iOS 設定
iOS 上的 `FlutterAppDelegate` 已經實作了該轉發並符合 `UNUserNotificationCenterDelegate`，所以你的 host App 只需要在 `AppDelegate.swift` 中指派它：

```swift
import UserNotifications // add this import

// ...inside application(_:didFinishLaunchingWithOptions:), before `return super...`:
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
}
```

##### macOS 設定
與 iOS 不同，macOS 上的 `FlutterAppDelegate` **不**符合 `UNUserNotificationCenterDelegate`。你必須在 `macos/Runner/AppDelegate.swift` 中明確宣告符合並實作 callback：

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

可運作的參考見 [`example/ios/Runner/AppDelegate.swift`](example/ios/Runner/AppDelegate.swift) 與 [`example/macos/Runner/AppDelegate.swift`](example/macos/Runner/AppDelegate.swift)。**少了這項設定，iOS / macOS 上不會出現前景橫幅**——通知仍會靜默送達 Notification Center，點它也仍可運作。

若權限被拒或平台不支援，notifier 會靜默降級為 no-op——絕不會讓你的 App crash。

### 記錄 log 訊息

```dart
inspector.log('User signed in', level: LogLevel.info);

inspector.log(
  'Payment failed',
  level: LogLevel.error,
  data: {'orderId': 'A123', 'amount': 4200},
  stackTrace: stackTrace.toString(),
);
```

可用的等級：`verbose`、`debug`、`info`、`warning`、`error`。

### 讀取合併後的時間軸

**Console** 分頁本身就已把 logs、network、navigation 與 database 事件交錯排在單一時間軸上（最新在前），並為每個來源提供一個 filter chip。error 等級的 log 與失敗的 network 呼叫會被加上淡紅色的列底色，捲動長時間軸時容易辨識——warning 維持原本的橘色文字但不上底色，避免 warning 一多就把整份列表洗成一片紅。

要在長時間軸中縮小範圍，此分頁另外提供：

- **搜尋** — 不分大小寫的關鍵字，比對每筆項目可讀的欄位：log 訊息與 stack trace、network 的 URL／method／status code、route 名稱，以及 database 的資料表與操作。
- **等級 chips** — `Verbose`、`Debug`、`Info`、`Warning`。這些**只**約束 log 項目，所以選了某個等級不會連帶把 network、navigation、database 事件一起藏起來。這裡刻意沒有 `Error` 等級 chip：它會把 `⚡ Errors only` 保留的失敗 network 呼叫濾掉，變成兩個都宣稱「隔離失敗」卻對「什麼算失敗」各執一詞的 chip。
- **`⚡ Errors only`** — 跨型別隔離失敗項目：`warning`／`error` 等級的 log，加上失敗的 network 呼叫。
- **點擊跳回** — 篩選啟用時，點任一列會清掉所有篩選條件，並把完整時間軸捲動到該筆項目，讓你把搜尋找到的那一列放回前後脈絡中閱讀。長按仍然是加書籤，篩選中也一樣可用。

你也可以用程式化方式讀取這份相同的合併檢視：

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

`mergedTimeline` 回傳依 `timestamp` 遞減排序的 `List<TimestampedEntry>`。可用的來源：`TimelineSource.log`、`.network`、`.nav`、`.db`（預設全部）。這些項目是即時的 buffer 物件，所以一個 pending 的 network 呼叫在稍後完成時，會在下一次讀取時反映出來。

### 可讀的 stack trace

Flutter 的 stack trace 大半是框架內部的管線。因此 log 詳情頁預設顯示**精簡（concise）**版本：連續的 `package:flutter/…` 或 `dart:…` frame 會摺疊成單一標記，非同步中斷點也會明確標示出來。

```text
#0      CheckoutPage._submit (package:my_app/checkout/checkout_page.dart:88:5)
#1      _rootRunUnary (dart:async/zone.dart:1407:47)
  [... 14 frames of framework internals]
#16     _WidgetsFlutterBinding.handleEvent (package:flutter/src/gestures/binding.dart:475:19)
  <-- async gap -->
#17     CheckoutPage.build.<anonymous closure> (package:my_app/checkout/checkout_page.dart:120:9)
```

每段摺疊區塊的**頭尾 frame 會刻意保留**——那裡正是控制權在你的程式碼與框架之間交界的位置，通常也是最值得讀的一段。

詳情頁的 **Show raw／Show concise** 按鈕可在兩種形式間切換，而複製與分享會匯出**當下畫面上的那一種**，所以貼到 ticket 的 stack trace 與正在討論的內容一致。原始 stack trace 從不被修改——正規化純粹是呈現層的投影。

同一個 helper 也可以直接在程式中使用：

```dart
// 摺疊任一 stack trace 字串中的框架噪聲。
final concise = normalizeStackTrace(rawStackTrace);

// log entry 的完整純文字匯出；預設為 concise。
final text = buildLogPlainText(entry);
final verbatim = buildLogPlainText(entry, isConcise: false);
```

### log 來自哪一頁

每筆 `LogEntry` 都會記錄寫入當下最上層的頁面，存放於 `activeRoute` 欄位——自動填入，不需要你這端做任何接線。它會顯示在 log 詳情頁與純文字匯出中。

```dart
inspector.log('Token refresh failed', level: LogLevel.error);
// entry.activeRoute == 'CheckoutPage'
```

同一則錯誤發生在結帳頁與發生在背景刷新，通常是兩個不同的 bug；事後回頭讀時間軸時，route 就是分辨兩者的依據。

### Uncaught error capture（需 opt-in）

預設情況下你得自己記錄錯誤。啟用 **uncaught error capture** 就能讓 inspector 自動把未捕捉的錯誤轉成 `error` 等級的 Console log——不需要手動 `try/catch`。

它**預設停用**，所以除非你主動要求，本套件絕不碰你的錯誤處理。在建構參數上啟用：

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  captureUncaughtErrors: true,
);
```

這會接上三個標準 Flutter hook——`FlutterError.onError`（build/layout/paint 錯誤）、`PlatformDispatcher.instance.onError`（未捕捉的 async 錯誤，包含未 await 的 `Future` 錯誤）與 `ErrorWidget.builder`（哪個 widget build 失敗）。三者合起來涵蓋 framework、非同步與 build-time 錯誤，且不需要把 `runApp` 包進自訂 zone，所以沒有 `Zone mismatch` 要處理。

> **錯誤絕不會被吞掉。** 每個 hook 都是**串接/包住**你既有的 handler 而非取代它：inspector 記錄錯誤後就往下游轉發（你的 handler，或 Flutter 的預設呈現——debug 紅屏／release 灰屏維持不變）。這個擷取純粹是加法。

被擷取的錯誤會以紅色 log 出現在 **Console** 分頁。點任何帶 stack trace 或結構化資料的 log 即可打開詳情頁，內含可複製的 stack trace 與結構化 payload，並附複製／分享動作。

### App 生命週期標記（需 opt-in）

啟用 **lifecycle capture**，把每一次前景／背景轉換記錄成 `info` 等級的 Console log，這樣崩潰或卡住的請求就能對照當下 App 是否在前景來判讀：

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  captureLifecycleEvents: true,
);
```

它**預設停用**，而 `detach()` 會把 observer 移除。每一次轉換（`resumed` / `inactive` / `paused` / `detached`，Flutter 3.13+ 另有 `hidden`）都會成為一筆項目，並自動被合併時間軸與 network、navigation、database 事件交錯排列。

每筆項目還會標註當前最上層的頁面，讓反覆的 home／back 切換在 Console 裡仍可區分，不必跳到 Navigator 分頁比對：

```text
App lifecycle: resumed · HomePage (/home)
App lifecycle: paused · CheckoutPage
```

頁面名稱是依導覽歷史盡力還原的結果；無法解析時（歷史為空）就單純省略該後綴。

> 這個 observer 是用 `WidgetsBinding.instance.addObserver` 註冊的，它是往清單追加——你 App 自己的 `WidgetsBindingObserver` 仍會照常收到各自的 callback。

### 追蹤 navigation

這裡不用做任何事——只要你把 `inspector.navigatorObserver` 註冊進 `navigatorObservers`（見 [初始化](#初始化)），route 就會被自動追蹤。push、pop 與 replace 全都會出現在 Navigator 分頁。

Navigator 分頁提供兩種檢視，透過頂端的 chip 切換：

- **Event History**：push/pop/replace/remove 事件的原始 log（原本的行為）。
- **Active Stack**：當前的 route stack，從 event history 即時推導，以垂直卡片由上而下呈現——最上方的卡片（當前畫面）會被標亮。尚未記錄任何 route 時顯示「Empty stack history」。

dashboard 自己開啟的 route——log／network 詳情頁、資料表與 cell 詳情、匯出面板——都不會被計入這份歷史，所以查 bug 的動作不會反過來污染你 App 的 route stack。你 App 自己的 route 記錄方式完全不變，包含未命名的 route。

### 追蹤 database 操作

記錄 database 操作，以便在 dashboard 中回顧。

```dart
inspector.database(
  DatabaseOperation.update,
  'users',
  affectedRows: 1,
  data: {'query': 'UPDATE users SET name = ? WHERE id = ?'},
);
```

可用的操作：`insert`、`update`、`delete`、`query`。

### 瀏覽 database 資料表

你可以直接從 Database 分頁瀏覽資料表與資料列。預設情況下，透過 `inspector.database(...)` 記錄的操作會被歸類成虛擬資料表。

要瀏覽真實資料庫（例如 SQLite、ObjectBox），實作 `DatabaseBrowserSource` 並註冊它。

#### SQLite Adapter 範例
以下是給 `sqflite` 的 `DatabaseBrowserSource` 完整、可直接複製貼上的實作：

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

#### ObjectBox Adapter 範例
對 ObjectBox 而言，由於 Box/Entity 代表一張資料表、且 runtime 沒有 reflection 可把 entity 轉成 map，你可以手動註冊 entity：

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

#### 註冊
你可以在初始化 `FlutterInspector` 時註冊這些 source，也可以在 runtime 動態註冊：

```dart
// At initialization
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  databaseSources: [SqfliteBrowserSource(db)],
);

// Or dynamically
inspector.registerDatabaseSource(SqfliteBrowserSource(db));
```

### 匯出診斷報告

打開 dashboard，點 app bar 上的**分享圖示**。挑選要納入哪些來源、一個時間窗（last 5m / last 1h / all），以及可選的「errors & warnings only」，然後按 **Share report**——一份 Markdown 報告就直接送進系統分享面板。不寫入磁碟。

報告以單一份依時間排序的 **Timeline** 開頭，把你選取的 log、network、navigation 與 database 項目依時間戳交錯（最新在前），讓跨層的因果關係一眼可讀；各來源的 Network / Navigation / Database 詳情區段接在其下。「errors & warnings only」開關會把整份 Timeline 篩選到只剩錯誤訊號（log 的 error/warning 加上失敗的 network 呼叫），而那些詳情區段不受影響。

報告會沿用你的 `redactSensitiveData` 設定，其標頭會標明 `Redaction: enabled` / `disabled`，讓收到報告的人知道遮罩了什麼。

#### 填入裝置／App 標頭（可選）

本套件**不**依賴任何 device-info plugin（也從不碰 `dart:io`，因此維持 WASM 相容）。沒有 source 時，標頭會降級為 `N/A`，報告仍完整產出。

要填入它，把 `package_info_plus` 與 `device_info_plus` 加進**你自己的 App**，然後實作 `DiagnosticInfoSource`：

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

接著把它傳入：

```dart
final inspector = FlutterInspector(
  navigatorKey: navigatorKey,
  diagnosticInfoSource: AppDiagnosticInfoSource(),
);
```

## 🕹️ 範例

完整、可執行的整合位於 [`example/`](example/) 目錄：

```sh
cd example
flutter run
```

## 📄 授權

本專案依 [LICENSE](LICENSE) 檔案所述條款授權。
