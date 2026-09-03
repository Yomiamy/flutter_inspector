# Flutter Inspector Kit - 整體架構概覽 (Overview)

> 「差勁的程式員只擔心程式碼，優秀的程式員關心資料結構。」 —— Linus Torvalds

`flutter_inspector_kit` 是一個輕量、低干涉且實用主義的 Flutter 開發期調試工具。它將 Console 日誌、網路請求（HTTP）、頁面導航（Navigator）以及資料庫操作（Database）集成在單一的懸浮按鈕（FAB）與全螢幕儀表板中。

---

## 🏗️ 核心架構分層

本套件遵循「資料驅動」與「低侵入性」的設計原則，將架構劃分為四個主要層次：

```text
  ┌────────────────────────────────────────────────────────────┐
  │                 表現層 (Presentation Layer)                │
  │  [DashboardModal]    [InspectorFab]    [ConsoleTab (Merged)]│
  │  [ExportReportSheet]  [Theme Tokens (lib/src/ui/theme/)]   │
  └─────────────────────────────┬──────────────────────────────┘
                                │ 讀取與操作
                                ▼
  ┌────────────────────────────────────────────────────────────┐
  │                 核心調試引擎 (Core Engine)                 │
  │   [FlutterInspector]  [InspectorRegistry]  [RingBuffer]    │
  │   [InspectorOverlayManager]                                │
  └─────────────────────────────┬──────────────────────────────┘
                                │ 持有與快取
                                ▼
  ┌────────────────────────────────────────────────────────────┐
  │                 領域模型層 (Domain Models)                 │
  │               [TimestampedEntry] (抽象介面)                │
  │   [LogEntry]  [NetworkEntry]  [NavigatorEntry]  [DBEntry]  │
  │   [DiagnosticInfo]  [NetworkOrigin]                        │
  └─────────────────────────────▲──────────────────────────────┘
                                │ 結構化寫入
                                │
  ┌─────────────────────────────┴──────────────────────────────┐
  │            資料擷取層 (Collectors / Interceptors)          │
  │ [DioInterceptor] [NavigatorObserver] [UncaughtErrorHandler]│
  │ [LifecycleHandler]                                         │
  │ [WebViewBridgeAdapter] <── postMessage ── 頁內注入 JS bridge │
  └────────────────────────────────────────────────────────────┘
```

### 1. 基礎核心層 (Core Engine)
- **`FlutterInspector`**：全域單例管理器（Facade）。負責協調各子系統、掛載控制台 UI、接收各類數據輸入，並委託各專屬 Inspector 儲存數據。提供 `slowRequestThreshold` 配置參數（預設 `const Duration(seconds: 2)`，並具有非負數驗證），用於定義慢速網路請求之判定門檻（`entry.duration >= slowRequestThreshold`）。
- **`InspectorRegistry`**：中央緩衝註冊表，集中持有與管理四個領域的專屬 Inspector。
- **`RingBuffer`**：最核心的底層資料結構，為一個固定容量的 FIFO 快取。提供就地更替（`replace`）與刪除最舊數據的功能，是所有資料儲存的基石。
- **`InspectorOverlayManager`**：獨立的核心懸浮 Overlay 生命週期管理器。負責 FAB 飄移按鈕在 Overlay 上的掛載與卸載。它與 Facade（`FlutterInspector`）完全解耦，僅藉由建構子傳入的 `onFabTap` 回呼來傳遞點擊事件，不逆向依賴任何特定的 Inspector 業務。

### 2. 領域模型層 (Domain Models)
- 採用 **Immutable (不可變)** 的設計模式。
- **`TimestampedEntry`**：定義混合時序軸（Merged Timeline）排序契約之抽象介面，包含 `timestamp`、`displayTime` 欄位與 `TimelineSource` 來源標記。
- 具體實體包括：`LogEntry`、`NetworkEntry`、`NavigatorEntry` 與 `DatabaseEntry`。
- **`NetworkOrigin`**：網路請求的來源列舉（`dio` / `webview`）。`NetworkEntry` 以第一級欄位 `origin`（預設 `dio`）與 `pageUrl`（WebView 請求的 `location.href`）標記 provenance——顯式欄位而非依賴 `sourceDio == null` 推斷，因為 `WeakReference<Dio>` 被 GC 後兩種來源將無法區分。
- **`DiagnosticInfo`**：裝置與應用程式的元數據模型（如應用版本、裝置型號、系統版本等）。為了確保平台自適應與 WASM 相容性，其所有欄位皆為 nullable，並在報告中安全地以 `N/A` 降級顯示，避免 host 無法提供資訊時導致流程中斷。
- **`DiagnosticInfoSource`**：Host 提供裝置與 App 元數據的抽象資料源介面。Host 實作此介面後，經由建構子注入 `FlutterInspector` 中。

### 3. 數據擷取層 (Collectors / Interceptors)
- **`DioInterceptor`** (`FlutterInspectorDioInterceptor`)：攔截 Dio 請求與響應，處理 pending 狀態更新，並支持安全請求重發（Replay）。
- **`NavigatorObserver`** (`FlutterInspectorNavigatorObserver`)：自動監聽路由變化，並安全解析頁面 Widget 類型。
- **`UncaughtErrorHandler`**：獨立類別，專職掛載與鏈接未捕捉的例外。它透過建構子接收 `onLog` 回呼函數，在呼叫 `attach()` 時安全地將錯誤鉤子鏈接（chain/wrap）至 `FlutterError.onError`、`PlatformDispatcher.instance.onError` 與 `ErrorWidget.builder`。此類別無 `FlutterInspector` 的逆向依賴，保證了職責單一與高品味的模組獨立性。針對同一次 build 崩潰會同時觸發 `FlutterError.onError` 與 `ErrorWidget.builder`（兩者收到**同一個** `FlutterErrorDetails` 物件）的情況，`_logFlutterError` 以 object-identity 去重（`identical` 比對上一筆已記錄的 details），確保 Console 只記錄一次（PR #96）。
- **`LifecycleHandler`**：獨立類別，專職把 app 前景/背景切換（`resumed`/`inactive`/`paused`/`detached`，及 Flutter 3.13+ 的 `hidden`）記成 `LogLevel.info` 的 `LogEntry`（opt-in `captureLifecycleEvents`，default off）。與 `UncaughtErrorHandler` 同形——透過建構子接收 `onLog` 回呼、無 `FlutterInspector` 逆向依賴。message 尾巴附加當前 top-most page（`FlutterInspector._currentTopPageLabel()` 走 `NavigatorStackResolver` best-effort 重播，推不出來時省略而非猜測），讓 home/back 頻繁切換仍能在 Console 一眼分辨發生在哪一頁。與錯誤鉤子不同，此 observer **可乾淨 teardown**：`detach()` 會 `removeObserver(this)`——因為 `WidgetsBindingObserver` 是一個 list（移除自己不影響宿主），而非 `FlutterError.onError` 那種單一 slot。同一旗標下還覆寫 `didHaveMemoryPressure()`，把 OS 回報的記憶體壓力記成 `LogLevel.warning`（非 info——這是 OOM/LMK 前導信號，要能被既有 warning/error 過濾撈起來，不能沉在資訊流裡）。**共用 `captureLifecycleEvents` 而非另開旗標**：兩者是同一個 observer 上的 callback、共用同一組 attach/detach 生命週期（PR #155）。
- **`OperationLogSource`**：將資料庫操作日誌轉換為虛擬表格，以配合資料庫瀏覽器展示。
- **`WebViewBridgeAdapter`** + **`inspectorWebViewBridgeJs`**：WebView 觀測橋。宿主把 `inspectorWebViewBridgeJs`（可注入 JS payload）掛進自己的 WebView（`webview_flutter` 或 `flutter_inappwebview` 皆可，套件零相依），頁內的 `console.*`、JS error、`fetch`/`XHR` 事件經 `JavaScriptChannel`（webview_flutter）/ `addJavaScriptHandler`（flutter_inappwebview）以 JSON 送回，adapter 翻譯為既有 `LogEntry` / `NetworkEntry` 後透過公開 API 推入 Core——與 Dio interceptor 完全同形的「翻譯器」，不持有 buffer、不做 UI。

### 4. 表現層 (Presentation Layer) & 工具類
- **`InspectorFab`**：支援拖曳的安全區域內懸浮按鈕。
- **`DashboardModal`**：全螢幕控制台儀表板，封裝了四大 Tab（Console, Network, Navigator, Database）與自訂頁。其中 `ConsoleTab` 與 `NetworkTab` 整合慢速網路請求偵測，當請求耗時 `entry.duration >= slowRequestThreshold` 時於列表項目（`_EntryTile` / `_NetworkEntryRow`）顯示 **`🐢 SLOW`** 警示 Badge；`NetworkTab` 頂部摘要列（`_ErrorSummaryBanner`）亦同步彙整慢速請求數量與時間門檻（如 `| 🐢 N slow (>Xs)`）。
- **`MagicalTap`**：靜默連擊偵測元件，可在隱藏 FAB 時喚醒控制台。
- **`ExportReportSheet`**：展示層的診斷報告導出與分享 Bottom Sheet。提供 Include 篩選、時間區間與 errors-only 選項，並整合了 async try-catch、`shareText` 及 clipboard fallback 的容錯分享流程。
- **`DiagnosticReport`** (`buildDiagnosticReport`)：位於無狀態工具層的純粹且同步的 Markdown 報告產生器（Builder）。與 Flutter UI 完全解耦，不依賴 `BuildContext` 與 `dart:io`。
- **集中化設計 Tokens 系統 (`lib/src/ui/theme/`)**：
  - **`theme.dart`**：Barrel 檔案，統一導出所有 Token 類別。
  - **`theme_color.dart`** (`ThemeColor`)：定義調色盤常數。並提供 `statusColor` 方法，根據 HTTP status code 返回調試用語意配色。
  - **`theme_padding.dart`** (`ThemePadding`)：定義 EdgeInsets Tokens（`paddingAll8`, `paddingAll12`, `paddingAll16`, `paddingH8`, `paddingH16V8`），內部基於 `ThemeSize.space*` 常數建構。
  - **`theme_size.dart`** (`ThemeSize`)：核心尺寸 Tokens 抽象類別（`abstract final class ThemeSize`），整合並統一管理間距（`space2`..`space16`）、圓角（`radius4`, `radius8`）與尺寸（`size16`..`size140`）常數。
  - **`theme_textstyle.dart`** (`ThemeTextStyle` / `ThemeFontSize`)：文字字型與粗細 Tokens，並包含 `ThemeFontSize`（`fontSize10`, `fontSize11`, `fontSize12`）字體大小常數。

---

## 🛠️ 架構設計原則與「好品味」

### 1. 平台自適應與 WASM 相容性 (Conditional Exports)
在網路通知 (`NetworkNotifier`) 與文字分享 (`ShareText`) 模組中，為了解決 Native（依賴 `dart:io` 與三方套件）與 Web（WASM 相容）之間的平台差異：
- 採用 **條件匯出 (Conditional Exports)** 技術：
  - Web 端自動切換為 no-op stub，或直接調用 Web 原生的 API（例如 Web Share API）。
  - Native 端則載入對應的插件（例如 `flutter_local_notifications`、`share_plus`）。
- **結果**：完全阻斷 `dart:io` 傳遞式匯入進入 Web 編譯鏈，保持 Flutter 網頁端 WASM 構建的乾淨相容。

### 2. 弱引用與防洩漏設計 (WeakReference)
在 `NetworkEntry` 中，重發（Replay）功能需要調用發起請求的 `Dio` 實例：
- **致命風險**：如果直接持有 `Dio` 實例強引用，隨著 RingBuffer 達到上限並拋棄舊 Entry，這些已失效的 `Dio` 將無法被垃圾回收，造成嚴重的記憶體洩漏。
- **Linus 式解法**：在 `NetworkEntry` 中使用 `WeakReference<Dio>`。這是一個暫時性的運行期引用，只在 Replay 時嘗試獲取。此欄位被刻意排除在 `==`、`hashCode` 與所有導出序列化之外，確保安全、乾淨且零洩漏。

### 3. 無害的錯誤鉤子 (Never Break Host App)
在捕獲 uncaught exceptions 時：
- `UncaughtErrorHandler` 嚴格包裹現有 Host 處理程序（`FlutterError.onError` 等）。
- 寫入日誌的邏輯完全置於 `try-catch` 中，不論日誌儲存是否失敗，**都必須確保在 finally 中將錯誤原樣轉發回下游**。
- **原則**：我們的職責是輔助調試，絕不能因為套件自身的崩潰或錯誤導致主 App 的行為改變。
- **同一原則、相反的 teardown 決定**：`LifecycleHandler` 的 `didChangeAppLifecycleState` 與 `didHaveMemoryPressure` 同樣以 `try-catch` 隔離，供頁面標籤的 `topPageLabel` callback 拋錯也不逃逸。記憶體壓力這側的 guard 另有一條硬理由：本套件 SDK 下限（Flutter >=3.10.0）的 `handleMemoryPressure()` 逐一走訪 observer 且**無** per-observer try-catch（該保護 3.44.0 才加入），逸出的例外會中斷整條廣播、波及排在本 handler 之後的每個 observer——**不能依賴新版才有的保護**。但它與錯誤鉤子的 teardown 策略**刻意相反**——錯誤鉤子是單一 slot（`FlutterError.onError` 只有一個），還原舊值會覆蓋宿主後裝的 handler，故不 teardown；而 `WidgetsBindingObserver` 是 binding 上的一個 list，`removeObserver(this)` 只移除自己這個實例，不碰宿主的 observer，故 `detach()` 會乾淨移除。**兩個相反的決定各有正確理由，不是前後不一致**。

### 4. 敵意輸入防護 (WebView Bridge Hardening)
WebView 頁面內容是**不可信來源**，且頁面可繞過注入腳本直接對 channel 送任意 payload：
- **`handleMessage` 永不拋出**：整條訊息路由包在單一 `try-catch` 內，malformed JSON、未知型別、超出 `DateTime` 範圍的時間戳一律靜默丟棄。
- **雙重大小上限**：JS 端於源頭截斷（`MAX_CHARS`，附 `truncated` 標記）；Dart 端在 `jsonDecode` 前再以 256KB 上限擋下繞過注入腳本的超大訊息——UI isolate 永不解析無界輸入。
- **redaction 無旁門**：WebView 網路事件與 native 走同一組顯示/匯出 formatter，遮罩行為與 `redactSensitiveData` opt-out 逐字節一致。
