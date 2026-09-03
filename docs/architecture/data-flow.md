# Flutter Inspector Kit - 數據流與功能流程 (Data Flow)

> 「好的程式碼沒有特殊情況。」 —— Linus Torvalds

本文件詳細剖析本套件內四大核心功能的運作流程、狀態移轉與數據傳遞軌跡，並涵蓋「App 生命週期標記」、「診斷報告導出與分享」、「懸浮按鈕與 Overlay 生命週期管理」與「WebView 事件橋接」等核心流程。

---

## 1. 網路請求攔截與更新流程 (HTTP Interception & Completion)

在網路請求的生命週期中，數據被低干涉地捕獲兩次：發出請求時（用於即時顯示 pending 狀態）與響應/失敗時（更新狀態碼、時長與 Body）。同時，完成的請求會與設定的慢請求閾值（`slowRequestThreshold`）比對，以提供 UI 層視覺標示與統計。

### 數據流時序圖

網絡請求純淨寫入 `NetworkInspector` 的環形快取中，不產生任何日誌鏡射。

```text
  Dio Client (App)            DioInterceptor               FlutterInspector & Registry                 UI (NetworkTab / ConsoleTab)
       │                           │                                    │                                           │
       │─── 1. 發起 Request ──────>│                                    │                                           │
       │                           │─── 2. 建立 Incomplete Entry ──────>│                                           │
       │                           │    (記錄 startTime)                │                                           │
       │                           │<── 3. 返回 pendingEntry ───────────│                                           │
       │                           │                                    │                                           │
       │                           │─── 4. 存入 options.extra ──────────│                                           │
       │<── 5. 放行 Request ───────│                                    │                                           │
       │                           │                                    │                                           │
       ~   ( 網絡傳輸中... )        ~                                    ~                                           ~
       │                           │                                    │                                           │
       │─── 6. 響應/失敗 ─────────>│                                    │                                           │
       │                           │─── 7. 從 options.extra 取得 pending│                                           │
       │                           │       與 startTime，計算 duration  │                                           │
       │                           │       (DateTime.now - startTime)   │                                           │
       │                           │─── 8. 原地更替為 Completed Entry ─>│                                           │
       │                           │    (含 duration, 經 RingBuffer)    │                                           │
       │                           │                                    │                                           │
       │                           │─── 9. [選用] 發送平台自適應通知 ──>│                                           │
       │                           │    (經 AlertThrottler 靜默限制)    │                                           │
       │<── 10. 返回 Response ─────│                                    │                                           │
       │                           │                                    │                                           │
       │                           │                                    │─── 11. 傳遞 entries & slowRequestThreshold ─>│
       │                           │                                    │                                           │
       │                           │                                    │                                           ├── 12. 動態評估 duration >= threshold
       │                           │                                    │                                           │    ├─ 繪製 🐢 SLOW 標籤 (Row Entry)
       │                           │                                    │                                           │    └─ 彙整 🐢 slowCount (Summary Banner)
```

### 關鍵細節：慢請求閾值配置與耗時判定 (Slow Request Threshold & Duration Evaluation)
1. **閾值配置與驗證**：`FlutterInspector` 提供了 `slowRequestThreshold` 參數（型態 `Duration`，預設值為 `Duration(seconds: 2)`），用於判定網路請求是否過慢。在建構時會檢查 `slowRequestThreshold.isNegative`，若傳入負數則拋出 `ArgumentError.value(slowRequestThreshold, 'slowRequestThreshold', 'must not be negative')` 阻斷不合法配置。
2. **耗時精確計算**：`FlutterInspectorDioInterceptor` 於 `onRequest` 階段記錄發起時間（在 `options.extra` 注入 `_inspector_start_time = DateTime.now()`），並於 `onResponse` 及 `onError` 觸發時計算 `duration = DateTime.now().difference(startTime)`，寫入 Completed `NetworkEntry`。
3. **純淨模型解耦 (Model Decoupling)**：`NetworkEntry` 本身僅儲存完成時計算的原始 round-trip 時長 `duration`（`Duration?`），不將 `isSlow` 布林值寫死於資料模型中。此解耦設計確保數據模型之純潔性，即使閾值動態變更亦無須異動已儲存的條目。

### 關鍵細節：UI 慢請求視覺標記與摘要橫幅 (UI Slow Request Presentation & Summary Banner)
1. **動態判定標準**：UI 層統一以 `entry.duration != null && entry.duration! >= slowRequestThreshold` 作為慢請求判定條件。
2. **列表列慢標籤 (`🐢 SLOW` Badge)**：在 `NetworkTab`（`_EntryTile`）與 `ConsoleTab`（`_NetworkEntryRow`）的請求列表項中，若請求符合慢請求條件，會在右側 trailing 區域（chevron 箭頭前）渲染橘色（`ThemeColor.colorFF9800`，15% 透明背景與 1px 邊框）`🐢 SLOW` 徽章。
3. **效能與錯誤摘要橫幅 (`_ErrorSummaryBanner`)**：
   - 橫幅會在包含錯誤群組或慢請求（`groups.isNotEmpty || slowCount > 0`）時顯示。
   - 動態計算滿足 `entry.duration! >= slowRequestThreshold` 的慢請求數量 `slowCount` 與秒數閾值 `thresholdSec = (slowRequestThreshold.inMilliseconds / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')`。
   - 當同時存在網路錯誤與慢請求時，橫幅標題與折疊狀態附加 `| 🐢 {slowCount} slow (>{thresholdSec}s)`；當無網路錯誤但存在慢請求時，橫幅標題顯示 `🐢 {slowCount} slow requests (>{thresholdSec}s)`。

### 關鍵細節：請求重發 (Replay Request)
在 `NetworkDetailView` 中點擊「重發」按鈕時：
1. **安全性檢查**：必須滿足「請求已完成（`entry.isComplete == true`）」、「來源 `Dio` 未被回收（`sourceDio.target != null`）」且「Body 未被截斷（`isRequestTruncated == false`）」。
2. **防死循環標記**：重發的請求會自動注入 `_inspector_is_replay: true` 到 `options.extra` 中。這可以使新請求在被攔截器捕獲時，標記為 `isReplay = true`，防止開發者混淆。

---

## 2. 🧵 跨層混合時序軸的設計與歸併排序 (Merged Timeline)

在事件發生時，擷取器純淨寫入各自的 Buffer。在 UI 渲染時，依據需求動態排序呈現。

```text
  【 1. 事件發生 】
  ┌──────────────────────────────────────────────────┐
  │  事件源 (Dio/Navigator/DB)                        │
  └────────┬─────────────────────────────────────────┘
           │ (純淨寫入結構化數據，無複製鏡射，零贅餘)
           ▼
  ┌──────────────────────────────────────────────────┐
  │  各自 RingBuffer (Network / Navigator / DB / Log) │
  └────────┬─────────────────────────────────────────┘
           │
           │ 【 2. UI 渲染期 】
           │ (呼叫 mergedTimeline(sources))
           ▼
  ┌──────────────────────────────────────────────────┐
  │  InspectorRegistry 核心                           │
  │  → 讀取所有啟用源 (Log + Network + Nav + DB)      │
  │  → 拍扁 (Flatten) 所有數據                        │
  │  → 依 timestamp 進行記憶體中降序 Merge-Sort       │
  └────────┬─────────────────────────────────────────┘
           │ (回傳 List<TimestampedEntry>)
           ▼
  ┌──────────────────────────────────────────────────┐
  │  UI ConsoleTab                                   │
  │  → 依 Entry 實際類型分派渲染                       │
  │  → Network 類型 Row 點擊可跳轉 DetailView 交互   │
  └──────────────────────────────────────────────────┘
```

- **統一排序契約**：所有日誌、網絡、導航與資料庫 Entry 皆實作了 `TimestampedEntry` 介面，藉由單一 `timestamp` 進行記憶體中降序 `sort` 歸併。
- **類型分派渲染**：時序軸行依 `entry is NetworkEntry` 等類型動態分派 UI 樣式。

---

## 3. 路由導航監聽流程 (Navigation Observing)

透過將 `FlutterInspectorNavigatorObserver` 註冊至 `MaterialApp.navigatorObservers`，套件能實時記錄路由事件。

```text
  ┌────────────────────────────────────────┐
  │          App 發生路由導航變化          │
  └───────────────────┬────────────────────┘
                      │ (didPush / didPop / didReplace / didRemove)
                      ▼
  ┌────────────────────────────────────────┐
  │     NavigatorObserver 監聽攔截         │
  └───────────────────┬────────────────────┘
                      │
                      ▼
            是否為控制台頁面？
            (flutter_inspector_dashboard)
           ╱        ╲
        (Yes)       (No)
         ╱            ╲
  ┌───────────┐   ┌────────────────────────┐
  │ 忽略，不記 │   │   安全解析 Widget 類型  │
  │ 防止自循環│   └───────────┬────────────┘
  └───────────┘               │
                              ▼
                       路由設定類型？
                      ╱              ╲
                (settings is Page)  (其他)
                  ╱                      ╲
  ┌───────────────────────┐      Route 是否有 builder？
  │ 獲取 page.child 的    │     ╱                      ╲
  │ runtimeType           │   (Yes)                   (No)
  └────────┬────────────┘   ╱                          ╲
             │       ┌───────────────┐          ┌──────────────────┐
             │       │ 安全呼叫      │          │ 降級使用路由名稱  │
             │       │ builder 獲取  │          │ settings.name    │
             │       │ runtimeType   │          │ (或 'Unknown')   │
             │       └───────┬───────┘          └────────┬─────────┘
             ▼               ▼                           ▼
  ┌────────────────────────────────────────────────────────────────┐
  │                       建立 NavigatorEntry                      │
  └───────────────────────────────┬────────────────────────────────┘
                                  │
                                  └─► 寫入 NavigatorInspector RingBuffer
```

- **避免循環記錄**：會主動偵測路由名稱，若為控制台頁面（`flutter_inspector_dashboard`），則跳過記錄，防止時序軸產生無限自我堆疊。
- **類型安全解析**：若 `settings` 是 `Page`，則獲取 `page.child` 的 `runtimeType`；否則若是能解析 builder 的特定 Route 則安全呼叫 builder 獲取元件類型；最終降級至 `settings.name`。

---

## 4. 未捕獲錯誤鏈接與轉發流程 (Error Handling & Chaining)

當配置 `captureUncaughtErrors: true` 時，套件會主動掛載錯誤處理鉤子。為保證向後兼容性（Never break userspace），我們決不能吞掉錯誤。

```text
                  主應用發生 Uncaught Error
                              │
                              ▼
                      錯誤發生在何處？
               ┌──────────────┼──────────────┐
               │              │              │
               ▼ (渲染/UI)    ▼ (非同步/Dart) ▼ (Widget 構建崩潰)
         FlutterError   PlatformDispatcher  ErrorWidget
           .onError        .instance.onError   .builder
               │              │              │
               └──────────────┼──────────────┘
                              ▼
                     建立 LogEntry (Error)
                              │
                              ▼
                 安全處理 (try-catch 隔離包裹)
                              │
                              ▼
                寫入 LogInspector RingBuffer
                              │
                              ▼
                   是否存在 Host 原始 Handler？
                    ╱                      ╲
                  (Yes)                    (No)
                  ╱                          ╲
  ┌────────────────────────┐      ┌────────────────────────┐
  │ 調用舊 Handler 轉發錯誤 │      │ 調用系統預設錯誤處理    │
  │ (如發送至 Crashlytics) │      │ (或崩潰紅畫面渲染)     │
  └────────────────────────┘      └────────────────────────┘
```

- **安全防護機制**：寫入日誌的邏輯完全置於 `try-catch` 中。在 `finally` 中將控制權回傳至下游原始 Handler，即使除錯套件日誌寫入失敗，主 App 亦絕不崩潰。

---

## 5. App 生命週期標記流程 (Lifecycle Marker Flow)

> 本節同時涵蓋**記憶體壓力事件**——它由同一個 observer、同一個 `captureLifecycleEvents` 旗標驅動，走下圖完全相同的路徑，差異見〈關鍵細節〉第 5 點。

當配置 `captureLifecycleEvents: true` 時，套件把 app 前景/背景切換記成一條 `LogLevel.info` log——**多一個事件來源，不是多一個系統**。每筆 log 尾巴附加當下的 top-most page，讓 home/back 頻繁切換時仍能在 Console 一眼分辨發生在哪一頁，免去跳 Navigator tab 對時間戳。

```text
              App 生命週期狀態變化 (framework 廣播)
                            │
                            ▼
          WidgetsBinding 廣播至 observer list
          （LifecycleHandler 是其中一個，宿主自己的 observer 照常收到）
                            │
                            ▼
          LifecycleHandler.didChangeAppLifecycleState
                            │ (try-catch 隔離，任何拋錯不逃逸給宿主)
                            ▼
          向 FlutterInspector 索取當前 top-most page
          (_currentTopPageLabel)
                            │
                            ▼
          NavigatorStackResolver.resolve(navigatorEntries)
          純函式重播 push/pop/replace/remove → 取 .first
                   ╱                      ╲
             (推得出來)                (空 history / 推不出來)
                 ╱                          ╲
   "displayName (routeName)"          回傳 null
   （無 routeName 時只給型態）             │
                 │                          │
                 ▼                          ▼
   message = "App lifecycle: {state} · {page}"   message = "App lifecycle: {state}"
                            │              （省略尾巴，不硬掰）
                            └──────┬───────┘
                                   ▼
                        寫入 LogInspector RingBuffer
                                   │
                                   ▼
                既有 mergedTimeline / Console tab / 診斷報告
                （零改動即受益，崩潰前最近一筆即前景/背景 + 頁面答案）
```

### 關鍵細節

1. **chain 不覆蓋、可乾淨 teardown**：`WidgetsBindingObserver` 用 `addObserver`/`removeObserver` 註冊，是 binding 上的一個 list，不霸占宿主唯一名額。`detach()` 呼叫 `removeObserver(this)` 只移除自己——與 `FlutterError.onError`（單一 slot、不 teardown）刻意相反，兩者各有正確理由。
2. **top-page 是 best-effort，推不出來就省略**：來源 `NavigatorStackResolver` 是純函式重播，會因 observer 掛載前導航 / buffer 淘汰 / nested Navigator 而失準。**推不出來時省略尾巴而非猜測**——不讓讀者把推導值當事實（避開 §P2「錯誤上下文快照」被否決的同一個坑）。
3. **只取型態 + path，`data` 維持 `null`**：`displayName`（優先 `widgetType`）+ `routeName`，不帶 `arguments`（PII / 大量資料風險）。資訊放 message 供肉眼辨識，不為未來可能的程式化篩選預先開 `data` 欄位。
4. **耦合邊界**：`LifecycleHandler` 只收 `String? Function()? topPageLabel` callback，不持有 registry/resolver；resolve 邏輯留在 `FlutterInspector`。handler 仍是「症狀記錄器」，不知道那個字串怎麼來的。
5. **記憶體壓力走同一條路（PR #155）**：同一旗標下 `didHaveMemoryPressure()` 走上圖**完全相同**的流程——同一個 observer、同樣的 top-page 索取與 best-effort 省略、同樣寫進 `LogInspector` RingBuffer，只有兩處不同：訊息為 `Memory pressure{· page}`，且 level 是 **`LogLevel.warning` 而非 info**（OOM/LMK 前導信號要能被既有 warning/error 過濾撈起來，不能沉在資訊流裡）。它是 Dart 層唯一拿得到的 OOM 前導信號，因此進時間軸的價值在於與其前面的 network/route/db 事件並排讀出因果。平台覆蓋：Android 走 `onTrimMemory`、iOS 走 `didReceiveMemoryWarning`，Web 實質不觸發。

---

## 6. 診斷報告導出與分享流程 (Diagnostic Report Export & Share Flow)

當用戶在儀表板觸發導出功能時，系統會開啟 `ExportReportSheet`，並執行以下流程以進行結構化 Markdown 報告的同步建構與平台自適應分享：

```text
  [Dashboard Trigger]
         │
         ▼
  [ExportReportSheet] ── (選取 Include/Time/Errors-only)
         │
         ▼ (點擊 Share Report 觸發)
  [Async Metadata Collection] (try-catch 隔離)
         │  ├─► 異步呼叫 DiagnosticInfoSource.collect()
         │  └─► 出錯時 null-fallback 為 null (不影響導出)
         ▼
  [Sync Report Building] (UI-free, pure Dart)
         │  ├─► 合併所有選取 entries 並按 timestamp 降序 merge-sort
         │  ├─► 將每條 entry 格式化為 Markdown 行
         │  └─► 對 logs/bodies 執行 _fenced (動態計算 backticks 以防 fenced block 提早結束)
         ▼
  [Conditional Text Sharing] (Conditional Export)
         │
         ├─► (Web) Web Share API (navigator.share) -> 降級寫入剪貼簿
         │
         └─► (Native) share_plus 呼叫系統 Share Sheet
                 │
                 ▼ (若 share_plus 丟出異常)
           [Share Fallback Sequence]
                 │
                 ├─► 1. 異步寫入系統剪貼簿 (Clipboard.setData)
                 ├─► 2. 顯示 SnackBar 通知: "Share unavailable — copied to clipboard"
                 │
                 └─► (若剪貼簿也失敗)
                       └─► SnackBar: "Export failed — please try again"
                       └─► 保持 Sheet 開啟，防止報告遺失，讓用戶重試
```

1. **觸發與選項配置**：在 `ExportReportSheet` 中，用戶可以篩選包含的資料源（Logs, Network, Navigation, Database）、時間區間（5 分鐘、1 小時、所有時間）以及是否僅保留錯誤與警告。
2. **異步元數據收集**：嘗試等待 `DiagnosticInfoSource.collect()` 收集裝置與應用元數據。此步驟以 `try-catch` 保護，如遇異常（如主應用的實作崩潰），則安全將 `DiagnosticInfo` 設為 `null`，以降級至 `N/A` 繼續進行，絕不中斷報告導出。
3. **純淨的同步報告建構**：調用 `buildDiagnosticReport` 函數。該函數是純 Dart 的同步無狀態函數（UI-free, no `BuildContext`），執行以下操作：
   - 合併選取之領域的 `TimestampedEntry` 資料，依 `timestamp` 降序進行歸併排序。
   - 重建路由 stack（忽略時間窗口限制以求完整正確性）。
   - 對於程式碼與 Response body 內容，執行 `_fenced` 函數：動態計算內容中最大連續 backticks 數量，以此動態決定 fenced block 的外層邊界（`longest < 3 ? 3 : longest + 1`），避免內部程式碼中的 Markdown 標記導致整個報告格式毀損。
4. **條件匯出與分享**：調用平台自適應的 `shareText(report)`。
5. **分享容錯序列 (Fallback Sequence)**：若 `shareText` 丟出錯誤（如在某些無原生分享面板的 Native 裝置上）：
   - 首先嘗試調用 `Clipboard.setData` 將報告複製到剪貼簿。
   - 成功複製後，彈出 SnackBar 提示：「Share unavailable — copied to clipboard」。
   - 若寫入剪貼簿也失敗，則彈出 SnackBar 提示：「Export failed — please try again」，且**保持底層 Modal 開啟**不調用 `navigator.pop()`，讓用戶有機會重試或自行複製。

---

## 7. 懸浮按鈕與 Overlay 生命週期管理流程 (Overlay Entry FAB Lifecycle Flow)

懸浮 FAB 按鈕的顯示與隱藏，由 `InspectorOverlayManager` 以完全解耦的方式集中管理：

```text
       FlutterInspector.attach() (或 hot-reload 初始化)
                      │
                      ▼
        InspectorOverlayManager.attach()
                      │
             _overlayEntry != null ?
               ╱              ╲
            (Yes)            (No)
             ╱                  ╲
        [安全防護: 返回]   1. 尋找 Overlay.maybeOf(context) (若無則安全返回)
                           2. 建立 OverlayEntry 實例 (封裝 InspectorFab)
                           3. 註冊建構子回呼 onFabTap 指向外層 showDashboard()
                           4. overlay.insert(_overlayEntry!) 載入畫面
```

```text
       FlutterInspector.detach() (或主應用手動卸載)
                      │
                      ▼
        InspectorOverlayManager.detach()
                      │
             _overlayEntry == null ?
               ╱              ╲
            (Yes)            (No)
             ╱                  ╲
        [安全防護: 返回]   1. 呼叫 _overlayEntry.remove() 自 Overlay 移除
                           2. 將 _overlayEntry 設為 null (防記憶體洩漏與重複操作)
```

1. **冪等性載入 (`attach`)**：在 `attach()` 時，首先確認內部 `_overlayEntry` 欄位是否為空。若非空則立即返回以避免重複掛載（Idempotence）。尋找當前 context 下的 `Overlay` 元件。成功取得後，建構並將封裝了 `InspectorFab` 的 `OverlayEntry` 插入，其 onTap 事件會觸發注入的 `onFabTap` 回呼。
2. **安全卸載 (`detach`)**：在 `detach()` 時，調用 `_overlayEntry?.remove()`，並將欄位重設為 `null`，防止記憶體洩漏並為下次載入做好準備。

---

## 8. WebView 事件橋接流程 (WebView Bridge Flow)

宿主 app 的 WebView 內事件（console / JS error / fetch / XHR）經注入的 JS bridge 翻譯為既有 `LogEntry` / `NetworkEntry`，與 native 事件共用同一條 timeline——**多一個事件來源，不是多一個系統**。套件對 webview 套件零相依：宿主自備 `webview_flutter` 或 `flutter_inappwebview` 並照 README 接線。

```text
  WebView 頁面 (不可信來源)      JavaScriptChannel /        WebViewBridgeAdapter        FlutterInspector & Registry
  inspectorWebViewBridgeJs       addJavaScriptHandler
       │                              │                           │                            │
       │ console.* / onerror /        │                           │                            │
       │ unhandledrejection /         │                           │                            │
       │ fetch / XHR 被 hook          │                           │                            │
       │                              │                           │                            │
       │─ 1. JS 端截斷 (MAX_CHARS) ──│                           │                            │
       │   統一 JSON envelope         │                           │                            │
       │   {t:"log"|"net", ...}       │                           │                            │
       │─── 2. postMessage(String) ──>│                           │                            │
       │                              │─── 3. handleMessage ─────>│                            │
       │                              │                           │─ 4. 大小上限檢查 (256KB)   │
       │                              │                           │─ 5. jsonDecode + 型別守衛  │
       │                              │                           │   (整條路由包 try-catch，  │
       │                              │                           │    敵意輸入靜默丟棄)       │
       │                              │                           │                            │
       │                              │              t == "log" ─>│─── inspector.log(...) ────>│ → Log RingBuffer
       │                              │              t == "net" ─>│─── inspector.logNetwork ──>│ → Network RingBuffer
       │                              │                           │    (origin: webview,       │
       │                              │                           │     pageUrl: location.href)│
       │                              │                           │                            ▼
       │                              │                           │          既有 mergedTimeline / Console tab /
       │                              │                           │          Network tab / Error Aggregation /
       │                              │                           │          診斷報告 Timeline（零改動即受益）
```

### 關鍵細節

1. **翻譯器不是系統**：adapter 形狀鏡像 `FlutterInspectorDioInterceptor`——持 inspector 參照、用公開 API 推事件，`FlutterInspector` 建構子零改動；不持有 buffer、不做 UI、不做 redaction。
2. **Provenance 為第一級欄位**：network 事件帶 `origin: NetworkOrigin.webview` 與 `pageUrl`；log 事件以既有 `data` map 攜帶 `{'origin':'webview','pageUrl':...}`。`NetworkDetailView` General 區顯示 Origin / Page URL。
3. **Replay 自然降級**：WebView 請求非經 Dio 送出，`sourceDio == null` 使既有 Replay 檢查自動停用，無新增特殊分支。
4. **redaction 共用邊界**：WebView `NetworkEntry` 存原始 headers/body（與 native 一致），遮罩由既有顯示/匯出 formatter 依 `redactSensitiveData` 施加——同一組 code path，無旁門。
5. **注入時機差異**：`flutter_inappwebview` 的 `UserScript` 可於 documentStart 注入、吃得到頁面最早期事件；`webview_flutter` 的 `runJavaScript` 於 `onPageStarted` 後執行會漏最早期 log。README 明文標註，套件不假裝抹平。
