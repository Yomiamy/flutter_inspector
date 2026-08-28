# Flutter Inspector Kit - 檔案用途與類型參考表 (File Reference)

本文件列出專案中所有核心源檔的單一職責、包含的關鍵類別與模組歸屬，以作為新加入的貢獻者快速熟悉專案結構的指南。

---

## 📂 核心模組與檔案結構

### 1. 入口與核心層 (`lib/` 根目錄與 `lib/src/core/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/flutter_inspector_kit.dart`](../../lib/flutter_inspector_kit.dart) | - | Barrel 檔案，導出本套件對外公開的 API。 |
| [`lib/src/core/flutter_inspector.dart`](../../lib/src/core/flutter_inspector.dart) | `FlutterInspector` | 套件的主入口。管理初始化、接收各項日誌與資料輸入，並與各個領域 Inspector 進行協調。支援配置 `slowRequestThreshold` 慢速請求時間門檻（預設 2 秒），影響 Dashboard 視覺標籤與慢速請求指標。含 `_currentTopPageLabel()`——為 `LifecycleHandler` 提供當前 top-most page 標籤（走 `NavigatorStackResolver` best-effort 重播，推不出來回傳 `null`）。 |
| [`lib/src/core/inspector_registry.dart`](../../lib/src/core/inspector_registry.dart) | `InspectorRegistry` | 中央緩衝註冊表，集中持有並管理四個領域的 RingBuffer，同時實裝多源歸併排序。 |
| [`lib/src/core/ring_buffer.dart`](../../lib/src/core/ring_buffer.dart) | `RingBuffer<T>` | 基礎 FIFO 環形快取。提供固定容量的資料寫入、刪除最舊數據及原地取代（`replace`）功能。 |
| [`lib/src/core/uncaught_error_handler.dart`](../../lib/src/core/uncaught_error_handler.dart) | `UncaughtErrorHandler` | 獨立的錯誤監聽類別，無 Inspector 逆向依賴。透過建構子接收回呼並安全鏈接至三大系統錯誤鉤子。同一 build 崩潰以 object-identity 去重，避免重複記錄（PR #96）。 |
| [`lib/src/core/lifecycle_handler.dart`](../../lib/src/core/lifecycle_handler.dart) | `LifecycleHandler` | **[新增]** 獨立的 app 生命週期監聽類別（`with WidgetsBindingObserver`），無 Inspector 逆向依賴。opt-in `captureLifecycleEvents`（default off）下把 `resumed`/`inactive`/`paused`/`detached`/`hidden` 各轉一筆 `LogLevel.info` log，message 尾巴附當前 top-most page（由建構子傳入的 `topPageLabel` callback 提供）。`detach()` 乾淨移除 observer（PR #100）。 |
| [`lib/src/core/inspector_overlay_manager.dart`](../../lib/src/core/inspector_overlay_manager.dart) | `InspectorOverlayManager` | 負責安全地管理懸浮 FAB Overlay 生命週期，支援冪等加載與無洩漏卸載。 |

### 2. 數據模型層 (`lib/src/models/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/models/timestamped_entry.dart`](../../lib/src/models/timestamped_entry.dart) | `TimestampedEntry`<br>`TimelineSource` (enum) | 混合時序軸的統一契約介面與其格式化擴充方法。定義了 `timestamp`、`displayTime` 屬性。 |
| [`lib/src/models/log_level.dart`](../../lib/src/models/log_level.dart) | `LogLevel` (enum) | 控制台日誌的嚴重性等級（`verbose` 至 `error`）。 |
| [`lib/src/models/log_entry.dart`](../../lib/src/models/log_entry.dart) | `LogEntry` | 單條日誌資料模型。實作了 `TimestampedEntry` 介面。 |
| [`lib/src/models/network_entry.dart`](../../lib/src/models/network_entry.dart) | `NetworkEntry` | HTTP 請求與響應資料模型。使用 `WeakReference<Dio>` 避免記憶體洩漏。實作 `TimestampedEntry`。含 `origin` / `pageUrl` provenance 欄位（帶預設值，向後相容）。 |
| [`lib/src/models/network_origin.dart`](../../lib/src/models/network_origin.dart) | `NetworkOrigin` (enum) | **[新增]** 網路請求來源（`dio` / `webview`）。顯式 provenance，取代不可靠的 `sourceDio == null` 推斷（WeakReference 被 GC 後無法區分來源）。 |
| [`lib/src/models/navigator_action.dart`](../../lib/src/models/navigator_action.dart) | `NavigatorAction` (enum) | 導航動作類型（`push`、`pop`、`replace`、`remove`）。 |
| [`lib/src/models/navigator_entry.dart`](../../lib/src/models/navigator_entry.dart) | `NavigatorEntry` | 導航事件資料模型。實作 `TimestampedEntry`。 |
| [`lib/src/models/database_operation.dart`](../../lib/src/models/database_operation.dart) | `DatabaseOperation` (enum) | 資料庫操作類型（`insert`、`update`、`delete`、`query`）。 |
| [`lib/src/models/database_entry.dart`](../../lib/src/models/database_entry.dart) | `DatabaseEntry` | SQL 日誌資料模型。實作 `TimestampedEntry`。 |
| [`lib/src/models/database_browser_source.dart`](../../lib/src/models/database_browser_source.dart) | `DatabaseBrowserSource`<br>`DatabaseTableInfo`<br>`DatabaseTablePage` | 定義自訂資料庫結構與資料的分頁讀取契約，用於資料庫瀏覽器 Tab。 |
| [`lib/src/models/diagnostic_info.dart`](../../lib/src/models/diagnostic_info.dart) | `DiagnosticInfo`<br>`DiagnosticInfoSource` | **[新增]** 元數據模型與其 Host 收集介面。欄位皆為 nullable，在 Web 載入或 Host 獲取失敗時會安全降級為 `N/A`。 |

### 3. 控制與收集器層 (`lib/src/inspectors/`、`lib/src/interceptors/`、`lib/src/observers/` 等)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/inspectors/log_inspector.dart`](../../lib/src/inspectors/log_inspector.dart) | `LogInspector` | 提供對日誌 RingBuffer 的包裝，主要實現級別過濾。 |
| [`lib/src/inspectors/network_inspector.dart`](../../lib/src/inspectors/network_inspector.dart) | `NetworkInspector` | 提供對網路請求 RingBuffer 的包裝，負責 Response 大小判別與 Completion 就地替換。 |
| [`lib/src/inspectors/navigator_inspector.dart`](../../lib/src/inspectors/navigator_inspector.dart) | `NavigatorInspector` | 提供對導航 RingBuffer 的包裝。 |
| [`lib/src/inspectors/navigator_stack_resolver.dart`](../../lib/src/inspectors/navigator_stack_resolver.dart) | `NavigatorStackResolver` | 負責根據導航事件流重新解析與還原當前應用的作用中路由 stack。 |
| [`lib/src/inspectors/database_inspector.dart`](../../lib/src/inspectors/database_inspector.dart) | `DatabaseInspector` | 提供對資料庫 RingBuffer 的包裝。 |
| [`lib/src/interceptors/dio_interceptor.dart`](../../lib/src/interceptors/dio_interceptor.dart) | `FlutterInspectorDioInterceptor` | Dio 攔截器，實作 Adapter 模式，將網絡生命週期轉化為 `NetworkEntry` 發送給 Core。 |
| [`lib/src/observers/navigator_observer.dart`](../../lib/src/observers/navigator_observer.dart) | `FlutterInspectorNavigatorObserver` | 導航觀察者，實作 Adapter 模式，將路由變更進行 Widget 類型解析後發送給 Core。 |
| [`lib/src/sources/operation_log_source.dart`](../../lib/src/sources/operation_log_source.dart) | `OperationLogSource` | 將資料庫 SQL 日誌包裝成虛擬 `DatabaseBrowserSource`，以便在資料庫 Tab 顯示。 |
| [`lib/src/webview/webview_bridge_js.dart`](../../lib/src/webview/webview_bridge_js.dart) | `kWebViewBridgeChannelName`<br>`inspectorWebViewBridgeJs` | **[新增]** 可注入 WebView 的 JS bridge payload（常數字串）。Hook `console.*`、`window.onerror`、`unhandledrejection`、`fetch`、`XHR`，JS 端截斷大 payload 後以統一 JSON envelope postMessage 給 native；單一 payload 同時支援 webview_flutter 與 flutter_inappwebview 的傳輸層。 |
| [`lib/src/webview/webview_bridge_adapter.dart`](../../lib/src/webview/webview_bridge_adapter.dart) | `WebViewBridgeAdapter` | **[新增]** WebView 訊息翻譯器，形狀鏡像 Dio interceptor。decode bridge JSON → 建 `LogEntry` / `NetworkEntry`（含 webview provenance）→ 經公開 API 推入 Core。`handleMessage` 永不拋出，並以 256KB 上限擋下繞過注入腳本的敵意超大訊息。 |

### 4. 平台適應通知層 (`lib/src/notifications/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/notifications/alert_throttler.dart`](../../lib/src/notifications/alert_throttler.dart) | `AlertThrottler` | 限制通知頻率，為 Heads-up Notification 提供 2 秒的冷卻限制以減少視覺噪音。 |
| [`lib/src/notifications/network_notifier.dart`](../../lib/src/notifications/network_notifier.dart) | - | 平台導出分流器。採用 Conditional Exports 設計，在 Web 載入 no-op，Native 載入 io 實作。 |
| [`lib/src/notifications/network_notifier_io.dart`](../../lib/src/notifications/network_notifier_io.dart) | `NetworkNotifier` (Native) | 使用 `flutter_local_notifications` 顯示網絡請求通知，點擊可呼叫控制台。 |
| [`lib/src/notifications/network_notifier_web.dart`](../../lib/src/notifications/network_notifier_web.dart) | `NetworkNotifier` (Web) | Web 端 no-op 實現，阻斷 `dart:io` 防止破壞 WASM 編譯。 |

### 5. 無狀態工具層 (`lib/src/utils/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/utils/log_formatters.dart`](../../lib/src/utils/log_formatters.dart) | - | 將日誌資料模型格式化為單行與純文字的工具方法。 |
| [`lib/src/utils/network_formatters.dart`](../../lib/src/utils/network_formatters.dart) | `ReplayRequest` | 提供網絡格式化功能，包含 `buildCurl` 產生 cURL 指令與 `prettyJson` 縮排工具。 |
| [`lib/src/utils/network_utils.dart`](../../lib/src/utils/network_utils.dart) | `NetworkStatusGroup`<br>`NetworkFilter` | 提供網絡搜尋、過濾邏輯與狀態碼 Chip 對應常數。 |
| [`lib/src/utils/redaction.dart`](../../lib/src/utils/redaction.dart) | - | 安全遮蔽。辨識敏感 headers（如 `authorization`、`cookie`）並遮蓋為 `••••`。 |
| [`lib/src/utils/share_text.dart`](../../lib/src/utils/share_text.dart) | - | 分享平台適應分流器（條件導出）。 |
| [`lib/src/utils/share_text_io.dart`](../../lib/src/utils/share_text_io.dart) | - | 使用 `share_plus` 開啟手機系統原生分享面板。 |
| [`lib/src/utils/share_text_web.dart`](../../lib/src/utils/share_text_web.dart) | - | 使用 Web Share API `navigator.share`，降級則複製到剪貼簿。 |
| [`lib/src/utils/table_sort.dart`](../../lib/src/utils/table_sort.dart) | - | 提供虛擬資料庫表格的記憶體排序（Null 一律置於最末）與單元格預覽工具。 |
| [`lib/src/utils/diagnostic_report.dart`](../../lib/src/utils/diagnostic_report.dart) | `buildDiagnosticReport` | **[新增]** 純粹且同步的 Markdown 報告產生器。與 UI 完全解耦，包含 fenced 區塊安全 backticks 計算。 |

### 6. UI 表現層 (`lib/src/ui/` 底下元件與頁面)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/ui/dashboard/dashboard_modal.dart`](../../lib/src/ui/dashboard/dashboard_modal.dart) | `DashboardModal` | 控制台全螢幕 Dialog 元件，包裝 TabBarView 結構。 |
| [`lib/src/ui/dashboard/tabs/console_tab.dart`](../../lib/src/ui/dashboard/tabs/console_tab.dart) | `ConsoleTab` | 顯示混合時序軸（Console, Network, Nav, DB 等多源時序歸併）並依類型分頁展示。 |
| [`lib/src/ui/dashboard/tabs/console/log_detail_view.dart`](../../lib/src/ui/dashboard/tabs/console/log_detail_view.dart) | `LogDetailView` | 展示單條日誌詳細資訊與 Stack Trace 的卡片。 |
| [`lib/src/ui/dashboard/tabs/network_tab.dart`](../../lib/src/ui/dashboard/tabs/network_tab.dart) | `NetworkTab` | 提供網絡請求列表、搜尋過濾與 Status 晶片篩選；支援慢速請求視覺標籤（`🐢 SLOW`）以及在 `_ErrorSummaryBanner` 中展示 slow request 統計指標與時間門檻資訊。 |
| [`lib/src/ui/dashboard/tabs/network/network_detail_view.dart`](../../lib/src/ui/dashboard/tabs/network/network_detail_view.dart) | `NetworkDetailView` | 展現詳細的請求/響應 headers 與 body，並整合 Replay、cURL 複製與分享。 |
| [`lib/src/ui/dashboard/tabs/navigator_tab.dart`](../../lib/src/ui/dashboard/tabs/navigator_tab.dart) | `NavigatorTab` | 以時間軸列表展示路由事件與傳參。 |
| [`lib/src/ui/dashboard/tabs/database_tab.dart`](../../lib/src/ui/dashboard/tabs/database_tab.dart) | `DatabaseTab` | 數據庫瀏覽器 Tab。支援動態下拉切換不同的 `DatabaseBrowserSource`。 |
| [`lib/src/ui/dashboard/tabs/database/table_rows_view.dart`](../../lib/src/ui/dashboard/tabs/database/table_rows_view.dart) | `TableRowsView` | 表格二維數據瀏覽器。支援動態加載（Load More）、點擊單元格查看，以及點擊表頭排序。 |
| [`lib/src/ui/dashboard/export_report_sheet.dart`](../../lib/src/ui/dashboard/export_report_sheet.dart) | `ExportReportSheet` | **[新增]** 診斷報告導出與分享 Dialog (Bottom Sheet)。包含 Include 篩選、時間區間與 errors-only 選項，並實現了 Clipboard 降級 fallback 分享容錯機制。 |
| [`lib/src/ui/widgets/inspector_fab.dart`](../../lib/src/ui/widgets/inspector_fab.dart) | `InspectorFab` | 安全區域內可拖曳的懸浮按鈕。 |
| [`lib/src/ui/widgets/magical_tap.dart`](../../lib/src/ui/widgets/magical_tap.dart) | `FlutterInspectorMagicalTap` | 靜默手勢防護罩，用於隱藏 FAB 時藉由快速連擊喚醒控制台。 |
| [`lib/src/ui/widgets/key_value_table.dart`](../../lib/src/ui/widgets/key_value_table.dart) | `KeyValueTable` | 通用的緊湊二欄式鍵值表格組件。 |
| [`lib/src/ui/widgets/detail_section.dart`](../../lib/src/ui/widgets/detail_section.dart) | `DetailSection`<br>`DetailKeyValueRow` | 共用的詳細資訊卡片與鍵值佈局組件。 |
| [`lib/src/ui/widgets/error_card.dart`](../../lib/src/ui/widgets/error_card.dart) | `ErrorCard` | 通用的錯誤狀態與空狀態 UI 卡片組件。 |

### 7. 主題與樣式設計 (`lib/src/ui/theme/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/ui/theme/theme.dart`](../../lib/src/ui/theme/theme.dart) | - | **[新增]** Barrel 檔案，導出所有的主題樣式設計 Token。 |
| [`lib/src/ui/theme/theme_color.dart`](../../lib/src/ui/theme/theme_color.dart) | `ThemeColor` | **[新增]** 定義配色與 HTTP status code 語意配色映射方法。 |
| [`lib/src/ui/theme/theme_padding.dart`](../../lib/src/ui/theme/theme_padding.dart) | `ThemePadding` | **[新增]** 定義 EdgeInsets 邊距 Tokens（如 `paddingAll8`, `paddingAll12`, `paddingAll16`, `paddingH8`, `paddingH16V8`）。 |
| [`lib/src/ui/theme/theme_size.dart`](../../lib/src/ui/theme/theme_size.dart) | `ThemeSize` | **[新增]** 統一收納尺寸 Token，包含間距 (`space*`)、邊框圓角 (`radius*`) 與元件固定寬高 (`size*`)，取代原先獨立的 `theme_spacing.dart` 與 `theme_radius.dart`。 |
| [`lib/src/ui/theme/theme_textstyle.dart`](../../lib/src/ui/theme/theme_textstyle.dart) | `ThemeTextStyle`<br>`ThemeFontSize` | **[新增]** 定義文字字型與粗細 Tokens。並包含 `ThemeFontSize`（`fontSize10`, `fontSize11`, `fontSize12`）字體大小常數。 |

### 8. 擴充方法與版本定義 (`lib/src/extensions/` 及其他)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) |
| :--- | :--- | :--- |
| [`lib/src/extensions/log_level_color_extension.dart`](../../lib/src/extensions/log_level_color_extension.dart) | `LogLevelColor` | 為不同 `LogLevel` 的日誌提供語意化色彩映射。 |
| [`lib/src/version.dart`](../../lib/src/version.dart) | `packageVersion` (String) | 定義當前 package 的版本資訊。**發版時必須與 `pubspec.yaml` 同步**——此處刻意不寫死版號，避免文件與實際版本漂移。 |
