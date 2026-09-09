# 🩺 Flutter Inspector 錯誤問題排查與分析：功能腦力激盪報告

> **建立日期**：2026-06-25（原始檔名）
>
> **📝 更新紀錄 (Changelog)**：
> * **2026-09-08**：**§P21 附加 ImageCache 水位案（Issue #158）實作完成後整案撤回**——原想在 memory pressure 那筆 warning 尾巴附上 `imageCache 98.2 MB/100.0 MB (212 imgs)`，賣點是「水位只有 3 MB 就能排除圖片方向」的否證能力。實作完成、584 測試全綠、analyze 零新增，但 code review 階段以 spy observer 實測發現 **`PaintingBinding.handleMemoryPressure()`（`painting/binding.dart:160`）在通知 observer 之前就 `imageCache.clear()`**，`didHaveMemoryPressure()` 內讀到的分子與張數**恆為 0**（`BEFORE: size=256 count=1` → `INSIDE observer: size=0 count=0`）。功能因此永遠輸出 `imageCache 0 B/...`，賣點反轉為**假否證**（會讓排查者排除正確方向），踩到 Anti-Feature #3「假精度比沒有資訊更糟」的判準，故 branch 重置、零程式碼留下。已查證 3.41.9 與 3.44.1 該兩段程式碼逐字相同（涵蓋整個支援範圍）、真實 OS 事件同路徑、`liveImageCount` 亦為 0。該需求改由**新增的 §P25 ImageCache 水位計**承接（主動查看時讀取，不綁 OS 事件）。同時新增「2026-09-08 記憶體觀測選項全面評估」表（RSS+Swap / LMK / bitmap 對齊 / 兩種水位讀法共五項逐一判定）與 §P21 的 `onTrimMemory` deprecation 風險註記。**本案的方法論教訓已寫入 §P21 撤回紀錄：查證「API 存在且可讀」不等於查證「在我要讀的那個時點，讀到的值有意義」。** 檔名日期前綴由 `2026-09-01` 更新至 `2026-09-08`。
> * **2026-09-04**：**官方 `dart-lang/leak_tracker` 深度評估與架構裁決**——針對官方記憶體洩漏分析套件深入研究其運作機制（Flutter `MemoryAllocations`、`Finalizer`、`WeakReference`、`reachabilityBarrier`、`vm_service`）、執行時期代價（`forceGC` 之激進記憶體分配造成的嚴重 Jank、定時輪詢與堆疊捕獲開銷）及跨平台限制（Web/WASM 下 Retaining Path 為 null、無法建立 VM Service WebSocket、`reachabilityBarrier` 不可用）。從 Linus 模式五層分解進行裁決，確立「堅決拒絕 Direct In-App 內建整合」的鐵律，更新第 2 節矩陣評分，增補第 3 節「核心決策三：拒絕 In-App 記憶體洩漏追蹤」，並提供純記錄導向之可選適配（Adapter/Recipe）規範。
> * **2026-09-04**：**§P21 記憶體壓力事件完成**——PR #155 合入 main（issue #154）。落地形式與原提案的差異只有一處：原本「二擇一待定」的旗標選擇**已裁決併入既有 `captureLifecycleEvents`**，不新增 `captureMemoryPressure`——兩者是同一個 observer 上的 callback、共用同一組 attach/detach，拆兩個旗標只是多一個特殊情況。其餘照提案落地：`LifecycleHandler` 多覆寫一個 `didHaveMemoryPressure()`，記為 `LogLevel.warning`（非 info——這是 OOM/LMK 前導信號，必須能被既有 warning/error 過濾撈起來，不能沉在資訊流裡），沿用既有 `topPageLabel` 後綴，零新增 Entry/Inspector/RingBuffer、零新相依。callback 內以 try-catch 包住：本套件 SDK 下限（Flutter >=3.10.0）的 `handleMemoryPressure()` 逐一走訪 observer 且**無** per-observer try-catch（per-observer 保護是 3.44.0 才加入），逸出的例外會中斷廣播、波及排在後面的每個 observer。`example/` 另補一顆 `Simulate Memory Pressure` 按鈕（走 `WidgetsBinding.instance.handleMemoryPressure()`，與 OS 真實回報同一條 observer 廣播路徑）。檔名日期前綴由 `2026-09-01` 更新至 `2026-09-04`。
> * **2026-08-28**：**新增第六部分：開源除錯與日誌生態套件全面評估與整合策略**——針對社群主流除錯與日誌套件（涵蓋 talker_flutter, logger, alice/chucker_flutter, flutter_mxlogger, logging, logarte, stack_trace, flutter_ume, catcher 等 20+ 套件）進行 4 大維度深度評估（架構相容性、輕量與效能、UI/UX 視覺呈現、社群活力與穩定度）。以 Linus 模式核心判斷「拒絕重型黑盒全家桶替換核心、嚴守 Anti-Features（拒絕本機落盤與強依賴注入）」，並提出 4 項高 ROI、零新相依的務實整合提案（§P16 生態適配器 LogOutput/TalkerObserver、§P17 原生折疊 JSON 樹狀檢視器、§P18 輕量網路效能統計條、§P19 StackTrace 非同步鏈正規化）。
> * **2026-08-22**：**§P15 鍵值儲存檢視器完成**——PR #137 合入 main（issue #136）。落地形式與原提案有一處關鍵差異：**實作為獨立 Storage tab，非併入 Database Tab**（理由：區分儲存引擎本身是 RD 需要的排查訊號）。該改動連帶消滅了「兩類 source 共存於同一 dropdown」的型別難題——`database_tab.dart` 最終一行未改。稽核 log 的值預設遮蔽（會經 `buildLogPlainText` 進剪貼簿與分享，而 KV source 可能是 secure storage）。Tier 4 剩 3 項（§P4 / §D4 / §P9）。檔名日期前綴由 `2026-08-14` 更新至 `2026-08-22`。
> * **2026-08-14**：**新增 §P15 鍵值儲存檢視器（Key-Value / SharedPreferences Browser）**——針對 QA 與開發者排查 Token 過期、快取污染與 Feature Flag 異常痛點，提出基於 `KeyValueBrowserSource` 的 host-injection 介面與 Database Tab 整合方案（支援搜尋、即時編輯、刪除與清空操作，零新相依且寫入操作自動記 log 追蹤）。排入 Tier 4（最高排查價值項）。
> * **2026-07-27**：**§D6 實查已完成**——經 codebase 比對，`pushInspectorRoute` 與 `kInspectorRoutePrefix` 皆已落實，此既有缺陷已修復。
> * **2026-07-26**：**新增 §D6 Inspector 自身頁面污染 NavigatorTab（既有缺陷）**——實測確認（probe test）dashboard 內 push 的 detail view 會被記進使用者的 Navigator 軌跡。根因是三段鏈：`dashboard_modal.dart` 的 `showGeneralDialog` 未指定 `useRootNavigator`（預設 `true`）→ dashboard 掛在**宿主 app 的 root Navigator**（正是掛載 observer 的那一個）→ 而 4 處 detail view 的 `MaterialPageRoute` **完全沒帶 `RouteSettings.name`**，`_isInspectorRoute()` 的字串等值比對一律放行。污染量與排查強度**成正比**（越反覆開關 detail view 越髒），故排入 **Tier 2** 而非打磨層——它侵蝕的是 NavigatorTab 既有功能的資料可信度。**已定案採方案 B**（dashboard 內部統一走 `pushInspectorRoute` helper，`_isInspectorRoute` 只認單一來源），不採方案 A（逐一補 route name）——A 把正確性押在「新增頁面時記得補」的人為自律上，B 才消滅特殊情況。**已實作**。
> * **2026-07-25**：**§P7 Error 高亮強化完成**——PR #101 合入 main（merge `3ecdf51`），ConsoleTab 的 error log 與失敗網路請求加淡紅底（`ListTile.tileColor`，alpha 0.08）。**只染 error 不染 warning**（warning 密集時整片泛黃反而稀釋「跳出來」的效果），warning 維持橘字並有測試鎖住。真正的 diff 主體是**收斂「網路請求是否失敗」的三份重複判定**——動工才發現該判定在 `network_tab` / `diagnostic_report` / `network_utils` 各手寫一份且已漂移（各漏一種失敗類型），統一為 `NetworkEntry.isFailed`，並一併修掉「只帶 `errorType` 的傳輸失敗不產生 Error Summary 群組卡片」這個靜默的既有 bug。Tier 2 下一步為 §P11→§P1（綁定排程）。
> * **2026-07-25**：**§P13 App 生命週期標記完成**——PR #100 合入 main（merge `c616482`），新增 `LifecycleHandler` + `captureLifecycleEvents`（default off）把前景/背景切換轉成 `LogLevel.info` log，並在 message 尾巴附加當前 top-most page（型態 + path，解 home/back 洗頻）。`detach()` 一併 teardown observer（不沿用 error hooks 的不 teardown 慣例）。Tier 1 清空，下一步進 Tier 2（§P7 或 §P11→§P1）。
> * **2026-07-24**：**實作路徑重排為「鏈推斷優先」**——原 Phase Plan 以「先滅紅燈」把 §D1 ConsoleTab 搜尋/過濾排最高優先，重新檢視後判定該紅燈紅在「功能對稱性」而非「排查能力」：過濾是**點查詢**（已知道要找什麼），排查要的是**鏈推斷**（不知道要找什麼），且過濾會**切斷因果鏈**。新排序原則為「往時間軸加資訊 → 標記已有資訊 → 檢索 → 打磨」，§P13 升為第一順位，§D1 降至 Tier 3 並與 §P5 合併，§P14 降級不單獨排程，**§P2 錯誤上下文快照整項否決**（快照的事件本就在 timeline 上、推導堆疊會失準卻被當事實、預先挑維度違背「錯誤常是綜合因素」——與 §D3 同病）。同時修正三處與 codebase 不符的估計（`InspectorSearchBar` 實為私有 `_SearchBar`、`entriesAtLevel()` 接不上混合流、`NavigatorStackResolver.currentStack` 不存在）。詳見文末「下一步實作路徑」。
> * **2026-07-24**：**新增第五部分：第二輪腦力激盪——開源除錯生態手法 + 效能訊號 + 既有缺陷**——基於 v1.7.0 codebase 二次查核（含 `RingBuffer`/`AlertThrottler`/redaction pipeline/生命週期 hook 的實際可重用性驗證），提出 P10–P15 共 6 項，並記錄一項殘留 redaction 缺陷 §D5（**§D5 已於同日決定不排程**——debug 工具應以資訊完整為先，遮罩反成排查絆腳石，既有 redaction 實作保留原樣不動）。核心結論：多數「開源工具常見手法」在本專案已有地基（breadcrumb＝`mergedTimeline`、alert throttle＝`AlertThrottler`），真正的新地基需求集中在「生命週期/連線狀態」這類本專案從缺的 hook 類別。
> * **2026-07-24**：**#1 去重機制修復完成**——PR #96 合入 main（merge `5d2b37d`），`UncaughtErrorHandler` 改以 object-identity（`identical` 比對上一筆 `FlutterErrorDetails`）去重，消滅同一 build 崩潰在 Console 的重複記錄，§D2 由待辦轉為已完成。
> * **2026-07-24**：**補記網路系統通知**——文件此前漏列的既有「網路系統通知」基建（`showNetworkNotification` opt-in，自 v0.1.0，`flutter_local_notifications` 已在相依）已補進完成度總覽與 §P1，修正「通知類未實作」的誤判。
> * **2026-07-23**：**新增第四部分：功能缺口深度分析與新功能提案**——對照 v1.7.0 codebase 盤點全部 10 項原始功能的實際缺口，並提出 9 項新功能提案 P1–P9，聚焦「快速排查 / 輔助定位錯誤」；更新完成度總覽與實作路徑為四階段 Phase Plan。
> * **2026-07-18**：新增 #10 WebView Inline Debugging 提案並完成。

> 「好代碼沒有特殊情況。」 —— Linus Torvalds
>
> 這份報告**只聚焦一件事**：當 app 出錯時，`flutter_inspector_kit` 能不能讓開發者/QA 用最少的步驟「看見錯誤、關聯原因、帶走證據」。
> 我們不重彈上一份 [`brainstorm/2026-06-18-feature_brainstorming.md`](../../brainstorm/2026-06-18-feature_brainstorming.md) 的泛用優化清單，而是用排查（troubleshooting）這把尺，重新審視每個缺口。凡是偏離「排查」核心、或為了理論完美而增加複雜度的，一律砍掉。

---

## 📊 完成度總覽（截至 2026-09-06 · v2.4.0）

> 以下狀態依實際 codebase 與 git history 核對標注。✅ 完成 ｜ 🟡 部分完成 ｜ ⬜ 未實作。
>
> **📝 更新（2026-09-06）**：新增 **§P24 Crash 系統通知**（Issue #156，已完成），
> 並連帶讓 **§P11 NetworkNotifier 重構**落地——§P11 原記「應與 §P1 綁定排程」，
> 但 §P24 成為它先一步的消費者，該綁定關係已解除且前提已就緒。
>
> **📝 實查校正 (2026-08-06)**：對照 codebase 逐項核對 Tier 4，修正兩處與實況不符的記載——
> * **§P8 慢請求標記**：文件原標 🆕 待辦，**實為已完成**（PR #111 / Issue #110）。
>   `slowRequestThreshold` 已參數化（預設 2s、拒絕負值），NetworkTab 與 ConsoleTab
>   混合時間軸兩處皆有 `🐢 SLOW` 標記。Tier 4 因此由 5 項降為 4 項。
> * **§P4 快速複製 Diagnostic Snippet**：仍未實作（無任何組合式 snippet builder），
>   但 effort 由 low 下修為 **trivial~low**——`buildCurl` / `buildPlainText` / `shareText`
>   皆已存在且已接 redaction，`PopupMenuButton<_ShareAction>` 選單也已就位，
>   真正缺的只有一個組裝 formatter。現為 Tier 4 最低成本入口。
>
> **📝 版本更新與確認 (v1.8.0 - 2026-07-27)**：
> * **新功能與缺陷修復 (Tier 1 & 2)**：
>   * **§D6 (Inspector 自身頁面污染 NavigatorTab)**：查核確認已實作 (`pushInspectorRoute` 方案)。
>   * **§P7 (Error 高亮強化)**：於 PR #101 完成。
>   * **§P13 (App 生命週期標記)**：於 PR #100 完成。
>   * **§D2 / #1 (去重機制修復)**：於 PR #96 完成（object-identity 去重）。
> * 以上項目皆為 v1.8.0 週期內完成的核心排查功能。
> 
> **📝 歷史盤點 (v1.7.0 - 2026-07-23 缺口分析)**：
> * **#1 去重機制**：確認實質未實作（`FlutterError.onError` 與 `ErrorWidget.builder` 各自觸發，同一崩潰記錄兩次，後於 PR #96 修復）。
> * **#5 ConsoleTab 排查化**：搜尋欄未接入 UI、`entriesAtLevel()` 零呼叫、errors-only 邏輯未暴露。（原記「`InspectorSearchBar` 元件存在但未接入」，2026-07-24 實查更正：**查無此符號**，`network_tab.dart` 內是私有的 `_SearchBar`，不可直接重用。）
> * **#2 做法 A（±5s 側欄）**：完全無程式碼。
> * **新增提案**：新增第四部分，提出 9 項新功能提案。
> 
> **📝 早期里程碑**：
> * **v1.5.0**：發現 **#3 一鍵診斷報告** 已完成（`buildDiagnosticReport` 及 `ExportReportSheet`）。**#9 診斷報告 Timeline 重設計** 於 PR #87 完成。**#10 WebView Inline Debugging** 於 PR #91 完成。
> * **v1.3.0**：完成 **#4 Dio 結構化錯誤捕捉**，並確認 **#7 錯誤聚合摘要** 已實作。
> * **v1.1.0**：Console 重構為混合時間軸（PR #40/#42），**#2 升級為 🟡**。PR #51 完成 **#8 當前路由堆疊可視化**。

| # | 功能 | 狀態 | 備註 |
|---|------|:---:|------|
| **#9** | **診斷報告 Timeline 重設計** | **✅** | PR #87：`## Logs` → 按 `timestamp` 降序交錯四層的 `## Timeline` 混合串流；新增 `buildLogOneLiner`/`buildNetworkOneLiner` 單行 formatter，`errorsOnly` 升級為過濾整條 stream，`## Network`/`## Navigation`/`## Database` detail section 不動 |
| #1 | 全局未捕捉例外捕捉 | ✅ | PR #30：`captureUncaughtErrors`(default off) + 三掛點 chain。**去重已補（PR #96）**：`FlutterError.onError` 與 `ErrorWidget.builder` 對同一 build 崩潰收到同一 `FlutterErrorDetails`，`_logFlutterError` 以 object-identity（`identical`）去重，Console 只記錄一次（見第四部分 §D2） |
| #6 | 網路請求重放 | ✅ | PR #36 / v1.0.0 已完成：支援 per-Dio 原樣重送、`isReplay` 標記、狀態回饋與防連點保護 |
| #8 | 當前路由堆疊可視化 | ✅ | PR #51（Issue #50）：新增 `NavigatorStackResolver` 純 Dart 重播器，`NavigatorTab` 以 `ChoiceChip` 切換「當前堆疊」（垂直卡片）與「事件歷史」 |
| #2 | 跨 Inspector 時序關聯 | 🟡 | **v1.1.0 大幅推進**：ConsoleTab 已改用 `mergedTimeline`（四 buffer 按 `timestamp` 歸併排序），即文件「做法 B：Timeline 視圖」的本體已成；**缺** 做法 A（detail view 的 ±5s 同時段側欄，完全無程式碼） |
| #4 | Dio 結構化錯誤捕捉 | ✅ | v1.3.0：`NetworkEntry.errorType`(`DioExceptionType`)/`errorStackTrace` 欄位、`response==null` 傳輸層失敗 vs `!=null` server 錯誤的分類判斷、`NetworkDetailView` 的 Exception Details section、純文字匯出皆已落地 |
| #5 | ConsoleTab 排查化 | ✅ | `LogDetailView`(stackTrace/data/分享) 完成；搜尋欄 / LogLevel FilterChip / `⚡ Errors only` 快捷已於 **PR #128（2026-08-14）** 補齊，並附「點擊過濾結果 → 清過濾 + 捲回該筆」（§D1 與 §P5 合併落地）。過濾邏輯為新寫的 `console_utils.dart`（`ConsoleFilter` + `applyConsoleFilter()`），吃四源混合流；`entriesAtLevel()` 因回傳型別接不上而**未採用**，UI 過濾仍零呼叫（見第四部分 §D1） |
| #3 | 一鍵診斷報告 | ✅ | 已實作：提供 `buildDiagnosticReport` 產生 Markdown 報告，並在 Dashboard 實作 `ExportReportSheet` 匯出 |
| #7 | 錯誤聚合摘要 | ✅ | v1.3.0 已實作：新增 NetworkErrorGroup 聚合模型與 _ErrorSummaryBanner / _ErrorGroupCard UI 元件 |
| #10 | WebView Inline Debugging（觀測層） | ✅ | PR #91：JS payload + host-injection bridge，把 WebView 的 console/error/fetch 映射為既有 `LogEntry`/`NetworkEntry` 入列 Timeline——零新相依、零 schema 變更（見第三部分） |

**Anti-features**（Profiler / 落盤 crash history / HAR timing / API mocking / WebView B 級除錯器 / 第五 source enum）— ✅ 正確地皆未實作，守住「不走向微核心」。

> **⚠️ 文件此前漏列的既有基建（2026-07-24 補記）**
> 對照實際 codebase 發現，系統通知的相關基建**早已存在**：
> 
> * **既有相依**：`flutter_local_notifications: ^22.0.0` 已存在於 `pubspec.yaml`。
> * **核心功能（自 v0.1.0 首發）**：已具備 opt-in 的系統通知功能。
>   * **入口**：`FlutterInspector(showNetworkNotification: false)`（預設為關閉）。
>   * **實作**：`NetworkNotifier`（分為 `_io` / `_web` 平台分支）搭配 `AlertThrottler`（2 秒節流窗）。
> * **實際行為**：
>   * 發送一則**持續更新的單一系統通知**，摘要顯示「最新一筆網路呼叫 + 總數」。
>   * 點擊通知可直接打開 Network tab。
>   * 具備安全降級機制：初始化或權限失敗時轉為 no-op；Web build 實作 no-op stub 以保證 WASM 相容。
> 
> **更正結論**：
> 此前的缺口分析（含 anti-feature 判斷與 §P1）未盤點到此區塊，導致「通知類＝未實作／需引入新相依」的誤判。實際上，**相依與節流器都已就位**，任何後續的「錯誤告警」提案皆屬於既有基建的**擴充**，而非從零新建。

**進度結論（v1.8.0，含 2026-07-27 更新）**：原始 10 項裡 9 項完全完成（#1、#3、#4、#6、#7、#8、#9、#10，以及 v1.1.0 實質完成的 #2 時序軸主體；#1 去重缺陷已由 PR #96 修復），**1 項半成品**（#5 console 搜尋/過濾）。第四部分提出的 9 項新提案中，§P7、§P13 與既有缺陷 §D6 皆已於 v1.8.0 完成。

---

## 🐧 三個鐵律問題

> 本節為初始設計階段的核心分析，保留作為決策紀錄。

1. **這是真實問題，還是腦補？**
   - 真實。掃描現有 codebase 後確認：**inspector 目前完全看不到「它沒被手動餵進來」的錯誤**——沒有任何全局例外捕捉，沒有 widget build error 攔截，Dio error 只存 `err.toString()` 丟掉了 stackTrace。錯誤排查工具卻是「錯誤的盲人」。
2. **有沒有更簡單的方法？**
   - 有，而且核心抽象都已存在。`RingBuffer`、`InspectorRegistry`、各 `*Inspector` 的 `add()`、`@immutable` 的 entry models、`LogEntry.stackTrace`（已定義卻沒人用）、共用 `timestamp`——排查能力幾乎都能靠**組合既有零件**長出來，不需要新框架。
3. **這會破壞什麼嗎？**
   - 不會。全部以擴充式設計：新增可選建構參數（default off）、新增 getter、新增 UI section。**絕不改動既有 `FlutterInspector` 公開 API 的行為**。

---

## 🔍 排查能力現況盤點

> **當前現況快照（v2.3.0 · 2026-08-23 實查更新）**：相較於初期有四個紅燈的盲區，經過多次迭代後，排查基礎建設已補齊。v1.8.0 補上 App 生命週期標記與 Error 視覺高亮強化、修復 Inspector 污染 NavigatorTab；**v1.9.0 週期的 PR #128 補齊 Console 搜尋/過濾，最後一盞紅燈已滅**。
>
> ⚠️ **本表原以 v1.8.0 為準且未隨後續版本更新**（原記「紅燈僅剩 Console 搜尋/過濾；黃燈僅剩 ±5s 側欄」），兩處皆已過期：紅燈已於 PR #128 滅；**±5s 側欄（§D3）已於 2026-07-24 否決，不該再計為黃燈缺口**——該需求的覆蓋者是既有的 `mergedTimeline()`，完整時間軸不預先挑什麼相關，把所有維度攤平讓排查者自己判斷。

| 排查環節 | 現況 (v1.8.0) | 評級 |
|---|---|---|
| 看見「我主動 log 的」錯誤 | `inspector.log()` 正常記錄；`LogDetailView` 支援展開與分享，ConsoleTab 已新增 error 淡紅底高亮（PR #101） | ✅ 完善 |
| 看見「未捕捉」的例外 | 已實作 `captureUncaughtErrors`；同一 build 崩潰重複記錄已去重消除（PR #96） | ✅ 完善 |
| 看見網路失敗的根因 | 擷取 `err.type` 與 `stackTrace`；網路失敗判定收斂於 `NetworkEntry.isFailed`，且傳輸失敗也會產生群組摘要，並套用 error 高亮（PR #101） | ✅ 已修復 |
| 關聯「錯誤前後發生了什麼」 | `mergedTimeline` 將四層事件歸併；v1.8.0 補上 `LifecycleHandler` 標記前景/背景與 top-most page（PR #100）；PR #128 補上「點擊過濾結果 → 清過濾 + 捲回該筆」的聚焦動線。~~±5s 側欄~~ 已否決（§D3），需求由 `mergedTimeline()` 覆蓋 | ✅ 完善 |
| 帶走排查證據 | `buildDiagnosticReport`／`ExportReportSheet` 落地，`## Timeline` 四層交錯直接看出跨層因果 | ✅ 完善 |
| 過濾定位 error log | 搜尋欄 / LogLevel FilterChip / `⚡ Errors only` 已於 **PR #128**（2026-08-14）補齊，過濾邏輯為新寫的 `console_utils.dart`（`ConsoleFilter` + `applyConsoleFilter()`）吃四源混合流；`entriesAtLevel()` 因回傳型別接不上而未採用（見 §D1） | ✅ 完善 |
| 排除 Inspector 自身干擾 | `pushInspectorRoute` 實裝，Inspector detail view 不再污染使用者 NavigatorTab 軌跡 (§D6) | ✅ 完善 |
| 看見 WebView 內的事件 | 實作 `WebViewBridgeAdapter` 及 JS injection 腳本，無縫轉接日誌與請求；新增 `NetworkOrigin` 標記 | ✅ 完善 |

> 結論（2026-08-23 更新）：排查鏈條上的八個環節，如今**八個全綠**。v1.8.0 解決 NavigatorTab 污染、強化 Error 視覺並補上生命週期時間軸；v1.9.0 的 PR #128 補齊 Console 搜尋/過濾並滅掉最後一盞紅燈；原記的黃燈（±5s 側欄）為已否決項，不計為缺口。**盤點表全綠不等於沒有待辦**——剩餘待辦是加分項而非鏈條缺口，見「下一步實作路徑」的 Tier 2 與 Tier 4。

---

## ✅ 第零部分：診斷報告 Timeline 重設計（已完成 · PR #87）

### 9. 診斷報告 Timeline 重設計（Diagnostic Report Timeline Redesign）— ✅ 已完成（PR #87）
* **痛點**：`v1.5.0` 的 `buildDiagnosticReport` 將 LogEntry、NetworkEntry、NavigatorEntry、DatabaseEntry 輸出為四個獨立 section。排查時最關鍵的跨層因果關係（例：按鈕點擊 → API 呼叫 → 5xx → error log）在報告中完全斷裂，QA 拿到報告後仍需人工對齊時間戳才能還原事件脈絡。此外 `## Logs` section 格式冗長（每筆都含 General / StackTrace / Data 區塊），90% 無 stackTrace 的 entry 佔據大量垂直空間。
* **好品味設計（核心洞察）**：
  > 四個 buffer 的 entry 都已實作 `TimestampedEntry` 介面，共用 `timestamp` 欄位——這個共通基礎就是答案。不需要新資料模型。
  - 將 `## Logs` section 替換為 `## Timeline` section，以 `mergedTimeline()` 相同的歸併排序邏輯，將四層事件按 `timestamp` 降序交錯排列。
  - 每筆事件以**高密度單行格式**呈現，加上來源 tag：
    - `[HH:mm:ss] [LOG/{level}] {message}` — 有 stackTrace 時附加最多 3 行縮排
    - `[HH:mm:ss] [NET] {method} {path} → {status} ({duration}ms)` — 無 statusCode 時 `✗ {errorType}`
    - `[HH:mm:ss] [NAV] {action} {routeName}`
    - `[HH:mm:ss] [DB] {operation} {tableName} ({rows} rows)`
  - `errorsOnly` 旗標從「僅過濾 log」升級為「過濾整條 Timeline 串流」：只保留 error/warning log + 錯誤網路請求（`statusCode >= 400` 或 `errorType != null`）。
  - 獨立的 `## Network`、`## Navigation`、`## Database` detail section **保留不動**，提供完整 request/response payload。
* **重用**：`TimestampedEntry` 介面、各 entry model 的 `displayTime`、既有 `_writeSection` 工具函式、`buildCurl`/`buildPlainText` 序列化。
* **品味守則**：Timeline 只是既有 entry 的**格式化投影**，不複製資料、不引入新模型。section rename 是語義升級而非結構重構。
* **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **實作計畫**：見 [`docs/plans/2026-07-16-diagnostic-report-timeline-design.md`](../plans/2026-07-16-diagnostic-report-timeline-design.md)（design spec）與 [`docs/plans/2026-07-16-diagnostic-report-timeline-plan.md`](../plans/2026-07-16-diagnostic-report-timeline-plan.md)（implementation plan），兩個 Chunk：
  - **Chunk 1**：建立 `buildLogOneLiner()` / `buildNetworkOneLiner()` single-line formatters（修改 `log_formatters.dart` + `network_formatters.dart`）
  - **Chunk 2**：重構 `buildDiagnosticReport()`——移除獨立 Logs block、新增混合 Timeline builder、升級 `errorsOnly` 過濾邏輯
* **影響範圍**：`lib/src/utils/log_formatters.dart`、`lib/src/utils/network_formatters.dart`、`lib/src/utils/diagnostic_report.dart`、`test/utils/diagnostic_report_test.dart`
* **破壞性分析**：`buildDiagnosticReport()` 的輸出格式會改變（`## Logs` → `## Timeline`），但此函式目前僅供 `ExportReportSheet` 內部消費，**無外部 API 合約**，零破壞風險。
* **✅ 實作現況（PR #87 · 2026-07-17 合入 main）**：兩個 TDD commit 落地——`buildLogOneLiner`/`buildNetworkOneLiner` 單行 formatter（`log_formatters.dart`/`network_formatters.dart`），`buildDiagnosticReport` 的 `## Logs` 換為 `## Timeline` 混合串流（依 `sections` 合流四源 → `inWindow` 時窗 → `timestamp` 降序 → 逐筆單行）。與原設計的差異：時間戳復用既有 `displayTime` extension 故為毫秒級 `[HH:mm:ss.mmm]`；Timeline 以 `- {oneLiner}` inline list item 呈現（非 fenced block）並把 log 訊息換行壓平，結構上杜絕訊息內含 ``` 撐破 markdown。code review 另補強：CRLF／孤立 `\r` 一併壓平、`Uri.tryParse` 失敗時 fallback 於首個 `?`/`#` 截斷避免 query secret 外洩。`## Network`/`## Navigation`/`## Database` detail section 未動；log 的 `data` 與完整 stacktrace 不再進報告（僅 message + 前 3 frame）為刻意取捨。

---

## 🛠️ 第一部分：補上排查盲區（高優先 · 真正的缺口）

### 1. 全局未捕捉例外捕捉（Uncaught Error Capture）— ✅ 已完成（原 🔴 最大盲區）
* **痛點**：async error、widget build error、`onPressed` 裡漏接的 exception——這些**最常導致線上問題**的錯誤，inspector 一個都看不到，全靠開發者記得手動 try-catch + log。覆蓋率取決於人的自律，等於沒有。
* **好品味設計（關鍵洞察）**：
  > 不要為「捕捉錯誤」發明新的儲存與 UI。捕捉到的例外**就是一條 `LogLevel.error` 的 log**。
  - 新增**可選**入口 `FlutterInspector(captureUncaughtErrors: true)`（default **off**，絕不強制接管宿主 app 的錯誤流）。
  - 內部設置三個標準掛點，把例外轉成 `inspector.log(msg, level: error, stackTrace: ...)`：
    - `FlutterError.onError`（**chain 既有 handler**，不取代）→ framework 層 build/layout/paint error
    - `PlatformDispatcher.instance.onError` → 未捕捉的 async error
    - `ErrorWidget.builder` → 包裝既有 builder，記錄是哪個 widget build 失敗後再轉交原 builder
  - 對需要 `runZonedGuarded` 的情境，提供 `FlutterInspector.runGuarded(() => runApp(...))` 薄包裝，**不污染** `main()`。
* **重用**：`inspector.log()` + `LogEntry.stackTrace`（終於有人用它了）+ `RingBuffer`。零新模型。
* **品味守則**：chain 而非覆蓋既有 handler。捕捉後**必須**把錯誤往下游傳（`FlutterError.presentError` / 重拋），否則就違反「Never break userspace」——debug 工具不該吞掉宿主的崩潰。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **✅ 實作現況**：PR #30 已完成。`FlutterInspector(captureUncaughtErrors: false)` 入口 + `UncaughtErrorHandler` 三掛點（`FlutterError.onError` chain、`PlatformDispatcher.onError`、`ErrorWidget.builder`）皆落地。`runGuarded` 已移除改用 `PlatformDispatcher.onError`。
* **✅ 去重已補（PR #96 · 2026-07-24 合入 main）**：原缺陷為 `_logFlutterError(details)` 同時被 `FlutterError.onError` 與 `ErrorWidget.builder` 呼叫、`_attached` 旗標只防重複 `attach()` 不防重複 log，同一 build 崩潰產生 2 筆重複 error log。修復採 **object-identity 去重**：新增 `_lastLoggedDetails` 欄位，`_logFlutterError` 入口 `if (identical(details, _lastLoggedDetails)) return;`。同一 build 崩潰兩個 hook 收到的是同一物件（identity 恆真 → 吞第二筆）；兩次獨立崩潰即使訊息相同也是不同物件（identity 恆假 → 各自記錄），不誤吞短時間內的獨立錯誤。詳見 §D2。

### 2. 跨 Inspector 時序關聯（Correlated Timeline）— 🟡 部分完成（原 🔴 排查的靈魂）
* **痛點**：錯誤幾乎都是跨層的——「點了某按鈕（nav）→ 發了某 API（network）→ 5xx → 印了某 error log」。但現在這四件事躺在四個孤立 buffer 裡，開發者得在四個 tab 之間用肉眼對時間戳，這是排查最大的摩擦。
* **好品味設計**：
  > 四個 buffer 共用 `timestamp`——這個共通欄位就是答案，不需要新資料管線。
  - **做法 A（先做，低成本）**：在 `NetworkDetailView` 與（規劃中的）`LogDetailView` 裡，加一個「同時段事件（±5s）」側欄。一個 `_eventsAround(timestamp, window)` 工具函式掃 registry 的各 buffer，按時序列出，點擊跳轉。
  - **做法 B（後做，高價值）**：新增 **Timeline 視圖**——一個 `TimelineEvent`（type: log/network/nav/db 的薄 union）按 `timestamp` merge-sort 後的混合時間軸，`error` 級事件標紅旗。這是把「故障全景」一眼攤開。
* **重用**：各 entry 的 `timestamp`、`InspectorRegistry` 已持有四個 buffer、`LogLevel` 配色、`KeyValueTable`。
* **品味守則**：`TimelineEvent` 只是**指標包裝**（指向既有 entry），不複製資料、不引入第二份真相。
* **Effort**：A=low / B=medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **🟡 實作現況（v1.1.0 / PR #40 #42）**：**做法 B 已落地，且實作得比原構想更乾淨**——沒有引入 `TimelineEvent` union，而是讓四個 entry model 共同實作 `TimestampedEntry` 介面，由 `InspectorRegistry.mergedTimeline()` 把四個 `RingBuffer` 拍扁後依 `timestamp` 降序歸併排序，`ConsoleTab` 直接渲染（`ConsoleTab` 的 `build()` 內呼叫 `inspector.mergedTimeline(sources: _selected)`），按 entry runtime type 動態分派渲染、點 Network 列跳 `NetworkDetailView`。這同時消滅了 v1.1.0 前「鏡射到 console log 的廉價替代」（見本文件頂部與 overview 的歷史演進）。**做法 A 已否決（2026-07-24）**：原提案的「±5s 同時段側欄」經重新檢視三個鐵律問題後判定固定時間窗與「找因果」目標不匹配（事件密集時是噪音、稀疏時視窗太窄），不再排入 Phase Plan，詳見第四部分 §D3 的否決紀錄；該需求改由 §P2 錯誤上下文快照覆蓋。

### 3. 一鍵診斷報告（Diagnostic Report）— ✅ 已完成（原 🔴 QA 提 bug 的剛需）
* **痛點**：QA 重現 bug 後，要手動切四個 tab、逐筆截圖/複製、再手打 device/OS/版本資訊。耗時且容易漏，回報品質參差。
* **好品味設計**：
  - 新增 `buildDiagnosticReport(inspector, {timeRange, sections})`，輸出一份 **Markdown / JSON** 報告：device & app info 表頭 + 選定時間窗內的 log / network / nav / db 各區段。
  - Dashboard AppBar 新增「Export Diagnostic Report」action → 勾選區段 + 時間範圍（last 5m / 1h / all）+ 格式 → 走系統分享。
  - device/app info 用官方維護的 `package_info_plus` + `device_info_plus`（**可選相依**，未安裝時該區段降級為「N/A」，絕不崩）。
* **重用**：`network_formatters.dart` 的 `buildPlainText`/`buildCurl` 序列化模式、`share_text.dart` 平台自適應分享、各 buffer 的 newest-first snapshot getter。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐⭐
* **✅ 實作現況**：已於 `utils/diagnostic_report.dart` 實作 `buildDiagnosticReport`，並在 Dashboard AppBar 提供 `ExportReportSheet` 以匯出（包含時間範圍與錯誤篩選選項）。
* **✅ 缺口已補（v1.5.0 → PR #87）**：原匯出報告的 `## Logs` section 只含 `LogEntry`、四層各自獨立、無法看出跨層因果——此缺口已由 **#9 診斷報告 Timeline 重設計**（PR #87，2026-07-17 合入 main）解決：`## Logs` 換為按時序交錯四層的 `## Timeline` 混合串流。

### 4. Dio 錯誤的結構化捕捉（Structured Network Error）— ✅ 已完成
* **痛點**：`onError()` 只存 `err.toString()`，把 `DioException` 的結構資訊大部分丟了：**根因類型**（connectionTimeout / DNS / SSL / parse / cancel）與 `err.stackTrace`。注意：`statusCode` 已顯示在 `NetworkDetailView` 的 General section，4xx/5xx 錯誤是可辨識的；**真正的盲區是 `statusCode == null` 的傳輸層失敗**（斷網、DNS 失敗、SSL 握手錯誤、request cancel 等），目前這些一律只顯示一坨 toString() 字串，無法從 UI 分辨根因。
* **好品味設計**：
  - `dio_interceptor.onError` 改為擷取結構化欄位：`err.type`（分類）、`err.stackTrace`、`err.response?.statusCode`、保住 `err.response?.data`（伺服器的錯誤說明）。
  - 核心區分一條：**`response == null` → 傳輸層失敗（沒到 server）**；**`response != null` → server 回了錯誤碼**。這條判斷消滅了「Failed 到底是斷網還是後端壞了」的猜謎。
  - `NetworkDetailView` 新增「Exception Details」section 分層展示。
* **重用**：擴充 `NetworkEntry.error`（或加 `errorType` / `errorStackTrace` 欄位，保持 `@immutable`）、`DioExceptionType` enum、既有 detail view 的 card 分層。
* **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐
* **✅ 實作現況（v1.3.0）**：`dio_interceptor.onError` 已擷取 `err.type` 存入 `NetworkEntry.errorType`(`DioExceptionType`) 與 `err.stackTrace` 存入 `errorStackTrace`，連同既有的 `statusCode`/`responseHeaders`/`responseBody`。`NetworkDetailView` 新增「Exception Details」section，依 `entry.statusCode == null` 明確分流顯示「傳輸層失敗 (transport failure — request did not reach server)」或「Server 錯誤回應 (server responded with error)」，消滅了原先「Failed 到底是斷網還是後端壞了」的猜謎；純文字匯出（`network_formatters.dart`）亦包含 `Error Type` 與 stack trace。設計完全依照原規劃落地，無偏離。

### 5. ConsoleTab 排查化：stackTrace 詳情 + error 過濾 — ✅ 已完成
* **痛點**：error log 的 `stackTrace` 與 `data` 在 UI 完全看不到，列表項點了沒反應，500 條 log 無搜尋無過濾，error 跟 info 混成一片。
* **好品味設計**：
  - `LogDetailView`（仿 `NetworkDetailView`）：點 log 展開 message / level / **可複製 stackTrace** / `data`（用 `KeyValueTable`）。
  - 搜尋欄 + LogLevel FilterChip + 「errors only」快捷——直接套 `NetworkTab` 的搜尋/chip 模式與 `applyNetworkFilter` 邏輯框架，error log 終於能秒定位。
* **重用**：`NetworkTab` 搜尋 bar + FilterChip、`LogInspector.entriesAtLevel()`（已存在）、`KeyValueTable`、`NetworkDetailView` 佈局。
* **注意**：搜尋/過濾/詳情面板在上一份 brainstorm（已歸檔）中已列入。**此處只強調其排查價值並與 #2 的時序側欄、#3 的報告打包對齊**，避免重複規劃；實作時應一併考量。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐
* **✅ 實作現況（2026-08-14 · PR #128 補齊）**：`LogDetailView` 已完成（點擊展開、可複製 stackTrace 區段、Data 區段、分享），Console 列已加 chevron 標記可展開。搜尋欄、LogLevel FilterChip、errors-only 過濾亦已於 PR #128 落地，並附帶「點擊過濾結果跳回完整時間軸」。`entriesAtLevel()` 最終**未被採用**——它回傳 `List<LogEntry>`，接不上 ConsoleTab 的四源混合流，改以吃 `List<TimestampedEntry>` 的 `applyConsoleFilter()` 取代。**實作細節與落差見第四部分 §D1**。

---

## 🚀 第二部分：加分但非核心（中優先）

### 6. 網路請求重放（Replay / Resend）— ✅ 已完成（PR #36 / v1.0.0）
* **價值**：API 出錯時，原地重送（可改 header/body）即時確認「是否仍重現 / server 是否恢復」，免去複製 cURL 跳終端的 context switch。
* **設計**：`NetworkDetailView` 加「Resend」按鈕，從 entry 重建請求（沿用 `buildCurl()` 已證明的請求重組邏輯）經注入的 Dio 重送，結果作為新 `NetworkEntry` 記回 buffer。
* **重用**：`buildCurl()` 的請求重組、init 時傳入的 Dio client。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐
* **邊界**：只「重送原請求」。**不**做 mocking、不做腳本化改寫——那是 Proxyman/Charles 的地盤（見 anti-features）。
* **✅ 實作現況**：PR #36 / v1.0.0 已完成。`NetworkDetailView` 的「Resend」按鈕經原始 `sourceDio`（`WeakReference<Dio>`）原樣重送，重送結果以 `isReplay` 標記記回 buffer，並含狀態回饋與防連點保護。

### 7. 錯誤聚合摘要（Error Aggregation）— ✅ 已完成
* **價值**：同一個 502 每 30 秒打一次 → 現在是 500 條各自獨立的列表項。聚合成「502 Bad Gateway × N 次，最近 5 分鐘」一張卡，一眼看出是「持續故障」還是「偶發」。
* **設計**：`NetworkTab` 頂部「Error Summary」卡，按 `(statusCode, errorType)` 分組計數 + 首末時間。
* **重用**：`NetworkStatusGroup.matches()` 分組邏輯、`RingBuffer` 作資料源.
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐
* **✅ 實作現況**：v1.3.0 已實作。新增 `NetworkErrorGroup` 聚合模型與 `aggregateNetworkErrors(entries)` 聚合邏輯（定義於 `lib/src/utils/network_utils.dart`），並在 `lib/src/ui/dashboard/tabs/network_tab.dart` 中以 `_ErrorSummaryBanner`（包含 `_ErrorGroupCard` 元件）實作，支援折疊/展開顯示，以及點擊進行過濾篩選。

### 8. 當前路由堆疊可視化（Active Navigation Stack）— ✅ 已完成（PR #51）
* **價值**：排查「頁面有沒有被重複 push / 該 pop 沒 pop（記憶體洩漏前兆）」。錯誤發生時的路由堆疊也是 #3 診斷報告的關鍵 context。
* **設計**：`NavigatorObserver` 即時維護 `currentStack`，`NavigatorTab` 頂部以麵包屑顯示 Root→Top，偵測重複 push 時標 warning。
* **重用**：既有 push/pop/replace 回調、`KeyValueTable`。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐
* **註**：與上一份 brainstorm 的「Navigator Stack Visualizer」同一構想，此處定位為「為診斷報告提供 crash 當下路由快照」。
* **✅ 實作現況**：PR #51（Issue #50）已完成。新增 `NavigatorStackResolver`（`lib/src/inspectors/navigator_stack_resolver.dart`）純 Dart 重播器，將 `navigatorEntries`（newest-first）反轉回時序後重播 push/pop/replace/remove，推導出 top-first 當前堆疊；`NavigatorTab` 以 `ChoiceChip`（`_Tab` 私有元件）在「當前堆疊」（垂直卡片，顯示 `displayName` + `routeName`，頂部路由標 `Current` 標籤 + `visibility` 圖示）與既有「事件歷史」之間切換，模式切換器與 refresh / delete 工具列並排於同一 Row。採**垂直卡片**而非麵包屑（經 STAGE 0a 規格確認調整，理由見 `docs/features/2026-07-01-navigator-active-stack.md`）；replace/remove 的歧義情況採明確可預測的 best-effort 規則，不做 nested Navigator 多樹精確還原。

---

## 🕸️ 第三部分：新戰場——WebView 觀測層（新提案 · 2026-07-18）

### 10. WebView Inline Debugging（WebView 觀測層）— ✅ 已完成 (PR #91)
* **痛點**：宿主 app 一旦嵌了 WebView（H5 活動頁、支付頁、混合頁），inspector 就瞎了：頁內 `console.log`、JS error、`fetch` 全部隱形。開發者被迫外接 chrome://inspect（Android）或 Safari Web Inspector（iOS 16.4+ 還得逐 WebView opt-in），QA 裝置上完全無解。[flutter/flutter#32908](https://github.com/flutter/flutter/issues/32908) 在許願此能力；本 repo `lib/` 零 webview 程式碼——真盲區，非重複造輪。
* **先拆穿一件事**：「WebView debug」是兩個等級——**A 觀測層**（console / JS error / fetch，JS 注入即可，vConsole / Eruda / iOS WebDebug 類 app 全是這套）與 **B 除錯器層**（breakpoint / step / DOM inspector / profiler，需要 CDP，inline 做不到也不該模擬）。本提案**只做 A**；B 進 anti-features（#5）。
* **好品味設計（核心洞察）**：
  > WebView 的 `console.log` **就是**一筆 `LogEntry`；WebView 的 `fetch` **就是**一筆 `NetworkEntry`。這是「多一個事件來源」，不是「多一個系統」——#2/#9 的 `TimestampedEntry` + `mergedTimeline()` 地基讓 Console tab、Network tab、#7 error aggregation、#3 匯出報告**全部免費得到 WebView 支援**。
  - 映射**零 schema 變更**：`console.*` → `LogEntry`（`level` ← console method；provenance 塞既有 `data` Map：`{'origin': 'webview', 'pageUrl': ...}`，UI 要不要加小圖示是 presentation 層的事，資料層無感）；`window.onerror` / `unhandledrejection` → error 級 `LogEntry`（JS stack 入 `stackTrace`）；`fetch` / XHR → `NetworkEntry`（`errorType` / `sourceDio` 本為 nullable，填 null 即入列；副作用：**Replay 對 WebView 請求自然不可用**——正確的降級而非缺陷，UI 既有 null 檢查已處理）。
  - 三個件、**零新相依**（host-injection 模式第三次複用，前兩次：`DiagnosticInfoSource`、`DatabaseBrowserSource`）：
    1. `inspectorWebViewBridgeJs`（Dart 常數字串）——hook `console.*` / `window.onerror` / `unhandledrejection` / `fetch` / XHR，統一 JSON 訊息協定 postMessage 給 native，**JS 端截斷大 payload**（與 `RingBuffer` 同哲學：上限在源頭）
    2. `WebViewBridgeAdapter`——decode → 轉 `LogEntry` / `NetworkEntry` → 進 registry，headers/body 過既有 redaction 管線，不開後門
    3. README 雙套件接線範例（webview_flutter / flutter_inappwebview 各一段，宿主端約五行：建 JavaScriptChannel → onMessage 轉 adapter → 載入時注入）
  - **Phase 0 零成本先行**：README 加「Eruda 快速接線」食譜（`runJavaScript` 一行載 CDN，立刻獲得頁內 debug 面板）——先服務需求並驗證熱度；頁內面板與 native timeline 無關聯，**不取代 bridge，只是墊檔**。
* **競品缺口（2026-07 調查）**：[inappwebview_inspector](https://pub.dev/packages/inappwebview_inspector) 僅 console + JS REPL 且綁死 flutter_inappwebview；[vConsole](https://github.com/Tencent/vConsole) / [Eruda](https://github.com/liriliri/eruda) 面板畫在網頁裡、換頁即重置、與 native 世界隔絕。**「native 事件與 WebView fetch 同一條時間軸」沒有人做**——恰是頁內工具結構上做不到、又恰是本套件 Timeline 地基的自然延伸。
* **重用**：`InspectorRegistry` 的 log/network buffer、`redaction.dart`、`LogLevel` 對應、`mergedTimeline()` / 報告全鏈路。
* **品味守則**：adapter 是**翻譯器不是系統**——不持有 buffer、不做 UI、不引入第二份真相。不加第五個 source enum、不開 WebView 專屬 tab（見 anti-features #6）。
* **風險（plan 階段逐一處理）**：① **注入時機**——`runJavaScript` 於頁面載入後執行會漏早期 log，吃到全部需 documentStart 注入（flutter_inappwebview 的 `UserScript` 完整支援；webview_flutter 抽象層較弱）——host 接線文檔明示各自能與不能，套件不吞；② **敏感資料**——WebView fetch 的 headers/body 必過 `redactSensitiveData` 管線，任何入口不得繞過 opt-out 行為；③ **bridge 流量**——大 response body 序列化過 channel 會卡 UI thread，JS 端截斷（如 body 上限 32KB + `truncated` 旗標），非 Dart 端事後補救；④ **不可信輸入**——WebView 內容視同惡意來源，走 #9 已加固的 CRLF / malformed-URL 清洗路徑並補驗證；⑤ **iframe 不支援**——注入只作用於 main frame，v1 明文不支援（README 註明），不偷做跨 frame 橋接；⑥ **`setOnConsoleMessage` 誘惑**——webview_flutter 4.x 原生可收 console 看似免注入，但 [iOS 有遞迴物件 logging bug](https://github.com/flutter/flutter/issues/144535) 且只覆蓋 console（無 fetch/error），只能當降級備援，不能當主路徑。
* **Effort**：Phase 0=trivial / bridge 主體=medium ｜ **排查價值**：⭐⭐⭐⭐⭐（混合開發場景的最後盲區）
* **✅ 實作現況（PR #91 · v1.7.0）**：已完成實作。包含提供 JS injection payload、`WebViewBridgeAdapter` 轉換層，能將 console 訊息與 XHR/fetch 網路請求平滑轉入 `LogEntry` 與 `NetworkEntry` 中，並順暢整合進現有 Timeline。新增 `NetworkOrigin` enum 區分 `dio` / `webview` / `http` 來源。

---

## 🔬 第四部分：功能缺口深度分析與新功能提案（2026-07-23 新增）

> 本節基於 v1.8.0 codebase 的全面比對分析，包含三類內容：
> - **§D1–D4**：原始 10 項功能中的殘留缺口，附實作方案
> - **§P1–P9**：新功能提案，全部聚焦「快速排查 / 輔助定位錯誤」
> - **完整優先順序總表**：13 項合併排序
>
> 核心原則不變：**不是新系統，是既有零件的重新組合**。零新模型、零新相依。

### §D1. ConsoleTab 搜尋 + LogLevel 過濾（#5 剩餘缺口）— ✅ 已完成（PR #128 · 2026-08-14，與 §P5 合併落地）

> **這是排查鏈上唯一的紅燈。** 500+ 條混合 timeline，error log 跟 info/debug 混成一片，開發者只能肉眼掃描。

**缺口明細（v1.8.0 實查）**：

| 缺口 | 現況 | 參考實作 |
|------|------|----------|
| 搜尋欄 | ❌ `_SearchBar` 元件已存在於 `network_tab.dart` 但 ConsoleTab 未接入 | `NetworkTab._SearchBar` 的 `TextField` + `onChanged` 模式 |
| LogLevel FilterChip | ❌ 完全不存在 | NetworkTab 的 `_FilterChips`（HTTP Method + Status Group） |
| errors-only 快捷切換 | ❌ `errorsOnly` 邏輯僅存在於 `diagnostic_report.dart`，UI 未暴露 | `ExportReportSheet` 的 Checkbox |
| `entriesAtLevel()` | ❌ 定義於 `LogInspector`（L20）且有測試，但**零 UI 呼叫** | — |

**設計方向**（Linus 式「偷懶」策略——直接鏡射 NetworkTab 的搜尋/過濾架構）：
- ConsoleTab 頂部加 `_SearchBar`（搜尋 `message` / `stackTrace` / `url` 內容）
- LogLevel 作為 `FilterChip` 一排（verbose / debug / info / warning / error），支援多選
- 新增 `errors-only` 快捷 Chip（等價於只選 `warning` + `error` level + 失敗網路請求）
- 搜尋 + 來源過濾 + LogLevel 過濾三者正交疊加
- 建立 `ConsoleFilter` + `applyConsoleFilter()` 純函式（鏡射 `NetworkFilter` / `applyNetworkFilter()`）
- **影響範圍**：`lib/src/ui/dashboard/tabs/console_tab.dart`（主改）、可選新增 `lib/src/utils/console_utils.dart`（過濾邏輯）
- **Effort**：low–medium ｜ **排查價值**：~~⭐⭐⭐⭐⭐~~ → **⭐⭐⭐（降級，見下）**

> **⚠️ 重新定性（2026-07-24 · 查核 `network_tab.dart` 實作後）**
>
> **① 搜尋語意＝過濾，不是捲動**。既有 `NetworkTab` 的 `build()` 把 `applyNetworkFilter()` 結果直接餵 `ListView.builder`，不匹配的 entry 根本不建立，空了顯示 `'No matches'`，全程無 `ScrollController`。ConsoleTab 應沿用過濾語意——捲動語意在此會壞掉：Console 是**持續有新事件湧入**的混合流，捲到第 300 筆後新事件進來會把目標推走，要修就得引入「錨定 entry identity + 重算 index」的捲動狀態管理，為一個搜尋框長出一套機制。
>
> **② 但過濾對「因果推斷」有本質缺陷**。搜「timeout」剩 3 筆 error，而前後的 API 呼叫與路由跳轉**全被濾掉**——排查要的不是「這筆 error 長什麼樣」，是「為什麼走到這裡」。過濾是**點查詢**（你已知道要找什麼），排查是**鏈推斷**（你不知道要找什麼）。更根本的問題是搜尋要求你**先知道關鍵字**，而難查的 bug 恰恰是不知道該搜什麼的那種。本節原標為 🔴 紅燈，實際上紅在「ConsoleTab 缺 NetworkTab 有的東西」的**功能對稱性**，不是**排查能力**——兩者被混為一談。
>
> **③ 修正方向：與 §P5 合併**。過濾完要能跳回完整脈絡——搜到 3 筆後點其中一筆 → **清掉過濾 + Timeline 捲到該位置**，站回完整時間軸看前後。這是 §D1 的過濾 + §P5 的 `ScrollController.animateTo` 兩個零件的組合，不需第三個機制；也正好是 §D3 ±5s 側欄想解決卻解錯的問題（側欄的錯在「固定窗 + 另開列表」，跳回主軸讓使用者自己決定往前看多遠）。**§D1 與 §P5 應合併為一項排程**，不該分居 Phase 1 與 Phase 4。
>
> **④ 上表兩處「已存在」的估計不準確**：
> - `InspectorSearchBar` **查無此符號**；`network_tab.dart` 內是**私有的 `_SearchBar`**，需先提取為共用元件或複製一份
> - `entriesAtLevel()` 回傳 `List<LogEntry>`，而 ConsoleTab 渲染的是 `mergedTimeline` 的**四源混合流**（log/network/nav/db）——**接不上**，需另寫吃 `List<TimestampedEntry>` 的過濾函式
>
> 故此項非「接線」等級，是「照 `applyNetworkFilter` 模式新寫 `applyConsoleFilter` + 提取搜尋元件」。仍在 low–med，但沒有原文暗示的那麼便宜。

**✅ 實作現況（2026-08-14 · PR #128）**：依上述 ③ 的修正方向，與 §P5 **合併為一項**落地。

* **新增** `lib/src/utils/console_utils.dart`：`ConsoleFilter`（keyword + `Set<LogLevel>` + `errorsOnly`）與 `applyConsoleFilter()` 純函式，鏡射 `NetworkFilter` / `applyNetworkFilter()`。關鍵字比對依 entry 型別分派，吃的是 `List<TimestampedEntry>` 混合流——正是 ④ 指出 `entriesAtLevel()` 接不上的那個缺口。
* **`console_tab.dart`**：接入搜尋欄、LogLevel FilterChip 一排、`⚡ Errors only` 快捷 chip；搜尋 / 來源 / LogLevel 三者正交疊加。`errorsOnly` 與 LogLevel 為**互斥語意**（開快捷即清空 level 選擇），避免留下不生效的選擇。
* **跳回完整脈絡（§P5 零件）**：過濾生效時點擊某列 → 清空全部過濾條件 + `ScrollController.animateTo` 捲到該筆位置。捲動前 `await SchedulerBinding.instance.endOfFrame`，否則會被過濾後較短的 scroll extent 夾住；偏移量以固定列高近似（`_kApproxRowHeight`），落在目標附近即可。
* **與原提案的落差**：§P5 原設計的「⬆ Jump to Latest Error」FAB 未採用——合併後的入口是「點擊過濾結果」，由 `_JumpRow` 承接。這是 ③ 合併決策的預期結果（取捲動零件、不取 FAB 入口），非殘留缺口。
* **Review 補正**：`TextEditingController` 原由 `_SearchBar` 私有持有，導致跳轉清掉 `_filter` 後輸入框仍殘留舊關鍵字；已將所有權提升至 `_ConsoleTabState` 並於跳轉時同步清空（附回歸測試）。
* **測試**：`test/utils/console_utils_test.dart`（過濾語意）＋ `test/ui/tabs/console_tab_test.dart`（跳轉、正交疊加、long-press 書籤不被跳轉接管）。

> **⚠️ 後續修正（2026-08-23 · PR #140）：本項落地時留下 chip 語意重疊，已移除 `Error` level chip。**
>
> 上述「`errorsOnly` 與 LogLevel 為互斥語意」解決的是**狀態**衝突（兩者不會同時生效），但沒解決**命名**衝突——`⚡ Errors only` 與 `Error` 兩個 chip 並排，名字讀起來是同一個 filter，實際行為卻不同：
>
> | | `⚡ Errors only` | `Error` chip |
> |:---|:---|:---|
> | warning log | ✅ 留 | ❌ 濾掉 |
> | error log | ✅ 留 | ✅ 留 |
> | **成功**的網路請求 | ❌ 濾掉 | ✅ **留** |
> | 導航 / DB 事件 | ❌ 濾掉 | ✅ **留** |
>
> 差異源自 `_matchesLevel` 的正確設計：level 約束**只作用於 `LogEntry`**，非 log 一律放行——否則選一個 level chip 就會把網路/導航/DB 全部濾掉，讓 level filter 悄悄變成 source filter。這個設計沒錯，錯在讓它與 `Errors only` 並排且名字幾乎一樣，使用者無從分辨。
>
> **修正**：移除 `Error` level chip，`⚡ Errors only` 成為看失敗的唯一入口。`Warning` chip 保留——`Errors only` 的 warning 覆蓋與 error、失敗請求綁在一起，跟「只看 warning」不是同一件事。實作上把 chip 列的迴圈由 `LogLevel.values` 改走 `logLevelLabels.entries`，讓 label map 成為「有哪些 chip」的唯一真相來源（刪 entry 即刪 chip，迴圈內不需 `if`）。`ConsoleFilter.levels` 刻意保留 `Set<LogLevel>` 不收窄——model 層仍接受 `LogLevel.error`，只拿掉 UI 入口，收窄會在 `_matchesLevel` 多一個特殊情況。
>
> **這是一種新的「文件與實況不符」，不計入既有的漂移計數**：累計 7 次那個計數追蹤的是「標為待辦、實際已完成」（狀態欄漂移），本項不屬於該型態——§D1 的狀態欄是對的，它確實已完成。這裡漏記的是**已完成項目留下的缺陷**：實作現況寫得詳盡，卻沒人注意到新增的 chip 列本身引入了語意重疊。**教訓：實作現況該記的不只「做了什麼」，還有「做完後這塊 UI 長什麼樣、有沒有新的並排衝突」。**

### §D2. 未捕捉例外去重修復（#1 殘留缺陷）— ✅ 已完成（PR #96 · 2026-07-24）

> 同一個 widget build 崩潰，`FlutterError.onError` 和 `ErrorWidget.builder` 各觸發一次 `_logFlutterError`，Console 出現兩筆完全相同的 error log，干擾判斷「是一次還是兩次」。

**原缺陷確認**：`UncaughtErrorHandler`（`lib/src/core/uncaught_error_handler.dart`）的 `attach()` 中，`FlutterError.onError` 與 `ErrorWidget.builder` 各自呼叫 `_logFlutterError(details, ...)`，`_attached` 旗標只防重複 `attach()`，**不防同一 exception 被兩個 hook 重複 log**。

**實際實作（PR #96，刻意偏離原構想）**：原設計提議 hashCode + 2 秒時間窗的 dedup ring，實作時判定那是為不存在的情境過度設計——framework 對同一 build 崩潰傳給兩個 hook 的是**同一個 `FlutterErrorDetails` 物件**，用 object identity 一步到位；且時間窗反而會誤吞「2 秒內兩次訊息相同的獨立崩潰」（各自是新物件，本該分別記錄）。最終方案（消滅特殊情況而非新增判斷）：
- 新增單一欄位 `FlutterErrorDetails? _lastLoggedDetails`
- `_logFlutterError` 入口：`if (identical(details, _lastLoggedDetails)) return;`，通過後更新 `_lastLoggedDetails`
- 無 Queue、無 hashCode、無時鐘、無魔術數字
- **影響範圍**：`lib/src/core/uncaught_error_handler.dart`（+ `test/core/uncaught_error_handler_test.dart` 新增 `dedup` / `no dedup` 兩測試）
- **Effort**：low（實際 low）｜ **排查價值**：⭐⭐⭐⭐
- **文件**：規格 [`docs/features/2026-07-23-uncaught-error-dedup.md`](../features/2026-07-23-uncaught-error-dedup.md)、計畫 [`docs/plans/2026-07-23-uncaught-error-dedup.md`](../plans/2026-07-23-uncaught-error-dedup.md)

### §D3. Detail View ±5s 同時段側欄（#2 做法 A）— ❌ 已否決（2026-07-24）

> 看到一筆 error log 後，想知道「這前後 5 秒內發生了什麼 API 呼叫、什麼路由跳轉」——目前只能回到 Console Timeline 肉眼搜。

**原設計方向**（保留作決策紀錄）：
- 在 `LogDetailView` / `NetworkDetailView` 底部加 `_NearbyEventsSection`
- 工具函式 `eventsAround(InspectorRegistry registry, DateTime center, Duration window)` 掃四個 buffer
- 展示 ±5s 內的其他事件（排除自身），點擊可跳轉對應 detail view
- 作為 `ExpansionTile` 預設收合，不影響既有頁面的載入效能

**❌ 否決理由（三個鐵律問題重新檢視）**：
1. **這是真實問題還是腦補？** 原始痛點是「detail view 孤立、看不到前後脈絡」，但「前後脈絡」的真正需求是**因果關係**，不是**時間鄰近**。固定 ±5s 時間窗跟這個目標本身不匹配：
   - **事件密集時**（連續操作、狂點、背景 polling）：±5s 塞進來的多半是無關噪音，跟現在「500 筆裡肉眼找」的摩擦沒有本質差異，只是換個地方繼續肉眼掃
   - **事件稀疏時**：真正相關的事件可能發生在 20 秒前（例如「進結帳頁」到「填完表單送出失敗」中間隔了填表單的時間），5 秒視窗反而抓不到
   - 調整視窗長度或改成固定筆數，都只是在兩個爛選項間換一個沒那麼爛的，無法真正解決「密集時太吵、稀疏時太窄」的兩難——這是設計假設（事件密度均勻）本身站不住腳，不是實作精度問題
2. **有沒有更簡單的方法？** 有，且已規劃：**§P2 錯誤上下文快照**——只在 error 發生當下快照真正相關的東西（路由堆疊、最後一次成功的 API），是精準的因果線索，而非時間鄰近的噪音列表。`mergedTimeline()`（§2 做法 B）也已經提供「按時序看全局」的能力，覆蓋了「回頭肉眼搜」的需求。
3. **結論**：§D3 從優先序列表移除，不再排入 Phase Plan。「detail view 缺乏上下文」的真實需求由 §P2 更準確地覆蓋。

### §D4. DatabaseTab 搜尋 / 過濾

> `DatabaseTab`（190 行 · 2026-08-13 實查，原記 131 行已過期）目前是四個 tab 中最原始的——純列表，無搜尋、無過濾、無聚合。

**設計方向**：
- 加入 `_SearchBar`（搜尋 table name / SQL operation）
- `DatabaseOperation` 作為 `FilterChip`（query / insert / update / delete）
- 模式完全對齊 NetworkTab
- **影響範圍**：`lib/src/ui/dashboard/tabs/database_tab.dart`
- **Effort**：low ｜ **排查價值**：⭐⭐⭐

---

### §D6. Inspector 自身頁面污染 NavigatorTab（既有缺陷）— ✅ 已完成（2026-07-27 實查確認）

> **這是既有 bug，不是新功能**。`_isInspectorRoute()` 只過濾 dashboard 本身，漏掉所有從 dashboard 內部 push 出去的 detail view——使用者在 inspector 裡的每一次點擊，都被當成他 app 的導航事件記進 NavigatorTab。

**實測證據（2026-07-26 以 probe test 驗證，非推論）**：

```
ENTRIES: [NavigatorAction.push/NetworkDetailView, NavigatorAction.push/SizedBox]
```

`NetworkDetailView` 確實出現在 `inspector.navigatorInspector.entries` 中。

**根因鏈**：
1. `dashboard_modal.dart:30` 的 `showGeneralDialog` **未指定 `useRootNavigator`**，Flutter 預設為 `true` → dashboard 掛在**宿主 app 的 root Navigator** 上，而該 Navigator 正是掛載 `FlutterInspectorNavigatorObserver` 的那一個。
2. dashboard 內的 detail view 以 `Navigator.of(context).push(...)` 推送，context 來自 dashboard 子樹 → 同樣落在被觀察的 root Navigator。
3. `navigator_observer.dart:17-18` 的 `_isInspectorRoute()` 只比對 `name == 'flutter_inspector_dashboard'`，而這些 detail view 的 `MaterialPageRoute` **完全沒帶 `RouteSettings.name`**（`name == null`）→ 過濾器一律放行。

**污染來源共 4 處**（全部無 route name）：

| 檔案 | 行 | 推送的頁面 |
|------|---|-----------|
| `tabs/network_tab.dart` | 187 | `NetworkDetailView` |
| `tabs/console_tab.dart` | 164 | `LogDetailView` |
| `tabs/console_tab.dart` | 178 | `NetworkDetailView` |
| `tabs/database_tab.dart` | 185 | （table rows 頁） |

> `tabs/database/table_rows_view.dart:116` 的 `showModalBottomSheet` 同樣未帶 name，但 bottom sheet 亦為 route，會觸發 `didPush`——一併納入。

**為何值得修**：污染量與使用者的排查強度**成正比**——越是深入追查（反覆開關 detail view），NavigatorTab 就被灌越多雜訊，正好在最需要乾淨導航軌跡時最髒。這違背了工具「不干擾被觀測對象」的基本原則（觀測者效應）。

**設計方向：✅ 已定案採方案 B**（2026-07-26 決定）

- ~~**方案 A**~~：逐一為 4 處 `MaterialPageRoute` 補上 `RouteSettings(name: 'flutter_inspector_*')`，`_isInspectorRoute` 改為 `startsWith` 比對。
  - **不採用**。**治標**——新增任何 detail view 都必須記得補 name，漏一個就再破一次，等於把正確性寄託在人的記憶上。這是在既有的 1 個判斷點旁再加第 5、第 6 個。
- **方案 B（定案）**：dashboard 內部推送統一走一個 helper（如 `pushInspectorRoute`），由它統一掛上帶前綴的 route name；`_isInspectorRoute` 只認這一個來源。
  - **消滅特殊情況**——新增頁面自動被涵蓋，不依賴呼叫端自律。符合「好品味」判準：把 4 個散落的判斷點收斂成 1 個。

**實作備忘（2026-07-26 探勘所得，動工時可直接用）**：
- 4 處呼叫端**全部是 `MaterialPageRoute` + `builder`**，形狀一致，單一 helper 即可覆蓋，無需為個別頁面開特例。
- `table_rows_view.dart:116` 的 `showModalBottomSheet` 形狀不同（非 `MaterialPageRoute`），需要 `routeSettings:` 參數另外處理——**別假設它能套同一個 helper**。
- helper 內建議加 `assert(name.startsWith(prefix))`，讓誤用在 debug build 當場炸出來，而非靜默漏過。
- `dashboard_modal.dart:32` 現有的 `'flutter_inspector_dashboard'` 字串常值應一併收進共用常數，否則前綴定義會有兩份。

- **影響範圍**：`lib/src/observers/navigator_observer.dart` + 上表 4 處呼叫端（+ `table_rows_view.dart`）
- **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐（直接影響 NavigatorTab 可信度）
- **⚠️ 動工前必查**：依 §P7 的教訓，先 grep 一次「dashboard 內還有幾處 push / showDialog / showModalBottomSheet」，上表是 2026-07-26 的快照，可能已增生。

---

### §P1. 錯誤爆發偵測 + 視覺警報（Error Spike Detection）— 🆕

> **痛點**：短時間內湧入大量 error（如 API 全面 5xx、WebView JS 狂報錯），Console 被淹沒但沒有任何**錯誤**告警機制（**釐清**：既有 `NetworkNotifier` 系統通知只摘要網路活動、不辨識 error）。開發者可能在看別的 tab、甚至把 app 切到背景，錯過爆發窗口。

* **設計**：
  - 在 `FlutterInspector` 層追蹤「最近 N 秒內的 error-level entry 計數」
  - 超過閾值（如 10 筆/30s）時，Dashboard 頂部彈出 `MaterialBanner`——「⚠️ 過去 30 秒偵測到 {N} 筆錯誤」，點擊跳轉 Console 並自動套用 errors-only 過濾
  - 零新模型，只是一個 `ValueNotifier<int>` + 閾值比較
* **重用**：既有 `RingBuffer` 的 timestamp 掃描、`LogLevel.error` 判別、`NetworkEntry` 的 error 判別（`statusCode >= 400 || error != null`）；**以及既有 `NetworkNotifier` + `AlertThrottler` 系統通知基建**（自 v0.1.0，`flutter_local_notifications` 已在相依）——`MaterialBanner` 只在前景可見時有效，據此基建可低成本延伸「app 在背景時的**系統通知**告警」，補上前景盲區。
* **品味守則**：告警是**讀取既有 buffer 的衍生狀態**，不引入第二份計數器。用 `AlertThrottler` 防止 banner 本身的爆發（該節流器已存在於通知模組，直接複用）。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐⭐

### ~~§P2. 錯誤上下文快照（Error Context Snapshot）~~ — ❌ 已否決（2026-07-24）

> **否決理由（2026-07-24 · 三個鐵律問題重新檢視）**：
>
> **1. 這是真實問題還是腦補？** 原痛點寫「瞬態上下文事後無法還原」——**這個前提不成立**。導航事件、網路事件本來就都在各自的 `RingBuffer` 裡，`mergedTimeline()` 已按時序把四源交錯排好。要看 error 前發生了什麼，Console tab 往上滑就是了。快照做的事是「把已經在 timeline 上的東西複製一份釘到 error 旁邊」，**省去對時間戳的便利，不是新資訊**。
>
> **2. 推導出來的東西不該當證據。** 原設計要快照 `NavigatorStackResolver` 推導的路由堆疊，但該 resolver 是**從觀察到的事件重放推導**的 best-effort 結果（原始碼註解自承），會因 `RingBuffer` 容量淘汰最早的 push、observer 掛載前的導航、nested Navigator 多樹混流、`_matches()` 只比對 routeName+widgetType 而失準。而報告裡一個標著「當時的路由堆疊」的欄位，讀者**會當成事實**。錯誤的證據比沒有證據更糟——會照著它推錯方向。
>
> **3. 最致命：它預設因果是單線的。** 快照挑「路由堆疊 + 最後成功的 API」兩個維度，等於預先假定「錯誤的原因就在這兩條線裡」。但真實錯誤往往是**綜合因素**——某個 API 回了非預期空值 ＋ 剛好切到背景 ＋ 前一次 db 寫入未完成。事先挑兩個維度釘上去，反而把注意力鎖死在那兩條線上，漏掉真正的交互作用。**這一點推翻的不是「挑錯維度」，是「挑維度」這件事本身**：完整時間軸不挑，它把所有維度攤平讓排查者自己判斷什麼相關——而那個東西已經存在。
>
> **與 §D3 同病**：兩者都想在 error 旁邊另闢一塊「相關資訊」，但「相關」只有排查的人邊看邊定義得出來，工具定義不了。§D3 用固定時間窗猜、§P2 用固定維度猜，都是猜。
>
> **結論**：移出所有 Phase / Tier，不排程。「error 缺乏上下文」的需求由既有 `mergedTimeline()` 覆蓋。下方原設計保留作決策紀錄。

> **痛點（原文，保留作紀錄）**：error log 或 network failure 發生時，有些**瞬態上下文**事後無法還原——「當時的路由堆疊是什麼」、「最後成功的 API 是哪個」。

* **設計**：
  - 每當捕捉到 error-level entry 時，自動快照 `NavigatorStackResolver.currentStack` 和最後一筆成功 `NetworkEntry`
  - 把快照塞入 `LogEntry.data`（`{'routeStack': [...], 'lastSuccessfulApi': '...'}`）
  - `LogDetailView` 的 Data section 已能渲染 Map——**零 UI 改動**
  - `buildDiagnosticReport` 的 Timeline 條目自然會包含這些 data
* **重用**：`NavigatorStackResolver`（已存在）、`LogEntry.data` Map（已定義）、`KeyValueTable`（已能渲染 Map）
* **品味守則**：快照**讀取既有資料結構**（NavigatorEntry buffer + NetworkEntry buffer），不維護自己的狀態。限制快照頻率（如 debounce 500ms 或只在首次 error 時快照）防高頻 error 場景效能問題。
* ~~**Effort**：low ｜ **排查價值**：⭐⭐⭐⭐⭐~~ → **不排程**，理由見本節開頭否決說明。

> **附帶更正**：原文提到的 `NavigatorStackResolver.currentStack` **這個 API 不存在**——實際只有純函式 `resolve(List<NavigatorEntry> entries)`，不持有狀態、無快取、無 getter。此更正對其他章節仍有效（勿再引用該 API 名稱）。

### §P3. Timeline 書籤 / 標記（Bookmark / Pin）— ✅ 已完成（PR #115）

> **痛點**：QA 重現 bug 時，想在 timeline 上標記「就是這裡出問題」，但匯出報告後，那個關鍵時刻淹沒在幾百筆事件裡。

* **設計**：
  - Timeline 列表項長按 → 標記為 📌 bookmark
  - 匯出報告時 bookmark 條目加 `📌` 前綴，方便 grep
  - Bookmark 作為一個獨立的 `Set<DateTime>` 存在 `_ConsoleTabState` 中（不修改 entry model——好品味：UI 狀態不汙染資料模型）
  - ConsoleTab 加一個 FilterChip「Bookmarks Only」
* **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐

### §P4. 快速複製 Diagnostic Snippet（一鍵複製 cURL + Error Payload）— 🆕

> **痛點**：開發者看到 API 失敗後，需要手動從 `NetworkDetailView` 複製 cURL、再從 error response 複製 body、再手動拼成一段完整的 bug report——步驟太多。

* **設計**：
  - `NetworkDetailView` 新增「Copy Diagnostic Snippet」按鈕
  - 一鍵組合：cURL + response status + error body + error type + timestamp → clipboard
  - 格式：Markdown fenced block（直接貼到 GitHub Issue / Slack）
* **重用**：`buildCurl()`、`buildPlainText()`、`share_text.dart`
* **Effort**：low ｜ **排查價值**：⭐⭐⭐
* **🔍 實查現況（2026-08-06）**：**仍未實作**，但既有零件比原估計更完整，effort 應下修為 trivial~low。
  - **已存在且可直接重用**：`network_formatters.dart:101` 的 `buildCurl(entry, redact:)`、
    同檔的 `buildPlainText(entry, redact:)`、`share_text.dart` 的 `shareText()`——三者皆已
    接上 `redactSensitiveData` 旗標，新按鈕沿用即可，不需自行處理遮罩。
  - **已存在的相鄰 UI**：`lib/src/ui/dashboard/tabs/network/network_detail_view.dart:38-50`
    已有 `PopupMenuButton<_ShareAction>` 含三個選項（`curl` / `text` / `share`，enum 定義於 `:13`），
    本項是**在既有選單多加一個 `_ShareAction` 值**，不是新建按鈕；
    `line 170` 的 'Exception Details' section 已備妥 error payload 的呈現面。
    ⚠️ **路徑校正 (2026-08-06)**：此檔曾位於 `ui/dashboard/views/`，現已搬至
    `ui/dashboard/tabs/network/`（`log_detail_view.dart` 同步搬至 `tabs/console/`）。
    本文件其餘處若出現 `views/` 路徑均已過期，動工時以 `tabs/<domain>/` 為準。
  - ⚠️ **第二次路徑校正 (2026-08-23)**：上一則只校正了 **detail view**，但本項要改的另一半 **formatter 不在該目錄**——
    `buildCurl` / `buildPlainText` 實際位於 **`lib/src/utils/network_formatters.dart`**（`:105` / `:136`），
    `tabs/network/` 下只有 `network_detail_view.dart` 一支。本項的寫入路徑因此橫跨兩處：
    `utils/network_formatters.dart`（新增 formatter）+ `tabs/network/network_detail_view.dart`（`:13` enum 加一個值）。
  - **真正缺的只有**：把 cURL + status + error body + errorType + timestamp 組成單一
    Markdown fenced block 的 formatter（`network_formatters.dart` 新增一個函式）。
  - ⚠️ 注意 `diagnostic_report.dart:186` 已記載「固定 3-backtick fence 會被內容中的 fence 打斷」
    的既有教訓，新 formatter 產 fenced block 時沿用該處的處理方式，勿重寫一份。

### §P5. Console Timeline 自動跳轉最新 Error（Jump to Latest Error）— ✅ 已完成（PR #128 · 2026-08-14，隨 §D1 合併落地）

> **痛點**：Timeline 按時序排列（newest first），但最新 error 可能不在最頂（之後有新的 info/debug log 進來）。需要手動滾動找紅點。

* **設計**：
  - ConsoleTab 浮動按鈕（FAB）「⬆ Jump to Latest Error」
  - 掃描 `_filteredTimeline()` 找第一筆 error-level entry 的 index，`ScrollController.animateTo`
  - 無 error 時 FAB 隱藏
* **Effort**：low ｜ **排查價值**：⭐⭐⭐
* **✅ 實作現況（2026-08-14 · PR #128）**：依 2026-07-24 的重排，本節已**併入 §D1 一併落地**——取的是 `ScrollController.animateTo` 捲動零件，入口則改為「過濾生效時點擊某列 → 清過濾 + 捲到該筆」。上方 FAB 設計是合併前的原始構想，**已被合併後的形狀取代，非殘留缺口**（合併理由見 §D1 重新定性 ③）。

### §P6. Dashboard 錯誤計數 Badge（Error Count Badge on Tabs）— ✅ 已完成（`b4846ea` · 2026-08-07）

> **痛點**：Dashboard 底部 tab 沒有任何數字提示。使用者不知道 Network 裡有多少筆失敗、Console 裡有多少筆 error——得逐 tab 點進去看。

* **設計**：
  - Tab label 旁加 `Badge`（Material 3 `Badge` widget）
  - Network tab：顯示 error count（`statusCode >= 400 || error != null`）
  - Console/Timeline tab：顯示 error/warning log count
  - Count 為 0 時隱藏 badge
  - 用 `ValueListenableBuilder` 監聽 buffer 變化，局部重建
* **Effort**：low ｜ **排查價值**：⭐⭐⭐

> **實作現況（`b4846ea` · 2026-08-07 · Issue #122）**：`_BadgeTabLabel` 建於
> `dashboard_modal.dart`，Console 與 Network 兩個 Tab 皆已接上，count 為 0 時隱藏。
> 與原設計的兩處差異：(1) 未用 `ValueListenableBuilder`，改在 `build()` 內即時計算；
> (2) Network count 直接複用 `NetworkEntry.isFailed` 而非原設計的
> `statusCode >= 400 || error != null`——`isFailed` 是「請求是否失敗」的單一真相來源，
> 與 error-summary banner、console 混合時間軸、diagnostic report 共用（該收斂源自 §P7）。
> Console count 刻意只算 log-level error/warning、不含混合時間軸裡的失敗網路請求，
> 避免與 Network badge 重複計數讓兩個數字互相矛盾。

### §P7. Error 高亮強化（Error Visual Enhancement）— ✅ 已完成（PR #101）

> **痛點**：目前 error log 只靠 `StatusColorIndicator` 的小色點區分（實際上 ConsoleTab 用 `TextStyle(color: entry.level.color)` 染文字色），在 500 條 timeline 裡不夠醒目。

* **設計**：
  - error/warning level 的 `_LogEntryRow` 加微妙的背景色（`ListTile` 外包 `Container` + `color: ThemeColor.colorF44336.withValues(alpha: 0.08)`）
  - 網路失敗的 `_NetworkEntryRow` 同理
  - 效果：error 條目帶淡紅底色，一眼從滾動列表中跳出
* **Effort**：trivial ｜ **排查價值**：⭐⭐⭐
* **✅ 實作現況（PR #101 · merge `3ecdf51`）**：與原構想有三處差異，前兩處是**刻意收窄/簡化**，第三處是動工後才浮現的既有缺陷：
  1. **只染 error，warning 不染**——原構想寫「error/warning 都加背景色」，實作決定只染 error。理由：warning 密集的 app 會整片泛黃，反而稀釋掉「跳出來」的效果，違背這項功能的唯一目的。warning 維持橘字不變，已有測試鎖住（`console_tab_test.dart` 斷言 warning 的 `tileColor` 為 null 且文字色為 `LogLevel.warning.color`）。
  2. **用 `ListTile.tileColor`，不外包 `Container`**——原構想的 `Container` 是多餘的：`ListTile` 自帶 `tileColor` 參數，而外包 `Container` 會多一層 widget，且背景色會蓋在 Material 之上、破壞 InkWell 水波紋。alpha 0.08 為半透明，疊在 ambient surface 上合成，深色底自然透上來。
  3. **順帶收斂「網路請求是否失敗」的三份重複判定**（本項才是這次 diff 的主體）：動工時發現該判定在 `network_tab.dart:52`、`diagnostic_report.dart:208`、`network_utils.dart:186` 各手寫一份，且**三份已經漂移**——各漏一種失敗類型（前兩者分別漏 `errorType` / `error`，第三者漏 `errorType`）。新增 `NetworkEntry.isFailed`（`>=400` ∪ `error` ∪ `errorType`）作為單一判定來源，四個消費端統一走它。
  - **一併修掉的既有 bug**：只帶 `errorType` 的傳輸失敗原本**不會產生 Error Summary 群組卡片**，在網路 tab 的錯誤摘要裡靜默消失（`aggregateNetworkErrors` 的判定漏了 `errorType`）。收斂後修正，已加測試鎖住。目前內建的 dio interceptor 一律同時寫 `error` 與 `errorType`，故走不到該分歧；但 `NetworkEntry` 建構式與 `logNetwork()` 都是公開 API，接非 dio 網路層的使用者即可觸發。
  - **未採納的 review 意見兩則**（皆經實測查證後 pushback）：① 建議把 `isFailed` 的 `errorType` 收窄以排除 `cancel`——在本 codebase 是 no-op，因 interceptor 一律同時寫 `error`，`error != null` 那項會先短路；真要處理應在 interceptor 決定記不記，而非在最下游的 getter 加 enum 白名單。② 建議 tint 改走 theme 衍生以支援 dark mode——本 package 全 `lib/` 對 `Brightness`/`ThemeMode` 的引用為 **0**，整套 design system 就是固定 hex token，且半透明 tint 本就會適應底色。

### §P8. 網路請求耗時慢查詢標記（Slow Request Indicator）— ✅ 已完成（PR #111 · Issue #110）

> **痛點**：API 回了 200 但花了 8 秒——不是 error 但確實是問題。目前無法快速識別慢請求。

* **設計**：
  - `NetworkEntry` 的 `duration` 超過可設定閾值（如 3000ms）時，列表項加 🐢 或黃色 `Chip("Slow")`
  - `_ErrorSummaryBanner` 可選顯示慢請求計數
  - 不修改 entry model，純 presentation 層判斷
* **Effort**：trivial ｜ **排查價值**：⭐⭐
* **✅ 實作現況（PR #111）**：與原構想有兩處差異——
  1. **閾值可設定且預設 2s**（非構想舉例的 3000ms）：`kSlowRequestThreshold` 常數被替換為
     `FlutterInspector` 建構式的 `slowRequestThreshold` 參數（commit `5d9cd21`），並在
     `e167954` 補上負值拒絕。NetworkTab 直接把當前閾值顯示在 UI（`>2.0s`），讓使用者
     知道判定條件而不需翻文件。
  2. **標記同時上了兩個 tab**：不只 `network_tab.dart:279-292`，`console_tab.dart:280-293`
     的混合時間軸也套用同一判定（`entry.duration! >= slowRequestThreshold` → `🐢 SLOW`）——
     時間軸是排查主場，只標在 NetworkTab 會讓慢請求在混合流裡消失。
  - **未做**：`_ErrorSummaryBanner` 的慢請求計數。慢請求不是 error，塞進錯誤摘要會混淆兩種語意；
    列表標記已足夠達成「快速識別」的目的。

### §P9. Diagnostic Report JSON 結構化輸出 — 🆕

> **痛點**：目前 `buildDiagnosticReport` 只輸出 Markdown。某些團隊需要結構化 JSON 以便自動化分析（如 CI 報告、Slack bot 解析）。

* **設計**：
  - 新增 `buildDiagnosticReportJson()` 回傳 `Map<String, dynamic>`
  - `ExportReportSheet` 加格式切換（Markdown / JSON）
  - JSON 結構直接映射既有 section，不引入新 schema
* **Effort**：medium ｜ **排查價值**：⭐⭐

---

### 完整優先順序總表

| 優先序 | 項目 | 來源 | Effort | 排查價值 |
|:---:|------|------|:---:|:---:|
| ~~1~~ | ConsoleTab 搜尋 + LogLevel 過濾 — ✅ 已完成（PR #128，與 §P5 合併） | §D1（#5 缺口） | low–med | ⭐⭐⭐⭐⭐ |
| **2** | 錯誤爆發偵測 + 視覺警報 | §P1 新提案 | low | ⭐⭐⭐⭐⭐ |
| ~~3~~ | ~~錯誤上下文快照~~ — ❌ 已否決（2026-07-24，理由見 §P2） | §P2 新提案 | — | — |
| ~~4~~ | 未捕捉例外去重修復 — ✅ 已完成（PR #96） | §D2（#1 缺陷） | low | ⭐⭐⭐⭐ |
| ~~5~~ | ~~Detail View ±5s 同時段側欄~~ — ❌ 已否決（2026-07-24，理由見 §D3） | §D3（#2 做法 A） | med | — |
| ~~6~~ | Timeline 書籤 / 標記 — ✅ 已完成（PR #115） | §P3 新提案 | low | ⭐⭐⭐⭐ |
| **7** | Dashboard 錯誤計數 Badge ✅ 已完成（`b4846ea`） | §P6 新提案 | low | ⭐⭐⭐ |
| ~~8~~ | Error 高亮強化 — ✅ 已完成（PR #101） | §P7 新提案 | trivial | ⭐⭐⭐ |
| **9** | 快速複製 Diagnostic Snippet | §P4 新提案 | trivial–low | ⭐⭐⭐ |
| ~~10~~ | Jump to Latest Error FAB — ✅ 已完成（PR #128，併入 §D1；入口改為點擊過濾結果，FAB 為被取代的原始構想） | §P5 新提案 | low | ⭐⭐⭐ |
| **11** | DatabaseTab 搜尋 / 過濾 | §D4 缺口 | low | ⭐⭐⭐ |
| ~~12~~ | 慢請求標記 — ✅ 已完成（PR #111 / Issue #110） | §P8 新提案 | trivial | ⭐⭐ |
| **13** | Diagnostic Report JSON 輸出 | §P9 新提案 | med | ⭐⭐ |

> **注意：本表為 2026-07-23 的舊排序，已被「下一步實作路徑」的 Tier 分層取代**（重排理由見該節）。
> 此處保留作為決策紀錄，實際動工順序請以 Tier 表為準。狀態欄則兩處同步維護。

---

## 🔭 第五部分：第二輪腦力激盪——開源除錯生態手法 + 效能訊號 + 既有缺陷（2026-07-24 新增）

> 本節出發點：對照 Sentry/Bugsnag（breadcrumbs）、Flipper（多層 plugin 檢視）、Reactotron（tag 過濾 + custom command）等開源除錯生態的具體手法，看哪些能以「零/低新增基建」的方式移植。**先做了二次 codebase 查核**（見下方「查核結論」），結果是：本專案已經把 breadcrumb（`mergedTimeline`）和 alert throttle（`AlertThrottler`）這兩塊地基做完了，開源生態的手法大多是這兩塊的變形；真正缺的是「生命週期 / 連線狀態」這類**本專案從未實作過的 hook 類別**——這些提案的 effort 因此如實標高，不偽裝成「零成本重用」。

### 查核結論（用於判斷下列各項的真實 effort）

| 查核項 | 結論 | 影響 |
|---|---|---|
| `InspectorRegistry` buffer | 固定 log/network/navigator/database 四個，皆 `implements TimestampedEntry`（僅 `timestamp` 欄位） | 新事件來源可直接掛上既有 `mergedTimeline()`，不需新資料管線 |
| `RingBuffer` | 純 FIFO，`capacity` 固定上限，**無** high-water-mark 統計 | 若新提案需要「近期計數」，得自己在 buffer 之外維護滑動視窗，非現成 |
| Rebuild/build 耗時 hook | 全 repo `debugPrintRebuildDirtyWidgets`/`Timeline.startSync`/`SchedulerBinding` **零命中** | rebuild 類提案完全是新建，非移植既有 hook |
| `NetworkNotifier`/`AlertThrottler` | 目前綁死「單一持續更新通知」；`AlertThrottler` 本身通用但只被 `NetworkNotifier` 私有持有，非共用單例 | §P1 錯誤告警要用系統通知，得先做 §P13 的重構才能複用節流邏輯 |
| `LogEntry.data`/`NetworkEntry` 欄位 | `data: Map<String,dynamic>?` 已存在；`NetworkEntry` **無**連線狀態欄位 | 上下文快照類提案（如 §P2）可直接塞 `data`，零 schema 變更；連線狀態則要新欄位 |
| redaction pipeline | 只作用於 `NetworkTab`/`NetworkDetailView`/匯出格式化；`LogEntry.data`、`DatabaseEntry`、`NavigatorEntry`、`dio_interceptor` 存入 buffer 的原始資料**完全未遮罩**；`log_detail_view.dart` 拿到 `redactSensitiveData` flag 但內部從未使用 | 見 §D5——查核屬實，但**已決定不排程修復**（debug 工具以資訊完整為先），既有實作保留不動 |
| App 生命週期 hook | `AppLifecycleState`/`WidgetsBindingObserver` **零命中** | §P14 是全新地基，非移植 |
| pubspec 相依 | 無 `connectivity_plus`/`battery_plus`/`device_info_plus` | §P12 需要新相依，非「已在相依」的低成本項 |

### ~~§D5. Redaction 涵蓋缺口（既有缺陷，非新功能）~~ — ❌ 不排程（2026-07-24）

> **決策（2026-07-24）**：查核所述的涵蓋缺口屬實，但**不排入開發**。既有 redaction 實作**保留原樣、不動**，本節保留作為查核紀錄。
>
> **理由**：`flutter_inspector_kit` 是 debug 工具，使用者是在自己的 debug build 裡看自己的資料——**除錯時資訊越詳細越好**。遮罩 header、遮罩 `LogEntry.data`，只會變成排查的絆腳石：想複製一段 curl 重現問題，結果 `Authorization` 是 `***`，還得回頭翻程式碼撈真值。這是為了「理論上的安全」增加真實的排查摩擦，與本文件「解決真實問題，不解決臆想威脅」的一貫判準相違。
>
> 因此「補齊涵蓋範圍」的方向被否決；既有的 `redactSensitiveData` 與 `redactHeaders()` 維持現狀（不擴大、也不移除），下方現況盤點與修復方向僅供未來若有需求時參考。

**現況（保留作查核紀錄）**：`redactSensitiveData`（`FlutterInspector` 建構參數，預設 `true`）目前的涵蓋範圍：

- ✅ `NetworkTab`、`NetworkDetailView`、`network_formatters.dart`（curl / 純文字匯出）：header 經 `redactHeaders()` 遮罩 `authorization`/`cookie`/`set-cookie`/`x-api-key`
- ❌ `LogEntry.data`：任何人透過 `inspector.log(data: {...})` 塞進去的 Map，原封不動存進 `RingBuffer`，UI 直接用 `KeyValueTable` 渲染，**無遮罩**
- ❌ `DatabaseEntry`、`NavigatorEntry`：完全未接 redaction
- ❌ `dio_interceptor.dart`：存進 buffer 的 `NetworkEntry` 本體是**明碼**，`redactHeaders()` 只在**顯示/匯出當下**現算，buffer 裡的原始資料從頭到尾未過濾
- ❌ `log_detail_view.dart`：`ConsoleTab` 有把 `redactSensitiveData` flag 一路傳進 `LogDetailView`，但該 view **內部從未讀取這個參數**——傳了等於沒傳，是一個「看起來接了線、實際上斷路」的死接線

**風險**：body 從未被 redaction 覆蓋（只有 header），且 `LogEntry.data` 若被用來記錄使用者輸入（表單欄位、token、PII）會完整落在 Console 明碼顯示，`redactSensitiveData: true` 給人的保護假象比實際涵蓋範圍大。

**~~建議~~（已否決，保留作紀錄）**：原提議獨立開 bug issue，修復方向兩選一：
1. ~~補齊 `LogDetailView` 對 `redactSensitiveData` 的實際使用（最小修復，對齊「傳了就要用」）~~
2. ~~若要根治，redaction 應移到 **entry 存入 buffer 前**而非顯示時現算——即在 `LogInspector.add()` / `DatabaseInspector.add()` 等入口統一過濾，讓「buffer 裡的資料本來就是安全的」，而非依賴每個 view 各自記得呼叫~~

* ~~**Effort**：low（方案 1）/ medium（方案 2，牽動四個 inspector 的 add 入口）｜**風險等級**：🔴~~ → **不排程**，理由見本節開頭決策說明。

> **殘留待議（不阻塞、非本次範圍）**：`log_detail_view.dart` 收下 `redactSensitiveData` flag 卻從未讀取，屬「接了線但斷路」的死參數。與遮不遮罩的取捨無關，純粹是程式碼整潔問題——未來若順手可移除該參數傳遞，但**不因此排程任何工作**。

### §P10. Rebuild 異常偵測（Excessive Rebuild Guard）— ❌ 已取消（2026-08-14）

> **痛點**：`setState` 迴圈、`ChangeNotifier` 誤觸發、`AnimatedBuilder` 忘記傳 `child` 這類 bug，症狀是「某個 widget 瘋狂重建」，但現有排查鏈完全看不到——這類 bug 現在只能靠 DevTools 的 Performance View 肉眼抓，跟本文件「排查」主軸脫節（DevTools 那是效能剖析，不是錯誤排查）。

* **先拆穿一件事**：這不是 anti-feature #1（完整 Profiler）的翻版。Profiler 回答「哪裡慢」，這裡回答「這個 widget 是不是在不正常地狂建」——是一個**離散的 bug 信號**（超過閾值 → 一筆 log），不是連續的效能剖析面板。
* **好品味設計（關鍵洞察）**：
  > Flutter 沒有「任意 widget rebuild 完成」的全域回呼（`debugPrintRebuildDirtyWidgets` 是 debug-only 全域旗標且直接 print，不分 widget、不進 buffer）。所以這**做不到自動偵測**，只能是 opt-in per-widget 的輕量 mixin——這和本文件其他功能「app 層級一個 flag 全開」的接線模式不同，必須誠實標注。
  - 提供 `RebuildGuardMixin`（`State` mixin），內部維護一個 `List<DateTime>` 滑動視窗（`RingBuffer` 沒有「近 1 秒內筆數」語意，這裡是新邏輯，非重用）
  - `build()` 開頭呼叫 `guardRebuild()`：清掉視窗外的舊時間戳、加入當前時間戳，超過閾值（預設 20 次/秒，可設定）→ `inspector.log('Excessive rebuild: $runtimeType (${count}x/1s)', level: LogLevel.warning)`
  - 同一個 widget 連續超標只記一次，冷卻期（如 5 秒）後才能再觸發——避免真的在狂建的 widget 洗版 Console
* **重用**：`inspector.log()`、`LogLevel.warning`。**不重用**：`RingBuffer`（語意不合，滑動視窗需要「移除視窗外的舊項」而非「滿了才淘汰最舊」）。
* **品味守則**：mixin 是**症狀偵測器**，不是效能分析——不記錄耗時、不記錄呼叫堆疊、不分帳每幀花費。開發者主動選擇要監控哪些 widget（通常是懷疑有問題的那幾個），不是全 app 插樁。
* **Effort**：low（邏輯本身簡單）但**接線成本非零**——需要開發者手動幫可疑 widget 加 mixin，不是一個 `flag: true` 就全解決；這點要在 README 講清楚，避免被誤期待成自動偵測。
* **排查價值**：⭐⭐⭐（見效但受眾窄：只有「懷疑某 widget 有 rebuild bug」時才會主動用）

### §P11. 多告警類型重構 NetworkNotifier（§P1 的後端支撐）— ✅ 已完成（隨 §P24 落地 · Issue #156 · 2026-09-06）

> **✅ 落地更新（2026-09-06）**：本重構已隨 **§P24 Crash 系統通知**一併完成。
> 下方「應與 §P1 綁定排程」的結論**已過時**——§P1 並非本重構的唯一消費者，
> §P24 同樣依賴它，且先一步動工。實際落地範圍與本節設計一致：
> `_notificationId` / `_channelId` / `_channelName` 已參數化為 `final` 實例欄位，
> 新增 `NetworkNotifier.crash()` 具名建構式，`showOrUpdate()` 公開簽章不變、
> 既有測試零修改（34 tests 未改動即全綠）。
> **§P1 若日後動工，本前提已就緒，無需重做。**

> **痛點**：§P1「錯誤爆發偵測」設想用既有系統通知基建做背景告警，但查核發現 `NetworkNotifier` 目前寫死「單一持續更新通知」（固定 notification id + channel）。**⚠️ 實查校正（2026-08-23）**：原句後半「`AlertThrottler` 是它的私有欄位，不是共用元件」**已過時**——`network_notifier_io.dart:19,22` 已支援建構式注入（`AlertThrottler? throttler`，預設 `?? AlertThrottler()`），`_web` 分支簽章一致，持有關係無需再動。**本項真正剩餘的缺口只有 `:31` `_notificationId` 與 `:33` `_channelId` 兩個私有常數的參數化**，effort 應由 low 下修為 trivial~low。§P1 若直接動工會被迫在 `NetworkNotifier` 內部長出 if/else 分支去區分「網路摘要」與「錯誤爆發」兩種通知語意——這正是「特殊情況」的壞味道。

* **好品味設計**：
  > 把「一則通知」抽象成 `id` + `channel` 兩個參數，`NetworkNotifier` 變成這個通用能力的其中一個**呼叫者**，而非通知邏輯本身的擁有者。
  - ~~`AlertThrottler` 改由呼叫端各自持有一份實例，而非塞在 `NetworkNotifier` 內部~~ — ✅ **已具備**（2026-08-23 實查）：建構式已可注入，§P1 的錯誤告警直接傳入自己那份即可，無需改動
  - 新增輕量的 `InspectorNotificationChannel`（或直接是幾個具名常數：`networkChannelId`/`errorAlertChannelId`），讓 `flutter_local_notifications` 的初始化一次註冊多個 channel
  - `NetworkNotifier.showOrUpdate()` 簽章不變（既有呼叫者零修改），只是內部改用參數化的 channel id
* **重用**：`AlertThrottler`（邏輯零修改，只改持有關係）、`flutter_local_notifications` 初始化流程、`_io`/`_web` 平台分支模式
* **品味守則**：這是**重構**不是新功能——目的是讓 §P1 能落地時不必重新發明節流器，也不必在通知模組裡塞 if/else 分special-case。若 §P1 最終不做，這項重構本身沒有獨立存在的理由，**應與 §P1 綁定排程**，不要單獨動工。
* **Effort**：~~low~~ → **trivial~low**（2026-08-23 實查下修，理由見痛點段的校正註記）｜**排查價值**：⭐⭐⭐（本身無直接排查價值，純粹是 §P1 的解鎖前提）

### §P12. 離線/斷網事件標記（Connectivity Marker）— 🆕 需新相依，謹慎評估

> **痛點**：網路請求失敗時，`NetworkDetailView` 已能分辨「傳輸層失敗 vs server 錯誤回應」（§4/#4 已完成），但**看不出「當下裝置本身是否離線」**——開發者仍得自己推敲「是我家 wifi 斷線，還是 server 真的掛了」。

* **先問三個鐵律問題**：
  1. **真實問題？** 部分真實——`DioExceptionType.connectionError` 已經間接透露「連不上」，多數情況這已經夠用；「裝置離線」是連線失敗一堆根因裡的**一種**，不是排查鏈上獨缺的一塊拼圖。
  2. **更簡單的方法？** 有：§4 的 `errorType` 分類已經覆蓋大部分情境，若要更精確，讓開發者自己在 error log 的 `data` 塞一筆 connectivity 資訊（用既有 `LogEntry.data`）比引入新相依更便宜。
  3. **會破壞什麼？** 新增 `connectivity_plus` 相依會擴大套件的 transitive dependency surface，且與本文件「零新相依」的一貫品味守則衝突。
* **判斷**：**效益不足以蓋過新相依的成本**，傾向不做。若真要做，正確的落地方式是**文件化的整合模式**（README 教學：使用者自行監聽 `connectivity_plus` 的 stream，在斷網時 `inspector.log('Device offline', level: warning)`），而非套件內建功能——這與 anti-feature #7「不直接相依 webview 套件」的判斷邏輯一致：讓消費端自己選要不要引入。
* **Effort**：若做 low（單純轉發事件）；若走「文件化模式」則 trivial（只寫 README）｜**排查價值**：⭐⭐（多數場景已被 §4 覆蓋）
* **建議**：不列入 Phase Plan，改為 README 補充一段「離線排查食譜」，成本最低且不违反零新相依守則。

### §P13. App 前景/背景切換標記（Lifecycle Marker）— ✅ 已完成（PR #100 · 2026-07-24 合入 main，merge `c616482`）

> **痛點**：崩潰或異常網路行為，若發生在 app 被切到背景的瞬間（iOS/Android 對背景 app 的資源限制、被系統 kill 前的緊急回收），這個「當下處於什麼生命週期狀態」的 context 現在完全沒被記錄——Sentry 等工具的 breadcrumb 預設就包含這個維度。

* **好品味設計**：
  > 生命週期切換本身**就是一條 log**，比照 §1 未捕捉例外的做法——不新增資料模型，轉成一筆 `LogEntry`。
  - `FlutterInspector` 新增可選建構參數 `captureLifecycleEvents`（default **off**，比照 `captureUncaughtErrors` 的保守慣例）
  - 內部用 `WidgetsBindingObserver.didChangeAppLifecycleState` 掛勾，`resumed`/`paused`/`inactive`/`detached` 各轉一筆 `LogLevel.info` 的 `LogEntry`（訊息如 `App lifecycle: resumed`）
  - 崩潰發生時，Timeline 上崩潰事件前最近一筆 lifecycle log 就是「當下 app 是否在前景」的答案——**免費疊加**在既有 `mergedTimeline()` 上，不需要額外的側欄或 UI
* **重用**：`inspector.log()`、`mergedTimeline()`、`LogLevel.info`
* **品味守則**：跟 §1 一樣「chain 不覆蓋」——`WidgetsBindingObserver` 用 `add`/`remove` 註冊，不霸占宿主 app 唯一的 observer 名額（Flutter 允許多個 observer 並存，天生不衝突，不像 `FlutterError.onError` 需要手動 chain）。
* **Effort**：low ｜**排查價值**：⭐⭐⭐⭐（崩潰報告新增一個免費維度，成本低價值不錯）
* **✅ 實作現況（PR #100 · v1.7.1 之後）**：新增 `LifecycleHandler`（`lib/src/core/lifecycle_handler.dart`，`with WidgetsBindingObserver`）+ `captureLifecycleEvents` 建構參數（default off）。與原構想的兩處**刻意深化**：
  1. **`detach()` 一併移除 observer，不沿用 error hooks 的「不 teardown」**——這是實質差異：`FlutterError.onError` 是單一 slot（還原會幹掉宿主後裝的 handler），而 `WidgetsBindingObserver` 是一個 list，`removeObserver(this)` 只移除自己。能乾淨移除就該乾淨移除。
  2. **message 尾巴附加當前 top-most page**（使用者實測回饋後追加）：`App lifecycle: resumed · HomePage (/home)`。home/back 頻繁切換時純狀態名會被洗頻，附上頁面才不用跳 Navigator tab 對時間戳。來源走既有 `NavigatorStackResolver.resolve(navigatorEntries).first`（純函式重播、零新資料管線），**推不出來時省略尾巴而非硬掰**——避免把 best-effort 推導值當事實（這正是 §P2 被否決的核心教訓，用「省略而非猜測」避開同一個坑）。只取型態 + path，不帶 `arguments`（PII/大量資料風險）。`data` 仍維持 `null`。
  - **耦合邊界**：`LifecycleHandler` 只收 `String? Function()? topPageLabel` callback，不持有 registry/resolver；resolve 邏輯留在 `FlutterInspector._currentTopPageLabel()`。handler 仍是「症狀記錄器」。
  - 完整設計判斷（`hidden` 納入、observer teardown、`data` map、top-page 追加）見 [`docs/features/2026-07-24-app-lifecycle-marker.md`](../features/2026-07-24-app-lifecycle-marker.md) 與 [`docs/plans/2026-07-24-app-lifecycle-marker.md`](../plans/2026-07-24-app-lifecycle-marker.md)。

### §P14. Breadcrumb 式自訂標記事件（`inspector.mark()`）— ⚠️ 降級（2026-07-24）

> **降級判斷（2026-07-24）**：`mark()` 與 `log()` **功能上沒有差別**——同一個 `LogEntry`、同一個 buffer、同一條 timeline、連 level 都是 info，差別只在 `data` 裡多一個固定 flag。它**沒有往時間軸加任何新資訊**：§P13 加的是「當時在前景還背景」這種原本拿不到的維度，`mark()` 加的只是「這筆 log 長得不一樣」——**是渲染差異，不是資訊差異**。
>
> 因此它不屬於「服務因果推斷」的那一批，應與 §P7 Error 高亮同列（標記已有資訊）。而且比 §P7 更弱：§P7 標的 error 是工具自己判斷得出來的，`mark()` 標的「這很重要」得靠人記得呼叫。
>
> **更關鍵**：為此新增一個公開 API 不划算。公開 API 有維護、文件、breaking change 成本，而想要的效果（timeline 上顯眼）有兩個更便宜的達成方式：① 約定 `log('📍 CHECKOUT_START')`，**零程式碼、現在就能用**；② §P7 高亮機制做完後，讓它一併認 `data` 裡的任意 flag。這與 anti-feature #6「為不存在的區別打補丁」是同一個毛病的輕量版。
>
> **結論**：移出優先序列，**與 §P7 綁定或直接被 emoji 約定取代**。若 §P7 完成後覺得約定夠用，本項永不需實作。下方原設計保留作紀錄。
>
> **§P7 完成後的現況（2026-07-25）**：高亮機制已存在於 `console_tab.dart`（`_kErrorRowTint` + 各 Row 的 `tileColor` 判斷），本項若要做，只需讓該判斷多認一種 `data` flag，**不需要新的公開 API**。在有人實際反映 `log('📍 …')` 的 emoji 約定不夠用之前，維持不排程。

> **痛點**：開發者常常想在「關鍵業務流程節點」主動留一個標記（如「進入結帳流程」「使用者按下送出」），現在只能用 `inspector.log()` 硬湊，跟一般 info log 混在一起，排查時不容易在 Timeline 裡一眼認出「這是我特意標的節點」還是「隨手印的訊息」。

* **先問**：這是不是只要教「約定成俗」就好，不用加新 API？—— **多數情況是**，`inspector.log('CHECKOUT_START')` 已經能用。但缺一個**視覺上可辨識**的標記慣例，容易被 100 筆 info log 淹沒。
* **好品味設計（最小化）**：
  > 不新增 entry model、不新增 buffer。`mark()` 就是 `log()` 的一層薄語法糖，只是**固定一個可辨識的 level 或 data 標記**，讓 Console/Timeline 的 UI 能選擇性高亮。
  - `inspector.mark(String label)` → 內部呼叫 `log(label, level: LogLevel.info, data: {'_marker': true})`
  - ConsoleTab 對 `data['_marker'] == true` 的條目加一個視覺區分（如 📍 前綴或不同底色，做法比照 §P7 Error 高亮強化的機制）
  - 完全不影響 `buildDiagnosticReport`——marker log 一樣進 `## Timeline`，`_marker` data 自然可見
* **重用**：`inspector.log()`、`LogEntry.data`（零新欄位）、§P7 **已實作**的高亮機制（PR #101，同一套 presentation 層判斷邏輯，這裡多一種 badge）
* **品味守則**：`mark()` 就是 `log()` 的殼，**不要**為了「聽起來像獨立功能」而新增 `MarkEntry` 模型或新 buffer——那是為不存在的區別打補丁（同 anti-feature #6 的判斷邏輯）。
* **Effort**：trivial ｜**排查價值**：⭐⭐⭐（小成本、體驗改善，錦上添花類）

### §P15. 鍵值儲存檢視器（Key-Value / SharedPreferences Browser）— ✅ 已完成（PR #137 · 2026-08-22）

> **📌 2026-08-22 結案（issue #136 / PR #137 已合併）**：落地形式與本提案有一處關鍵差異——
> **實作為獨立的 Storage tab，而非併入 Database Tab**。改動理由：區分「資料存在哪個引擎」
> 本身就是排查資訊，RD 需要這個訊號，混在同一個 tab 會模糊它。
>
> 這個歸屬改變同時**消滅了提案沒預見的一個設計難題**：若併入 Database Tab，
> `DropdownButton<DatabaseBrowserSource>` 的泛型型別容不下第二種介面，而既有測試
> （`database_tab_test.dart:114/121/151`）把該泛型寫死在斷言裡，任何上層抽象都會讓它們全紅。
> 獨立 tab 後 `database_tab.dart` 一行未改，難題不是被解決而是被取消。
>
> 其餘設計均如提案落地：`KeyValueBrowserSource` host-injection 介面（第四次複用該 pattern）、
> 零新相依（`pubspec.yaml` diff 為空）、寫入須二次確認並自動記 `info` log。
> 稽核 log 的值在 `redactSensitiveData` 為 true（預設）時遮蔽——log 會經
> `buildLogPlainText` 進入剪貼簿與分享，而 KV source 可能是 secure storage。

> **痛點**：Database Tab 已提供 SQLite / ObjectBox 的表格瀏覽，但實務上 QA 遇到「卡在某個畫面」「登入異常」「功能開關失靈」時，90% 的根因是 `SharedPreferences` 或 `FlutterSecureStorage` 裡的 Token、Feature Flag、快取 Key 爛掉了——而這些鍵值儲存**完全沒有任何 in-app 檢視手段**。目前 QA 唯一的選項是請開發者拉 adb shell / 解壓 sandbox，然後手動翻 XML 或 SQLite，完全不具即時排查能力。

* **先問三個鐵律問題**：
  1. **真實問題？** 100% 真實。「Token 過期但本地快取沒清掉導致 401 循環」「Feature flag 卡在錯誤狀態導致 UI 空白」是日常回報的常態。Database Tab 做了 SQLite 但漏了 SharedPreferences，是一個真實的盲區——兩者都是「本地持久化狀態」，只是儲存引擎不同。
  2. **更簡單的方法？** 沒有。`SharedPreferences` 不像 SQLite 可以用現有的 `DatabaseBrowserSource` 接入——它不是表格式的結構化資料，是扁平的 key-value 對，需要不同的介面抽象。但**設計模式完全可以複用**：`DatabaseBrowserSource` 的 host-injection pattern（套件提供介面、消費端注入實作）已驗證三次（`DiagnosticInfoSource`、`DatabaseBrowserSource`、`WebViewBridgeAdapter`），第四次不需要新發明。
  3. **會破壞什麼？** 不會。新增可選建構參數（`keyValueSources`）+ 新介面 + 新 UI section。**既有 Database Tab 的行為零改動**。

* **好品味設計（核心洞察）**：
  > SharedPreferences 就是一個「只有一張表、column 是 key/value/type」的 database。不需要另起爐灶——它的 UI 歸到 Database Tab 或獨立為 Storage Tab 皆可（傾向前者，避免 tab 膨脹），差別只在資料來源不同。
  - **新增介面 `KeyValueBrowserSource`**（鏡射 `DatabaseBrowserSource` 的 host-injection 慣例）：
    ```dart
    abstract class KeyValueBrowserSource {
      String get name; // e.g. 'SharedPreferences', 'SecureStorage'
      Future<List<KeyValueEntry>> listAll();
      Future<void> setValue(String key, Object value);
      Future<void> remove(String key);
      Future<void> clear();
    }
    ```
  - `KeyValueEntry`：`@immutable` 資料類（`key: String`, `value: Object?`, `type: String`——`String`/`int`/`double`/`bool`/`List<String>`）
  - **消費端實作（README 範例，非套件內建）**：
    ```dart
    class SharedPrefsBrowserSource implements KeyValueBrowserSource {
      SharedPrefsBrowserSource(this._prefs);
      final SharedPreferences _prefs;
      @override String get name => 'SharedPreferences';
      @override Future<List<KeyValueEntry>> listAll() async { /* _prefs.getKeys() → map */ }
      @override Future<void> setValue(String key, Object value) async { /* _prefs.setXxx */ }
      @override Future<void> remove(String key) async { _prefs.remove(key); }
      @override Future<void> clear() async { _prefs.clear(); }
    }
    ```
  - **註冊方式**對齊 `DatabaseBrowserSource`：
    ```dart
    final inspector = FlutterInspector(
      navigatorKey: navigatorKey,
      keyValueSources: [SharedPrefsBrowserSource(prefs)],
    );
    // 或動態
    inspector.registerKeyValueSource(SharedPrefsBrowserSource(prefs));
    ```
  - **UI**：Database Tab 的 source dropdown 擴充為同時列出 `databaseSources` 與 `keyValueSources`（以 group header 區分），選中 KV source 時切換為 key-value 列表視圖（搜尋 + 篩選 type + **inline 編輯 / 刪除 / 清空**）
  - **寫入操作**：KV 與 DB 的核心差異在於 KV **需要寫入能力**（修改 value、刪除 key、清空全部）。這是刻意的——QA 的真實需求是「把 Token 清掉重現全新狀態」「手動把 Feature Flag 改成 true 觸發隱藏功能」，唯讀的檢視器只解決一半問題。寫入操作須加二次確認（`AlertDialog`），且每次寫入自動生成一筆 `LogLevel.info` 的 Console log（`KV write: [source] key=xxx → value`），讓改動有跡可循。

* **重用**：`DatabaseBrowserSource` 的 host-injection 架構模式、`DatabaseTab` 的 source dropdown + `DropdownButton` UI、`_SearchBar` 元件、`KeyValueTable`（已能渲染 Map）、`inspector.log()` 記錄操作。
* **品味守則**：
  - **零新相依**：套件不引入 `shared_preferences` 或 `flutter_secure_storage`，消費端自行注入——與 `DatabaseBrowserSource`（不引入 `sqflite`）、`DiagnosticInfoSource`（不引入 `device_info_plus`）、`WebViewBridgeAdapter`（不引入 webview 套件）完全一致。
  - **不加第五個 Tab**：KV 檢視器歸入 Database Tab（或重新命名為 Storage Tab），不膨脹底部導航——tab 數量已經在臨界值，再加就得做 scrollable tab bar，偏離「簡潔」原則。
  - **寫入操作加 log 追蹤**——debug 工具自己改了本地狀態卻不留痕跡，那就是 observer effect 的反面教材。
* **Effort**：medium（新介面 + 新 UI section + README 範例）｜ **排查價值**：⭐⭐⭐⭐⭐（QA 排查「狀態卡住」問題的最高 ROI 工具，是目前排查鏈唯一缺少的「本地狀態可視化 + 可操作」能力）
* **影響範圍**：
  - 新增：`lib/src/models/key_value_browser_source.dart`（介面 + `KeyValueEntry`）
  - 修改：`lib/src/core/flutter_inspector.dart`（新建構參數 + `registerKeyValueSource`）
  - ~~修改：`lib/src/ui/dashboard/tabs/database_tab.dart`（source dropdown 擴充 + KV 列表視圖）~~
    → **實際為零改動**：改採獨立 Storage tab 後不需擴充既有 dropdown
  - ~~新增：`lib/src/ui/dashboard/tabs/database/key_value_view.dart`~~
    → 實際為 `lib/src/ui/dashboard/tabs/storage_tab.dart`（升為 tab 根 widget，與 `database_tab.dart` 平級）
  - 實際另需：`lib/src/ui/dashboard/dashboard_modal.dart`（條件性掛載 Storage tab，追加於尾端以維持 index 契約）
    與 `lib/src/ui/widgets/confirm_dialog.dart`（本專案首個 dialog，供三種寫入操作共用）
  - README：SharedPreferences / FlutterSecureStorage 兩套接線範例

---

### 第二輪優先順序建議

| 優先序 | 項目 | Effort | 排查價值 | 備註 |
|:---:|------|:---:|:---:|------|
| ~~1~~ | §P13 App 前景/背景切換標記 — ✅ **已完成（PR #100）** | low | ⭐⭐⭐⭐ | 免費疊加在既有 Timeline，性價比最高；額外附加 top-most page（型態 + path）解洗頻問題 |
| ~~2~~ | ~~§P10 Rebuild 異常偵測~~ | ~~low（但需使用者接線）~~ | ~~⭐⭐⭐~~ | ❌ 已取消——價值太窄，opt-in per-widget 接線成本與收益不成比例 |
| ~~**3**~~ | ~~§P11 NetworkNotifier 重構~~ | ~~low~~ | ⭐⭐⭐（解鎖 §P1） | ✅ **已完成**（隨 §P24 落地，Issue #156）——原「與 §P1 綁定」的結論已過時，§P24 才是先動工的消費者 |
| **4** | **§P15 鍵值儲存檢視器（KV Browser）** | medium | ⭐⭐⭐⭐⭐ | **2026-08-14 新增**。QA 排查「狀態卡住」問題的最高 ROI 工具；host-injection pattern 第四次複用，零新相依 |
| — | ~~§P14 Breadcrumb 標記 `inspector.mark()`~~ | trivial | — | **降級不單獨排程**：與 `log()` 無功能差異，是渲染差異非資訊差異；與 §P7 綁定或直接用 emoji 約定取代（見 §P14） |
| — | ~~§D5 Redaction 涵蓋缺口修復~~ | — | — | **不排程**：debug 工具應資訊越詳細越好，遮罩是排查絆腳石；既有實作保留不動（見 §D5） |
| — | §P12 離線/斷網事件標記 | — | ⭐⭐ | **不建議做**：改寫入 README 作為整合食譜，避免新相依 |

---

## 🌐 第六部分：開源除錯與日誌生態套件全面評估與整合策略（2026-08-28 新增）

> **評估背景**：
> 針對 Flutter 社群主流的除錯與日誌開源生態套件（涵蓋 ducafecat 推薦清單與 pub.dev 頂級庫共 20+ 套件）進行全面盤點與架構評估。
> 評估遵循 Linus Torvalds 的實用主義哲學與「好品味」準則，以四項嚴格維度衡量：
> 1. **架構相容性 (Architecture Compatibility)**：能否原生適配 `RingBuffer` O(1) 記憶體寫入、`TimestampedEntry` 統一契約、`mergedTimeline()` 跨層歸併時序軸與 Host-Injection 模式。
> 2. **輕量與效能零負擔 (Lightweight & Performance Zero-Cost)**：零/極少外部相依、零磁碟污染（無 blocking I/O / SQLite 寫入）、無 PII 隱私外洩風險、零 GC 抖動與 WASM 相容。
> 3. **UI/UX 視覺呈現品質 (Visual Presentation & Ergonomics)**：Material 3 風格、彩色日誌等級標籤、堆疊折疊、可折疊 JSON 樹狀檢視器、因果跳轉定位、暗黑/明亮主題相容。
> 4. **社群活力與穩定度 (Community Activity & Long-term Stability)**：pub.dev 評分、維護活躍度、Flutter 3.35+ / Dart 3 / WASM 支援度。

### 1. 套件生態原型分類與綜合評估

我們將所有評估的 20+ 套件按「核心架構原型 (Archetype)」歸納為六大類別：

#### 原型一：全功能應用內除錯套件 (All-in-One In-App Debug Suites)
* **包含套件**：`talker_flutter` (`talker`), `alice` / `chucker_flutter`, `cr_logger`, `flutter_ume`, `logarte`, `ispect`, `let_log`, `flutter_debug_overlay`, `fconsole`。
* **深度特性剖析**：
  - **`talker_flutter`**（Likes: 755+，Popularity: 98%）：目前社群最成熟的綜合日誌與監控套件。優點是擁有強大的日誌格式化、UI 介面、豐富的擴充外掛（`talker_bloc_logger`, `talker_dio_logger`, `talker_riverpod_logger` 等）與自訂 Observer。缺點是其 UI 與日誌體系強綁定，預設日誌歷程儲存模型較重，若全面引入會與本 kit 的 `RingBuffer` 和 `Timeline` 地基造成概念重複與架構重疊。
  - **`alice` / `chucker_flutter`**（Likes: 316 / 500+）：專注於 HTTP/Dio 網路請求攔截與視覺化檢視（含 cURL 匯出、通知快捷、回應格式化）。但兩者僅涵蓋網路層，缺乏跨層時序整合；部分分支（如舊版 Alice）維護停滯且缺少 WASM 支援。
  - **`cr_logger`**（Likes: 48）：提供搖一搖呼出、網路/日誌/堆疊整合，但 UI 偏客製化、非標準 Material 3，且程式碼擴充性有限。
  - **`flutter_ume`**（字節跳動，Likes: 121）：外掛式除錯平台（Kit 概念），但套件拆分過碎（10+ kits，如 `flutter_ume_kit_ui`, `flutter_ume_kit_device`, `flutter_ume_kit_console`）、重度依賴反射與 Widget Tree 遍歷，近年維護放緩，且與現代 Flutter 3.35+ / WASM 相容性欠佳。
  - **`logarte`**（Likes: 213）：輕量級 App 內懸浮日誌與網路監控，UI 簡潔但功能較陽春，缺乏資料庫與生命週期觀測。
  - **`ispect` / `let_log` / `fconsole` / `flutter_debug_overlay`**：多為 Talker 或 Alice 的二次封裝或簡單 Console Overlay，缺乏獨立架構優勢。

#### 原型二：純日誌框架與終端格式化工具 (Logging Frameworks & Formatters)
* **包含套件**：`logger` (`logger_flutter`), `logging` (Dart 官方), `loggy` (`flutter_loggy`), `fimber` (`flutter_fimber`), `lumberdash` (`colorize_lumberdash`, `file_lumberdash`, `print_lumberdash`), `simple_logger`, `surf_logger`, `roggle`, `quick_log`, `snug_logger`, `en_logger`, `cross_logger`, `verbose`。
* **深度特性剖析**：
  - **`logger`**（Likes: 2500+，社群標竿）：Simon Leier 開發的日誌格式化標準庫。其亮點在於極致優美的控制台邊框打印（`PrettyPrinter`）、豐富的 `LogFilter`/`LogOutput` 擴充機制與堆疊折疊能力。無 UI 負擔、零重量相依。
  - **`logging`**（Likes: 945，Dart 官方）：官方標準抽象庫。採層級命名空間架構（hierarchical loggers）與 Stream 廣播機制，是無數企業級專案的標準介面。
  - **`loggy` / `fimber` / `lumberdash`**：分別借鑒了 Android Timber 或 mixin 概念，提供樹狀種植（Tree planting）或日誌插件化能力，但本質上皆為純日誌管道，不具備 in-app UI。

#### 原型三：高性能與二進制日誌引擎 (High-Performance / Binary & Disk Loggers)
* **包含套件**：`flutter_mxlogger` (Tencent MMAP), `f_logs` / `flutter_logs` (SQLite/File DB), `fimber_io`。
* **深度特性剖析**：
  - **`flutter_mxlogger`**：騰訊開源、基於 MMAP 記憶體映射的高性能二進制日誌庫。適用於日誌量每秒萬條且保證 crash 不丟 log 的極端環境。但包含 C++ native 依賴，增加打包體積且無法在 Web (WASM) 運行。
  - **`f_logs` / `flutter_logs`**：將日誌寫入本地 SQLite 或檔案系統，支援壓縮成 Zip 匯出。然而引入了本機磁碟 I/O 阻塞、儲存權限與資料庫版本遷移風險，且易在未脫敏情況下落盤敏感 Token。

#### 原型四：錯誤攔截與堆疊處理專門庫 (Stack Trace & Error Handling Specialists)
* **包含套件**：`stack_trace` (Dart 官方), `catcher` / `catcher_2`, `error_stack`, `native_stack_traces`, `anyhow`。
* **深度特性剖析**：
  - **`stack_trace`**（Dart 官方）：提供 `Trace` 與 `Chain` 類別，能完美解析、demangle、並將非同步中斷（`<asynchronous suspension>`）還原為完整因果鏈，過濾 core package 噪聲。
  - **`catcher` / `catcher_2`**：全域未捕捉例外框架。其設計存在嚴重哲學缺陷：強制接管 `runApp`、在發生錯誤時彈出侵入式阻塞 Dialog 或自動發送 Email/HTTP，違反「不破壞用戶空間」與「本機除錯不連外」原則。

#### 原型五：雲端 APM / 遙測與遠端桌面橋接 (Cloud APM, Telemetry & Desktop Bridges)
* **包含套件**：`sentry_logging`, `instabug_flutter`, `flutter_bugfender`, `flutter_flipperkit`, `flutter_stetho`, `redux_remote_devtools`。
* **深度特性剖析**：
  - 此類套件目標為線上 APM 收集或外接桌面除錯器（如 Flipper / Chrome DevTools）。與本 kit「完全運行於裝置端、資料不出裝置、無外部伺服器依賴」的定位正交。

#### 原型六：DevTools 輔助與終端工具 (Profiler & Terminal Utilities)
* **包含套件**：`leak_tracker`, `vm_snapshot_analysis`, `lcov_parser`, `print_color`, `rich_console`, `sprintf`, `flutter_storyboard`, `snapp_cli`, `screen_state`。
* **深度特性剖析**：
  - **`leak_tracker`**（Dart 官方，Likes: 168+）：由 Flutter 官方 DevTools / Memory 團隊維護之記憶體洩漏分析引擎。專注於在測試執行期（CI/CD）與開發輔助中捕捉未釋放物件（`notDisposed`）、未被回收物件（`notGCed`）與延遲回收物件（`gcedLate`）。其架構深度仰賴 Flutter 框架 `MemoryAllocations` 派發之事件、Dart `Finalizer` 與 `WeakReference`、以及 `vm_service` 之 WebSocket 連線以獲取保留路徑（Retaining Path）。在 In-App 即時排查場景下，因其激進的記憶體分配（`forceGC`）、不可忽略的幀率中斷（Jank）、以及在 Web (WASM/JS) 上完全無法取得 Retaining Path，使其無法適配為 In-App 常駐除錯工具。
  - 其餘多數為開發時期的靜態分析、測試報告解析或終端著色工具，不屬於即時除錯 Inspector 領域。

---

### 2. 綜合評估矩陣 (Comprehensive Evaluation Matrix)

| 套件名稱 (Package) | 原型分類 | 維度 1：架構相容性 | 維度 2：輕量與效能 | 維度 3：UI/UX 呈現 | 維度 4：社群活力 | Linus 品味評級 | 最終裁決與處置 |
|---|---|:---:|:---:|:---:|:---:|:---:|---|
| **`talker_flutter`** | 全功能調試套件 | 🟡 部分（需 Adapter） | 🟡 中等（UI 相依多） | 🟢 優秀（豐富圖示） | 🟢 極高 (755+) | 🟡 湊合 | **不替換核心**；以 `TalkerObserver` 接線適配 |
| **`logger`** | 純日誌框架 | 🟢 極佳（純輸出流） | 🟢 極佳（零多餘相依） | 🟢 優秀（終端邊框） | 🟢 頂級 (2500+) | 🟢 好品味 | **最佳日誌夥伴**；提供 `InspectorLogOutput` 適配器 |
| **`logging`** (dart.dev) | 純日誌抽象 | 🟢 極佳（官方標準） | 🟢 頂級（官方零負擔） | ⚪ 無 UI | 🟢 頂級 (945+) | 🟢 好品味 | **標準支援**；提供 `onRecord.listen` 接線食譜 |
| **`alice` / `chucker`** | HTTP 檢查器 | 🟡 僅涵蓋 Network | 🟡 中等（自帶儲存/UI） | 🟢 良好（HTTP 詳情） | 🟡 中等 (316+) | 🟡 湊合 | **不整合**；本 kit 之 NetworkTab 完整涵蓋且更輕 |
| **`stack_trace`** | 堆疊處理 | 🟢 極佳（純演算法） | 🟢 頂級（官方工具） | 🟢 結構清晰 | 🟢 頂級 (331+) | 🟢 好品味 | **吸收技術**；正規化非同步堆疊與框架過濾 |
| **`flutter_mxlogger`** | MMAP 二進制日誌 | 🔴 差（C++ native/無 Web）| 🟢 高性能但體積大 | ⚪ 無 UI | 🔴 低 (8) | 🔴 垃圾 | **拒絕**；破壞 WASM，違背 Anti-Features |
| **`f_logs` / `flutter_logs`**| 本機 DB 日誌 | 🔴 差（綁定 SQLite/File）| 🔴 差（磁碟 I/O 阻塞） | ⚪ 無 UI | 🟡 中 (120/98) | 🔴 垃圾 | **拒絕**；違反「零磁碟落盤」鐵律 |
| **`catcher` / `catcher_2`** | 錯誤捕獲與上報 | 🔴 差（破壞 userspace）| 🔴 差（阻塞式彈窗/上報）| 🟡 傳統對話框 | 🟡 舊套件 (597/52) | 🔴 垃圾 | **拒絕**；本 kit `UncaughtErrorHandler` 更優雅 |
| **`flutter_ume`** | 外掛除錯平台 | 🔴 差（架構過重/拆分碎）| 🔴 差（反射/記憶體重） | 🟡 傳統 Window | 🔴 停滯 (121) | 🔴 垃圾 | **拒絕**；過度工程典型，維護已放緩 |
| **`logarte`** | 輕量日誌控制台 | 🟡 僅 Log/Network | 🟢 輕量 | 🟡 陽春 | 🟡 中 (213) | 🟡 湊合 | **不整合**；功能為本 kit 子集 |
| **`cr_logger`** | 應用內日誌套件 | 🟡 概念重疊 | 🟡 自帶多層 UI | 🟡 非標準 M3 | 🔴 低 (48) | 🟡 湊合 | **不整合**；代碼封閉，無借鑒價值 |
| **`loggy` / `fimber`** | 日誌框架 | 🟢 良好（純日誌流） | 🟢 輕量 | ⚪ 無 UI | 🟡 中 (127/78) | 🟡 湊合 | **提供 README 食譜**，不新增直接相依 |
| **`leak_tracker`** | 記憶體洩漏分析 | 🔴 差（Web/WASM 斷手、綁定 VM Service 與 assert） | 🔴 差（forceGC 激進配置引發 Jank、追蹤駐留與 StackTrace 捕獲開銷大） | ⚪ 無 UI（純引擎無 In-App 界面） | 🟢 官方 (168+) | 🔴 垃圾（針對 In-App 整合） / 🟡 湊合（僅限 CI 測試） | **堅決拒絕 Direct In-App 內建**；維持外部獨立（DevTools/CI），至多以離散 Event Adapter 食譜轉入 Timeline（見 §3 核心決策三） |
| **`leak_detector`** | 頁面洩漏偵測（Widget/Element/State） | 🔴 差（native plugin 無 Web，拖 `sqflite`）| 🔴 差（Full GC 掉幀） | 🟡 自帶洩漏鏈預覽 | 🔴 停滯 (65 · 3 年未更新) | 🔴 垃圾 | **拒絕**；破壞 WASM 且違反「零磁碟落盤」，嚴格劣於已否決的官方 `leak_tracker` |

---

### 3. Linus 模式核心決策與架構批判

#### 前置思考：三個鐵律問題檢驗
1. **問題真實性**：「社群有現成的 Talker 或 UME，我們為什麼不直接換掉底層或整套搬過來？」
   - *答*：這是典型的**「拿著錘子找釘子」**。現有 `flutter_inspector_kit` 已經在排查鏈上完成了 8 個全綠的關鍵閉環（未捕捉錯誤捕捉、Dio 結構化錯誤、4 源歸併時序軸、WebView 觀測、Storage 鍵值操作、Markdown 診斷報告）。社群套件大多是把一堆無關的工具塞進一個大黑盒，完全缺乏本專案以 `TimestampedEntry` 貫穿的因果鏈推斷能力。
2. **有沒有更簡單的做法**？
   - *答*：有！**「Adapter（轉譯器）模式」**。外部日誌框架（`logger`, `talker`, `logging`）產生的日誌，本質上只是一條文字與等級。透過薄薄的幾行適配器注入到 `inspector.log()`，就能零成本享受整個 Timeline、搜尋過濾與診斷報告，根本不需要把整個外部框架塞進 `pubspec.yaml`。
3. **會破壞什麼嗎**？
   - *答*：堅決不破壞用戶空間。外部相依零增加、API 零破壞。

#### 核心決策一：為什麼絕不使用重型黑盒「全家桶」替換核心？
* **拒絕 Talker 式的單體龐大化 (Monolithic Coupling)**：
  Talker 試圖包辦一切（從日誌、Bloc、Riverpod、Dio、路由到自訂 UI）。但代價是引入龐大的相依鏈，並強迫消費端採用其特定的日誌資料模型。`flutter_inspector_kit` 採用 **Micro-Kernel + Host-Injection**：核心只有 `RingBuffer` 與 `InspectorRegistry`，其餘 Database、Storage、Diagnostic 全部由宿主按需注入。
* **拒絕 UME 式的反射與碎裂化 (Over-engineered Plugin Matrix)**：
  UME 把一個簡單的除錯需求拆成十幾個獨立 package，維護成本極高，且大量依賴 Element Tree 反射遍歷，在 Flutter 3.35+ 與 WASM 上頻頻出錯。
* **拒絕 Catcher 式的侵入與吞錯 (Breaking Userspace Anti-pattern)**：
  Catcher 在捕獲未處理異常時，會強行攔截並彈出全螢幕阻斷 Dialog 或發送 Email。這不僅中斷了使用者操作，更違背了「除錯工具不該改變應用原有行為」的底線。本 kit 的 `UncaughtErrorHandler` 以非侵入式 Chain 串接現有 handler，保留原汁原味的崩潰現場。

#### 核心決策二：堅守 Anti-Features（拒絕本機落盤與強依賴注入）
* **嚴禁引入本機落盤（SQLite / Hive Crash History DB）**：
  許多日誌庫（如 `flutter_logs`, `f_logs`）主打「本地資料庫持久化」。這在理論上看似美好，但在實務上是災難：
  1. **I/O 阻塞與 GC 抖動**：高頻日誌寫入 SQLite 會造成 UI 卡頓與 Jank。
  2. **版本遷移地獄**：除錯工具自身的資料庫版本若與宿主衝突，將引發難以排查的 crash。
  3. **隱私與安全暴雷**：未經 Redaction 脫敏的 Auth Token 或用戶密碼若落盤在 SQLite，在產線環境將構成嚴重的資安合規漏洞。
  4. **好品味解法**：記憶體由 `RingBuffer`（500 筆上限）鎖定上限；排查證據由 `buildDiagnosticReport`（Markdown 報告）一鍵透過系統分享帶走。**排查要的是證據，不是留在手機裡的歷史資料庫！**

#### 核心決策三：拒絕 In-App 記憶體洩漏追蹤（深入剖析官方 dart-lang/leak_tracker）

##### 【背景與動機】
在社群與除錯需求討論中，常有一種聲音：「既然 `flutter_inspector` 已經有 Navigator 堆疊與生命週期追蹤，能不能像 Android 的 LeakCanary 一樣，在手機上直接抓出哪個頁面或 Controller 發生記憶體洩漏（Memory Leak）？」
官方 `dart-lang/leak_tracker` 正是 Flutter/Dart 官方團隊主導的記憶體洩漏偵測專門庫。我們從底層機制、執行時期代價、跨平台限制到哲學定位進行全面剖析，評估其是否有資格進入 `flutter_inspector` 核心。

##### 1. `leak_tracker` 核心實現機制深探
* **Flutter 框架層 `FlutterMemoryAllocations` 的監聽與生命週期依賴**：
  * `leak_tracker` 透過註冊 `FlutterMemoryAllocations.instance.addListener((ObjectEvent event) { LeakTracking.dispatchObjectEvent(event.toMap()); })` 監聽框架物件建立與銷毀事件。
  * 涵蓋 `ui.Image`、`ui.Picture`、`RenderObject`、`Layer`、`PipelineOwner`、`Element`、`State`、`AnimationController`、`Ticker`、`Route`、`ChangeNotifier`。
  * **致命限制 ①（Profile / Release 模式靜默失效）**：框架內所有調用點皆為 `assert(debugMaybeDispatchCreated(...))` 與 `assert(debugMaybeDispatchDisposed(...))`。在 Profile 與 Release 模式下，`assert` 會被編譯器完全消除；且 `kFlutterMemoryAllocationsEnabled` 預設為 `_kMemoryAllocations || kDebugMode`。在 QA 最常使用的 Profile 模式下會「靜默完全失效」，除非宿主編譯時傳入 `--dart-define=flutter.memory_allocations=true`，嚴重違反對開發者透明與零心智負擔原則。
  * **致命限制 ②（海量事件風暴 Event Storm）**：常規頁面切換與動畫重建每秒涉及數千個 `Element`、`RenderObject`、`Layer` 的頻繁建立與釋放，每次事件派發都會遍歷 listener 清單，對 UI 執行緒的 Event Loop 形成極大負擔。
* **物件追蹤、Finalizer、Expando 與狀態機**：
  * **弱引用隔離（WeakReference）**：`ObjectRecord` 透過 `WeakReference<Object>(object)` 持有物件目標，並以 `identityHashCode(object)` 建立索引，避免自身持有強引用而造成偽洩漏。
  * **GC 回收感知（Finalizer）**：使用 Dart 2.17+ 的 `Finalizer<Object>`，當物件在 VM Heap 被回收時，非同步調用 `_onObjectGarbageCollected`。
  * **Expando vs Finalizer 邊界**：Dart 2.17 之前的 `Expando` 本質是弱鍵關聯表，無法在物件被 GC 時主動回呼，只能被動輪詢；現代 `leak_tracker` 已全面遷移至 `Finalizer`，但這帶來了對 VM 底層 GC 排程的深度依賴。
  * **物件狀態機與三類洩漏**：
    1. `LeakType.notDisposed`：物件被 GC 回收了，但從未調用過 `dispose()`（生命週期管理失職）。
    2. `LeakType.notGCed`：物件已調用 `dispose()`，但經過了數次 GC 週期與時間門檻後依然存活，代表被強引用釘死在記憶體中（最嚴重的記憶體洩漏）。
    3. `LeakType.gcedLate`：物件已調用 `dispose()`，但延遲回收。
* **保留路徑（Retaining Path）抓取機制**：
  * 深度依賴 `package:vm_service` 透過 `Service.controlWebServer(enable: true)` 開啟本地 WebSocket。
  * 調用 `Service.getObjectId(object)` 與 `Service.getIsolateId(...)`。
  * 非同步向 VM Service 發送 `service.getRetainingPath(...)`，遍歷整個 VM 堆疊對象圖。

##### 2. 執行時期代價與跨平台致命傷
* **幀率毀滅者：`forceGC` 的激進記憶體配置本質**：
  * 正常 UI 運行時，Dart VM 可能數分鐘都不會觸發 Full GC，導致追蹤器無法判定物件是否「逾期未回收（notGCed）」。
  * 為此，`leak_tracker` 提供了 `forceGC()`（`helpers.dart:25-48`）：在 UI isolate 上透過 while 迴圈**反覆產生長度 30,000 的整數列表（`List.generate(30000, ...)`），強行把 VM 記憶體撐爆，逼迫 VM 執行 Full GC**！
  * 此行為在手機端會引發極端 CPU 暴衝、記憶體劇烈抖動、數百毫秒的嚴重 UI Jank / 凍結幀，甚至直接觸發 OS LMK（Low Memory Killer）使 App 崩潰。
* **定時輪詢與堆疊捕獲開銷**：
  * `LeakReporter` 預設以 `Timer.periodic(1s)` 輪詢所有待 GC 集合，在 Event Loop 上持續耗能。
  * 若開啟 `collectStackTrace`，每次物件建立/銷毀皆調用 `StackTrace.current`，FPS 跌至個位數；內部 6 個非定長集合隨物件生成失控膨脹，追蹤器自身可佔用數十 MB 記憶體。
* **跨平台死穴（Web / WASM 斷手）**：
  * Web (JS / WASM) 環境缺乏 `reachabilityBarrier`、`Service.getObjectId`、`Service.controlWebServer`。
  * `leak_tracker` 官方之 `_retaining_path_web.dart` 直接硬編碼：`retainingPathImpl(...) async => null;`。
  * `forceGC()` 在 Web 與 Release 模式下官方標註完全無效。
  * 深度綁定 `package:vm_service`，與 `flutter_inspector` 全平台（含 WASM/Web）一等公民支援原則直接衝突。

##### 3. 三種整合路線的實用性與破壞性評估矩陣

| 評估維度 | 路線 1：Direct In-App Integration<br>（核心內建或默認啟用） | 路線 2：Recipe / Optional Adapter<br>（文檔食譜或可選適配器） | 路線 3：Rejection / Keep External<br>（保持完全獨立，交由官方 DevTools） |
|---|---|---|---|
| **實作形式** | 核心相依 `leak_tracker`，監聽 `MemoryAllocations`，自建 In-App 洩漏面板 | 核心零相依，提供 `LeakTrackerAdapter` 供宿主手動將 leak 事件轉成 log | 核心零新增，明確宣告為 Anti-Feature，指引至官方 DevTools Memory |
| **對 Userspace 影響** | 🔴 災難（UI Jank、記憶體膨脹、干擾被測 App） | 🟢 零干擾（開關完全由宿主掌控） | 🟢 零干擾（被測 App 乾淨純粹） |
| **WASM / Web 相容** | 🔴 嚴重割裂（Web 上 Retaining Path 恆為 null） | 🟢 完全相容（僅接收字串與等級） | 🟢 完全相容 |
| **外部相依性** | 🔴 沉重（拖入 `vm_service`, `clock` 等） | 🟢 零新相依（純介面或 README 食譜） | 🟢 零新相依 |
| **排查因果價值** | 🔴 雜訊（滿螢幕推測性 notGCed 誤報） | 🟡 湊合（一筆帶時間戳的 warning log） | 🟢 純淨（因果鏈不被推測性分析污染） |
| **最終評估** | ❌ **堅決否決** | 🟡 **僅作可選食譜，不進核心** | ✅ **最佳實踐與核心裁決** |

##### 4. Linus 模式五層分解
* **第 1 層：資料結構分析**：
  * `leak_tracker` 核心由 6 個非定長集合（`notGCed`, `notGCedDisposedOk`, `notGCedDisposedLate`, `notGCedDisposedLateCollected`, `gcedLateLeaks`, `gcedNotDisposedLeaks`）管理物件生命週期，資料隨時跨集合搬移且持續膨脹。相較之下，`flutter_inspector` 的資料結構是斯巴達式的 `RingBuffer`，固定上限、O(1) 淘汰、零自體洩漏風險。
* **第 2 層：邊界情況識別**：
  * 「好的程式碼沒有特殊情況。」`leak_tracker` 充斥大量特殊條件補丁：官方在原始碼註釋中明言「若使用者約 5 分鐘無操作，VM 不跑 GC 就會引發 notGCed 誤報」，為此堆疊了 `numberOfGcCycles`、時間閾值、`CreationChecker` 與測試白名單。當一個機制需要 5 分鐘無操作的猜測與一堆例外補丁才能維持時，其設計已然失控。
* **第 3 層：複雜度審查**：
  * 這功能的本質一句話：「找出誰持有被廢棄物件的強引用」。但為此強行引入 WebSocket、VM Service RPC 通訊、Finalizer、輪詢計時器與記憶體激進分配。砍掉 Retaining Path 則失去排查診斷意義，留著則讓除錯工具膨脹為肥重 Profiler。
* **第 4 層：破壞性分析**：
  * 破壞 Web/WASM 一致性；破壞 Profile 模式透明性；激進記憶體分配破壞影格率甚至引發 OOM Crash。
* **第 5 層：實用性驗證**：
  * 手機小螢幕根本無法舒適閱讀深度保留路徑樹；真實除錯場景應連線桌面端 DevTools。In-App 排查真正需要的是 §P21 提供的 OS 級記憶體壓力前導信號（`WidgetsBindingObserver.didHaveMemoryPressure()`），而非在手機內塞入修車廠手術台。

##### 5. 最終核心裁決與處置規範
* **【核心判斷】**：❌ **堅決拒絕 Direct In-App 整合**。對齊 Anti-Feature #1（拒絕 Profiler）與 Anti-Feature #8（拒絕 Widget Tree 反射）。
* **【關鍵洞察】**：記憶體洩漏分析是離線 Profiling 職責；In-App 偵錯器只需記錄 OOM 前導信號（§P21 `didHaveMemoryPressure()`）。
* **【處置規範】**：
  1. **核心零新增、零相依**：維持 `flutter_inspector` 超輕量架構，絕不引入 `leak_tracker` 或 `vm_service`。
  2. **Anti-Features 補強**：在 Anti-Feature #1 明文增列 2026-09-04 對 In-App 記憶體洩漏分析器之否決紀錄。
  3. **生態適配規範（可選 Adapter 食譜）**：若宿主應用在特定測試流程或自定義環境中已啟動了 `leak_tracker`，可透過以下 **5 行純轉譯食譜**，將洩漏摘要轉為一筆 `LogLevel.warning` log 併入既有 Timeline，享受因果關聯與 Markdown 報告匯出，套件本體絕不增加任何相依：
     ```dart
     // 宿主端可選接線食譜（零新相依）：
     LeakTracking.start(
       config: LeakTrackingConfig(
         onLeaks: (LeakSummary summary) {
           if (summary.isNotEmpty) {
             FlutterInspector.instance.log(
               '⚠️ Memory Leak Detected: ${summary.toMessage()}',
               level: LogLevel.warning,
               data: summary.toJson(),
             );
           }
         },
       ),
     );
     ```

---

### 4. 具體可落地的 4 大整合提案

基於上述評估，我們從社群優秀實踐中提煉出 **4 項高 ROI、零新相依、完全符合 Linus 好品味** 的具體功能提案：

#### §P16. 生態日誌適配器（Ecosystem Adapters: `logger` & `talker` & `logging`）
* **痛點**：許多專案已經在使用 `package:logger`、`package:talker` 或官方 `package:logging`，若要手動改呼叫 `FlutterInspector.log()` 會產生巨大的遷移摩擦。
* **好品味設計（核心洞察）**：
  > 不要讓宿主選邊站。外部日誌庫的日誌，只是一條 `LogEntry` 的原料。
  - **零新相依**：不將 `logger` 或 `talker` 加入 `flutter_inspector_kit` 的 `pubspec.yaml`，而是提供純介面適配器與 README 接線食譜：
    1. **`InspectorLogOutput`**（針對 `package:logger`）：
       ```dart
       // 宿主端 5 行接線：
       class InspectorLogOutput extends LogOutput {
         InspectorLogOutput(this.inspector);
         final FlutterInspector inspector;
         @override
         void output(OutputEvent event) {
           for (final line in event.lines) {
             inspector.log(line, level: _mapLevel(event.level));
           }
         }
       }
       ```
    2. **`InspectorTalkerObserver`**（針對 `package:talker`）：
       ```dart
       // 宿主端監聽 Talker 事件並轉入 Inspector
       class InspectorTalkerObserver extends TalkerObserver {
         InspectorTalkerObserver(this.inspector);
         final FlutterInspector inspector;
         @override
         void onLog(TalkerData log) => inspector.log(log.generateTextMessage(), level: _mapLevel(log.logLevel));
         @override
         void onError(TalkerError err) => inspector.log(err.message, level: LogLevel.error, stackTrace: err.stackTrace);
         @override
         void onException(TalkerException exc) => inspector.log(exc.message, level: LogLevel.error, stackTrace: exc.stackTrace);
       }
       ```
    3. **`InspectorLoggingHandler`**（針對官方 `package:logging`）：
       ```dart
       Logger.root.onRecord.listen((record) {
         inspector.log(record.message, level: _mapLoggingLevel(record.level), stackTrace: record.stackTrace);
       });
       ```
* **重用**：既有 `FlutterInspector.log()`、`LogEntry`、`LogLevel`。
* **Effort**：trivial~low ｜ **排查價值**：⭐⭐⭐⭐（零相依打通百萬級日誌生態）

---

#### §P17. 原生折疊式 JSON 樹狀檢視器（Collapsible JSON Tree Viewer: `JsonTreeViewer`）
* **痛點**：目前 `NetworkDetailView` 與 `LogDetailView` 在展示大型 JSON Payload / Response Body 時，只能顯示純文字或扁平的 `KeyValueTable`。當面對深層巢狀（3+ 層）物件或陣列時，排查者很難快速折疊無關分支或定位特定欄位，體驗落後於 Alice / Chucker 的 JSON 瀏覽器。
* **好品味設計（核心洞察）**：
  > JSON 解析完後就是 Dart 原生的 `Map<String, dynamic>` 與 `List<dynamic>`。不需要引入第三方肥大 json_viewer 套件，用一個 150 行以內的純原生遞迴 Widget 即可消滅問題。
  - 新增 `JsonTreeViewer`（`lib/src/ui/widgets/json_tree_viewer.dart`）：
    - 遞迴節點展開/折疊（預設展開前 2 層）。
    - Material 3 語法色彩高亮：Key（紫）、String（綠）、Number（橘）、Bool（藍）、Null（灰）。
    - 支援長按/點擊「一鍵複製節點 JSON 路徑與值」（如 `data.users[0].id`）。
    - 支援文字搜尋過濾高亮。
* **重用**：Material 3 主題配色、`KeyTheme`。
* **品味守則**：零外部相依，純 Dart 遞迴渲染，性能極致（透過 `ListView.builder` 與扁平化節點清單避免 O(N²) 重建）。
* **Effort**：medium ｜ **排查價值**：⭐⭐⭐⭐⭐（大幅提升 API 排查可讀性）

---

#### §P18. 輕量網路效能統計條（Lightweight Network Stats Bar）
* **痛點**：排查網路群體故障時，除了個別錯誤聚合（§7），QA/開發者常需要一眼看到「總請求數、失敗率、平均響應時間、總傳輸量（Bytes）」，以評估是否發生網路劣化或流量異常。
* **好品味設計（核心洞察）**：
  > 這些統計數據全部已經躺在 `NetworkInspector` 的 `RingBuffer<NetworkEntry>` 裡！
  > 不需要發明 Profiler，不需要定時器，只需要一個無狀態純函式 `calculateNetworkStats(entries)`。
  - 在 `NetworkTab` 頂部新增一個高密度的 **Stats Bar**（單行 4 個指標）：
    - `📊 Total: 142` ｜ `❌ Fail: 3 (2.1%)` ｜ `⚡ Avg: 185ms` ｜ `📦 Size: 1.2MB`
  - 點擊指標可快速套用過濾（如點擊 `Fail` 觸發 `errors-only`）。
* **重用**：`RingBuffer<NetworkEntry>`、`NetworkEntry.duration`、`NetworkEntry.responseBody` 長度。
* **品味守則**：純計算投影，零儲存成本，不追 HAR 虛假分段 timings。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐⭐

---

#### §P19. StackTrace 非同步呼叫鏈與框架噪聲正規化（StackTrace Async Gap Normalization）
* **痛點**：Flutter 拋出的 stackTrace 往往充斥大量框架內部長達數十行的內部呼叫（如 `package:flutter/src/widgets/framework.dart`），且在 async/await 跨越後會被 `<asynchronous suspension>` 分割成難以辨識的片段，真正出錯的業務程式碼被淹沒在噪聲中。
* **好品味設計（核心洞察）**：
  - 借鑒官方 `stack_trace` 套件的精髓（或內建輕量 Regex 剖析器）：
    1. **折疊框架噪聲 (Frame Folding)**：自動將連續的 `package:flutter/*` 或 `dart:*` 內部 frame 摺疊為「*+ 12 Flutter internal frames*」，預設突出高亮 `package:宿主App/*` 的程式碼行。
    2. **非同步鏈拼接 (Async Gap Demangling)**：清楚標示非同步跳轉點，並提供一鍵「複製精簡堆疊 (Concise Stack)」與「複製原始堆疊 (Raw Stack)」。
* **重用**：`LogDetailView` 的 StackTrace 展示區塊、`share_text.dart`。
* **品味守則**：可選使用 Dart 官方維護之 `stack_trace`（Dart SDK 內建或輕量相依），絕不破壞原始堆疊字串。
* **Effort**：low–medium ｜ **排查價值**：⭐⭐⭐⭐
* **✅ 實作現況（PR #149）**：`normalizeStackTrace` 實作完成。透過 Regex 安全識別 `package:flutter/` 與 `dart:` 呼叫並摺疊為 `[... N frames of framework internals]`，且刻意保留連續框架呼叫的**頭尾邊界 frames**，避免丟失重要呼叫上下文。非同步中斷處換為 `<-- async gap -->`。UI 端 `LogDetailView` 增加「Show raw/concise」切換按鈕，預設顯示 concise 堆疊，複製與分享功能會跟隨當下 UI 模式匯出對應內容；`buildLogPlainText` 預設輸出 concise 堆疊。


---

## 🎯 第七部分：Google Play 品質要求（Q3-2026）× 執行時期排查（2026-09-01 新增）

> **背景**：Google Play 2026 Q3「Elevating app quality」新增／收緊多項品質門檻——
> [App quality 要求](https://support.google.com/googleplay/android-developer/answer/17492799)
> 與 [Android vitals / Core Vitals](https://developer.android.com/topic/performance/vitals)。
> 本部分評估：這些門檻涉及的**執行時期信號，哪些能在 app 進程內（純 Flutter/Dart）被 kit 觀測到並落進混合時間軸供鏈推斷**。
>
> **調研方法（2026-09-01）**：多 agent 對抗式調研——8 個信號各查 app 內可觀測性 → 可行者設計成 kit 功能 → 每個經 3 個 lens（技術可行性／不變式衝突／鏈推斷哲學）審查。

### 查核結論：只有 4 類信號 app 內可觀測

Google 的 10 類信號中，**6 類的核心信號在 Dart 執行之前或 OS/build 層，kit 碰不到**（見下方「不可觀測」表）；剩 4 類可觀測且全部契合鏈推斷（進時間軸當因果原料，非孤立儀表數字）。

| 信號 | Google 門檻 | app 內可觀測？ | 觀測機制 |
|:---|:---|:---:|:---|
| Slow Rendering（掉幀/凍結幀） | Core Vital | ✅ | `SchedulerBinding.addTimingsCallback` → `FrameTiming` |
| Memory / LMK | Feb 2027 強制 | ✅（前導信號） | `WidgetsBindingObserver.didHaveMemoryPressure()` |
| Permission Denials | Additional vital | ⚠️（需 host 餵） | host 在 call site 記入既有 log |
| Crash rate | 1.09% | ✅（已有） | 既有 `captureUncaughtErrors`（可強化為 crash 前鏈快照） |

### §P20. 掉幀/凍結幀維度（`capturePerformance`）— 🆕 旗艦 · ⚠️ 與 Anti-Feature #1 衝突待裁決

> **🔴 動工前必讀（2026-09-01 交叉核對發現）**：本節設計與 **Anti-Feature #1 於 2026-08-14 覆核時明確否決的變體是同一個東西**（同樣是「不做 profiler 面板，只用 `SchedulerBinding.addTimingsCallback` 把單幀超標轉成離散事件併入 `mergedTimeline`」）。該否決的死因是 **debug build**：
> 無 AOT、assert 全開，`buildDuration` 系統性偏慢數倍，判定掉幀會**大量誤報**而非漏報，timeline 會被假 jank 洗版，反過來污染 Console 這條原本乾淨的排查鏈；而本 kit 是 debug-only 工具，**誤判不是邊緣情況，是唯一情況**。
>
> 本節（2026-09-01 由 Google Play 品質門檻角度提出）**並未回應此否決理由**——對齊 Core Vital 是「為什麼值得做」，不構成「debug build 測得準」的反證。
>
> **本項狀態為「待裁決」，非「待辦」。** 排程前必須二擇一：
> 1. **撤銷否決** — 需先提出 debug build 誤報的具體解法（例如僅在 profile/release 模式啟用、或以相對基準線取代絕對門檻），並同步改寫 Anti-Feature #1 的覆核段落；
> 2. **撤下 §P20** — 維持 Anti-Feature #1 原判，本節降為「已評估／不排程」。
>
> 在裁決落地前，**不應進入實作排程**。

* **痛點**：Slow Rendering 是 Core Vital，直接影響商店能見度。Play Console 只給**聚合百分比**（知道多爛、不知爛在哪一步）。app 內時間軸能提供 Console 拿不到的「烂在哪個事件之後」維度。
* **好品味設計（核心洞察）**：
  > 掉幀不是一個要顯示的「當前 FPS 數字」（那是被否決的即時儀表、切斷前後文的點查詢）。它是一個**帶時間戳的離散事件**，該落進混合時間軸。
  - 新增 `JankEntry implements TimestampedEntry` + `JankInspector`（內含 `RingBuffer(500)` + 掛 `onMutate`），走「新增緩衝型維度」標準三件套。
  - `SchedulerBinding.instance.addTimingsCallback((List<FrameTiming>){...})`：`buildDuration + rasterDuration` 超門檻（預設 32ms）即記一筆。
* **公開 API**：建構式旗標 `bool capturePerformance = false`（對齊 `captureUncaughtErrors`/`captureLifecycleEvents`）+ `Duration jankThreshold`（對齊 `slowRequestThreshold` 門檻慣例）。**非** `registerXxx` 註冊式——緩衝型套件內建，不是 Host 註冊的即時查詢型。
* **重用**：kit 已 import `SchedulerBinding`（`console_tab.dart` 用 `endOfFrame`）。零新相依。
* **鏈推斷價值**：一次 700ms 凍結夾在時間軸的 network 回來、route push、db 查詢之間，讓「凍結發生在哪個大 JSON 之後／哪次跳轉當下」變成看得見的因果脈絡；且能分辨 build 期 jank（同步 decode／巨大 rebuild）與 raster 期 jank——這本來就需要前後文，非單一數字能給。
* **🔴 動工必讀（3 個 lens 都獨立點出的實作地雷）**：
  > `JankEntry.timestamp` **絕不能**用 `FrameTiming.timestampInMicroseconds`——那是 dart:ui 的 **monotonic 時鐘**（自 engine 啟動計時），不是 wall-clock epoch。既有 4 維 timestamp 全是 `DateTime.now()`。直接換算會讓 jank 事件在 `mergedTimeline` 降序排序時全甩到最舊端，**「掉幀在哪個 network 之後」這個唯一賣點當場歸零**，且單測不易抓（本機時間看似合理）。
  >
  > **正解（最笨最對）**：callback 觸發當下用 `DateTime.now()` 當 timestamp（延遲數十 ms，對因果排序精度綽綽有餘）；frame 的 build/raster **duration** 照實記進 payload（monotonic diff 的正當用途，不受 epoch 影響）。
* **次要**：Web 平台 `FrameTiming` 上報不完整，需明講降級（不 crash 但「四平台一致」在 Web 打折）；`TimelineSource` enum 加 jank 要同步 `mergedTimeline` / console_tab filter chip 三處。
* **Effort**：low~medium ｜ **排查價值**：⭐⭐⭐⭐⭐（對齊 Core Vital，鏈推斷價值最高）

### §P21. 記憶體壓力事件（併入 `captureLifecycleEvents`）— ✅ 已完成（PR #155）

* **痛點**：Memory usage（RSS+Swap / Bitmap）Feb 2027 強制。真正的 RSS 數值需 platform channel（粗糙且跨平台不一），但 **OOM/LMK 前的「記憶體壓力」是 Dart 層唯一拿得到的前導信號**。
* **好品味設計**：
  > `WidgetsBindingObserver.didHaveMemoryPressure()` 是 Flutter SDK 內建回呼，而 kit 的 `LifecycleHandler` 已經是 observer——**多接一個 callback 即可**，寫進既有 log／lifecycle 時間軸，不新增 Entry/Inspector/RingBuffer。
* **公開 API**：**已裁決併入既有 `captureLifecycleEvents`**，不新增 `captureMemoryPressure` 旗標——兩者是同一個 `WidgetsBindingObserver` 上的 callback、共用同一組 attach/detach 生命週期，拆兩個旗標只是多一個特殊情況。
* **重用**：`LifecycleHandler` 既有 observer + 既有 log 維度。零新相依。
* **鏈推斷價值**：把 OOM 前唯一的 Dart 層前導信號插進時間軸，讓 crash 前的 memory pressure 與其之前的 network/route/db 並排，讀出「壓力密集出現在載入大圖之後」這種因果推斷。
* **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐（強化既有維度，零風險，建議當暖身第一項）

#### ❌ 曾嘗試強化並整案撤回：附加 ImageCache 水位（Issue #158 · 2026-09-08）

> **結論先講**：**這條路不通，別再提**。不是實作沒做好——實作做完了、584 測試全綠、
> analyze 零新增，是**功能的前提被 SDK 行為打穿**。Issue #158 的分支已重置，零程式碼留下。

**原提案**：在既有那筆 warning 的訊息尾巴附上事件當下的 ImageCache 水位——

```
現況：Memory pressure · HomePage (/home)
提案：Memory pressure · HomePage (/home) · imageCache 98.2 MB/100.0 MB (212 imgs)
```

賣點是**否證能力**：水位只有 3 MB 就能當場排除圖片方向，省下翻圖片程式碼的時間。
「排除一個方向與指出一個方向同等有用」——這個論點本身沒錯，錯的是它建立在
「pressure 當下讀得到有意義的水位」這個**未經查證的假設**上。

**死因：`PaintingBinding` 在通知 observer 之前就把快取清空了。**

```dart
// packages/flutter/lib/src/painting/binding.dart:160
@override
void handleMemoryPressure() {
  super.handleMemoryPressure();
  imageCache.clear();                      // ← 先清空
}

// packages/flutter/lib/src/widgets/binding.dart:1372
@override
void handleMemoryPressure() {
  super.handleMemoryPressure();            // ← 這一步走到上面那個 clear()
  for (final observer in List.of(_observers)) {
    observer.didHaveMemoryPressure();      // ← 才輪到我們讀
  }
}
```

關鍵在 mixin 順序：`WidgetsFlutterBinding` 的清單是
`... PaintingBinding, SemanticsBinding, RendererBinding, WidgetsBinding`，
**`WidgetsBinding` 在最後、其覆寫最先執行**，而它第一件事就是 `super`——
往前走到 `PaintingBinding` 執行 `imageCache.clear()`。清空完成後，才輪到通知 observer。

**實測證據**（spy observer 讀同一個 cache 實例，非推論）：

```
BEFORE pressure:  size=256  count=1
INSIDE observer:  size=0    count=0      ← didHaveMemoryPressure() 讀到的
AFTER  pressure:  size=0    count=0
```

**後果是功能價值歸零，且反轉為危害**：該功能永遠只會輸出
`imageCache 0 B/100.0 MB (0 imgs)`——分子與張數恆為 0，唯一有值的是分母
（`maximumSizeBytes`，`clear()` 不動它）。於是原本的兩列判別塌成一列：

| 原設計預期顯示 | 實際永遠顯示 | 排查者會得到的結論 |
|:---|:---|:---|
| `98.2 MB/100.0 MB` → 圖片層有事 | — | 永遠看不到 |
| `3.1 MB/100.0 MB` → 不是圖片 | `0 B/100.0 MB` | **「不是圖片問題」——即使圖片正是問題** |

這是**假否證**：它會讓排查者主動排除正確的方向。踩到的正是本文件在
**Anti-Feature #3（拒絕 HAR timing 的假精度）** 與第七部分**拒絕「總記憶體估算值」**
時用的同一條判準——**假精度比沒有資訊更糟**，因為讀者會照著錯的數字推錯方向。

**已排除的變通方案**（皆實查，非推測）：

| 方案 | 判定 |
|:---|:---|
| 改讀 `liveImageCount`（`clear()` 不清 live images） | ❌ 實測在 observer 內同為 **0**，無可用的替代存活指標 |
| 只在測試環境有問題、真實 OS 事件不同路 | ❌ 不成立。`services/binding.dart:177` 收到系統 `memoryPressure` 訊息後走**同一個** `handleMemoryPressure()`，沒有第二條路徑 |
| 只是某個 SDK 版本的行為 | ❌ 不成立。3.41.9 與 3.44.1 上述兩段程式碼**逐字相同**，涵蓋 `pubspec.yaml` 宣告的整個支援範圍（`flutter: ">=3.10.0"`） |
| 覆寫 binding，在 clear 之前取值 | ❌ 要求 host 改用套件提供的 custom binding，破壞「接線零改動」前提，成本遠超價值 |

> **該需求的正確形狀是 §P25（ImageCache 水位計）**——不綁任何 OS 事件，
> 在使用者主動查看的那一刻讀取，那個時點的值是真的。

**🔴 本案最該記住的教訓（方法論，不是技術細節）**：

規格階段確實做了實查，查證的是「`currentSizeBytes` / `maximumSizeBytes` / `currentSize`
三個 getter 存在、公開、純 Dart、零相依、O(1)」——**這些全部正確**。
但**沒有查證「在 `didHaveMemoryPressure()` 這個時點，讀到的值是否有意義」**。

**前者是 API 存在性，後者才是功能可行性。把前者當成後者的證明，就是這次的失誤。**
review 階段的 mutation testing 之所以能揭穿它，是因為它問的不是「API 在不在」，
而是「改壞了測試會不會叫」——四個接線 mutation 有三個逃逸，才順藤摸瓜挖出恆零的根因。

> **可執行的防範規則**：日後規格涉及「在特定時點讀取外部狀態」時，
> **必須實測該時點的值**（寫個 spy/probe 跑一次），不能只確認 API 存在。
> 這條成本是十幾行拋棄式測試碼，換掉的是一整輪實作 + review + 撤回。

### §P22. 權限被拒便利方法（`permissionDenied(...)`）— 🆕 弱但有用

* **痛點**：Permission Denials 是 Additional vital。但 Flutter framework **無任何 permission binding**——沒有可被動訂閱的全域信號源（實查 `network_notifier_io.dart`：kit 只在自己的 call site 拿得到權限回傳值）。
* **好品味設計**：
  > 不設新緩衝型維度（沒有可掛的觀測源）。提供薄便利方法讓 **host 在拒絕的 call site 主動記入既有 log**，帶 `activeRoute` 錨點。
* **公開 API**：`permissionDenied(permission, {activeRoute})`——對齊既有 `log`/`logNetwork`/`database` 每維度一具名 forward 的慣例（**非** `capture` bool flag，因為 kit 無法自動觀測、只能被動接收 host 餵的資料）。
* **哲學審查提醒**：philosophy lens 判為 **weak**——它**不提供新的因果原料**（permission 資訊 host 在 call site 已握有），kit 只多貢獻 `activeRoute` 錨點與時序。價值真實但有限，API surface 是否值得暴露待定（可能只需文件示範用既有 `log` 記即可，不必新增方法）。
* **Effort**：trivial ｜ **排查價值**：⭐⭐

### §P23. Crash 前因果鏈快照（強化既有 `captureUncaughtErrors`）— 🆕 待評估

* **痛點**：Crash rate 門檻 1.09%（Core Vital）。kit 已有 `captureUncaughtErrors`，但目前只記「錯誤本身」。
* **方向（尚未細設計）**：crash 發生時，既有 `mergedTimeline` 已天然保留了 crash 前的完整 log/network/nav/db 事件鏈——診斷報告已能匯出。待評估的是「是否需要在 crash 當下自動觸發一次診斷報告匯出/標記」，讓 QA 拿到的 crash 報告自帶前因果鏈。
* **注意**：這必須小心不要變成被否決的「錯誤上下文快照」（§P2，固定挑幾個維度釘在 error 旁 → 預設因果單線）。正解仍是完整 `mergedTimeline`，此項頂多是「crash 時自動觸發既有匯出」，不新增快照機制。
* **Effort**：low ｜ **排查價值**：⭐⭐⭐（待確認是否與既有診斷報告重疊）

### §P24. Crash 系統通知（Crash Notification）— ✅ 已完成（Issue #156 · 2026-09-06）

* **痛點**：套件僅在 API 呼叫時推送系統通知（`showNetworkNotification`），**崩潰發生時沒有任何系統層級的即時提示**。App 在背景時，QA／開發者完全不知道剛剛發生 crash；即使在前景，也得主動打開 dashboard 才會發現 error 進了 timeline。**網路異常有通知、崩潰卻沒有——這個不對稱沒有正當理由。**
* **好品味設計（核心洞察）**：
  > 不要新增 `CrashNotifier` 類別。那會複製一份 init／permission／平台守衛邏輯，且 `_io`/`_web` 雙分支各再多一份——四份檔案的維護成本，換一個「語意不同」的假需求。
  >
  > 正解是把「一則通知」的身分（id + channel）參數化，`NetworkNotifier` 就成為這個通用能力的**其中一個呼叫者**，crash 只是**換參數再建一個實例**。
  - `_notificationId` / `_channelId` / `_channelName` 由 `static const` 改為 `final` 實例欄位，新增 `NetworkNotifier.crash()` 具名建構式（此即 §P11 重構本體）。
  - crash 與 network 的四點差異，全部從「crash 是**離散事件**而非持續更新的摘要」這一點推導而出：獨立 id（不互相覆蓋）、獨立 channel（可分別靜音）、`ongoing: false`（可滑掉）、不執行 legacy channel 刪除（那只屬於 network）。
* **公開 API**：建構式旗標 `bool showCrashNotification = false`（對齊既有 `showNetworkNotification` 慣例）。
  > **刻意不自動開啟 `captureUncaughtErrors`**：安裝全域 error hook 是 host 的決定，套件不代為決定。兩者需搭配使用，已在 dartdoc 明講。
* **重用**：三個 crash hook（`FlutterError.onError` / `PlatformDispatcher.instance.onError` / `ErrorWidget.builder`）**皆已存在**於 `uncaught_error_handler.dart`，本功能**不新增任何 hook**；`AlertThrottler` 邏輯零修改（crash 持有自己的實例，與 network 節流互不干擾）。
* **接線點的判斷**：通知掛在 `UncaughtErrorHandler` 的 `onLog` callback，**不是** `FlutterInspector.log()`——後者是公開 API，掛在那裡會讓 host 自己的 `log(level: error)` 也跳通知，那不是「crash 通知」。
* **自動繼承既有去重**：`UncaughtErrorHandler._lastLoggedDetails` 已處理「`FlutterError.onError` + `ErrorWidget.builder` 對同一錯誤雙擊」，通知走在 log 之後，不需另寫一套。
* **🔴 實作教訓（條件匯出的驗證方式）**：`_io`/`_web` 簽章漂移是本次最大破壞風險（CLAUDE.md 不變式 #4），而 **`flutter test` 完全抓不到**——測試跑在 VM 上全程走 `_io`，`_web.dart` 根本不會被載入，少一個建構式也能測全綠。
  > **且 `example/` 不能當關卡**（2026-09-06 實測）：它依賴 ObjectBox（native-only、`dart:ffi`），在該目錄跑 `flutter build web` **永遠失敗且與本功能無關**。正解是建一個只依賴本套件的最小 harness，讓兩個建構式都進編譯圖後 `flutter build web`——**編譯器擋得住，人眼擋不住**。
* **Effort**：low（實際落地 5 任務）｜ **排查價值**：⭐⭐⭐⭐（補上網路／崩潰的通知不對稱，QA 背景測試場景剛需）

### §P25. ImageCache 水位計（Image Cache Gauge）— 🆕 low priority

> **本項是 Issue #158 那個需求唯一可行的形狀**。該案想在 memory pressure 事件當下讀水位，
> 但 `PaintingBinding` 在通知 observer 前就清空快取，讀到的恆為 0（完整死因見 §P21 的
> 撤回紀錄）。**本項不綁任何 OS 事件**——在使用者主動查看的那一刻讀取，那個時點的值是真的。

* **設計方向**：
  - Dashboard 內常駐顯示 `currentSizeBytes` / `maximumSizeBytes` 與 `currentSize`（張數）
  - **打開時才讀，不輪詢**（三個 getter 都是 O(1)，沒有輪詢的理由；加輪詢就踩 Anti-Feature #1）
* **建議位置：Storage tab 內加一區**（`lib/src/ui/dashboard/tabs/storage_tab.dart`）
  - imageCache 本質是**即時查詢型**，與 CLAUDE.md 不變式 #3 的 Browser Source 分流**同構**
    ——呼叫時即時拉取、**不進 `RingBuffer`、不進 timeline、不加第五個 `TimelineSource`**
  - Storage tab 在 host 未註冊 source 時是空的（`flutter_inspector.dart:218` 明載套件不內建
    任何 `KeyValueBrowserSource`），剛好給它一個永遠有內容的區塊
  - **🔴 明確不開新的 Performance tab**：為單一 widget 開一個 tab 是過度工程，且會誘導未來
    往裡塞 FPS／jank 指標，**直接滑向 Anti-Feature #1**。這條先寫死，別日後重議
* **價值（四項，第 2 項是 §P21 那條路根本給不了的）**：
  1. **主動量測**，不必等 OS 出手——這才是 Google bitmap memory 頁面實際要求開發者做的事
  2. **能驗證修改有沒有效**：改 `cacheWidth` / `RGB_565` / 快取上限後，同一頁面改前 98 MB、
     改後 31 MB，一眼可證。**綁 pressure 事件的做法給不了這個**——就算它讀得到值，
     修對之後 pressure 就不來了，反而失去量測手段
  3. **有分母才看得出 LRU thrashing**：`98.2/100.0`（頂到上限、圖片反覆被踢掉又重載，
     此時 NetworkTab 會看到同一張圖被抓多次，兩條線索互相印證）vs `98.2/500.0`（只是用得多）
  4. **回收行為可觀察**：切背景再回來、pop 掉圖片牆頁面，看水位有沒有降
* **🔴 必守的誠實劃界（本項最大風險是誤導，不是技術）**：
  - 標題**必須寫 "Image Cache"**，不可寫 "Memory" 或 "RAM"
  - **絕不可湊一個「總記憶體用量」估算值**——WebView 內的圖、native plugin、`dart:ffi`
    配置的記憶體**全都不在此帳上**（cache 顯示 3 MB 而 app 實吃 800 MB 完全可能）
  - 判準同 Anti-Feature #3：**假精度比沒有資訊更糟**。§P21 撤回案就是活生生的反例
* **重用**：`PaintingBinding.instance.imageCache` 三個現成 getter、既有 `formatBytes`
  （`lib/src/utils/network_formatters.dart:48`，支援 B/KB/MB/GB/TB）。零新相依。
* **不做**：定時輪詢、歷史曲線、「快取未回收 = 洩漏」的自動判定
  （LRU 正常行為就會讓水位不降，要判定異常就得堆閾值與例外補丁——那正是 2026-09-04
  否決 `leak_tracker` 的第 2 層理由，換個包裝而已）
* **Effort**：low ｜ **排查價值**：⭐⭐⭐

### 📌 2026-09-08 記憶體觀測選項全面評估（Issue #158 期間，避免日後重提）

使用者引用 Google Play 三個 Vitals 頁面（[memory-usage](https://developer.android.com/topic/performance/vitals/memory-usage)
／[lmk](https://developer.android.com/topic/performance/vitals/lmk)
／[bitmap-memory-usage](https://developer.android.com/topic/performance/vitals/bitmap-memory-usage)）
詢問本套件能否做記憶體洩漏警示或顯示記憶體資訊。逐項實查後結論如下，**前四項已否決，勿再提案**：

| 選項 | 判定 | 依據（皆實查，非推測） |
|:---|:---:|:---|
| **Anonymous RSS + Swap 數值** | ❌ **拿不到** | Google 官方頁面明載「**No in-app API exists** for reading this metric」，資料由 OS telemetry 收集後經 Play Console 呈現。`ProcessInfo.currentRss`（`dart:io`）存在，但①它是 Dart VM 進程 RSS、非 Google 定義的 anonymous RSS+swap；②本套件**刻意從不引入 `dart:io`**（`lib/src/models/diagnostic_info.dart:41` 明載此為 WASM 相容前提）|
| **LMK 事件偵測** | ❌ **需 platform channel** | Google 推薦的是 `ApplicationExitInfo` + `REASON_LOW_MEMORY`，為 Kotlin/Java API，語意是「**下次啟動時回讀**上次為何被殺」而非即時信號。Dart 層無對應 binding |
| **Bitmap memory 宣稱對齊 Play Console** | ❌ **假精度** | `imageCache` 是 Flutter 自己的圖片快取帳面，**不等於** OS 統計的 bitmap memory（後者含 malloc heap、shared memory、graphics buffer）|
| **ImageCache 水位 — 掛在 memory pressure 事件上** | ❌ **讀到的恆為 0** | `PaintingBinding.handleMemoryPressure()` 在通知 observer 前先 `imageCache.clear()`。Issue #158 實作完成後整案撤回，實測證據見 §P21 撤回紀錄 |
| **ImageCache 水位 — 使用者主動查看時讀取** | ✅ **可做** | 見上方 §P25。讀取時點由使用者決定，不受 `clear()` 影響 |

> **🔴 判準沿革（引用時務必分辨，否則會推導出錯誤的相鄰結論）**：
> 本表的否決與 2026-09-04 否決 `leak_tracker` 的**理由完全不同**——
> - 本表前三項是「**Dart 層拿不到**，或拿到的不是那個東西」（**能力邊界**）
> - 第四項是「**拿得到，但在那個時點讀到的值無意義**」（**時序問題**）
> - `leak_tracker` 是「**拿得到，但代價不可接受**」（`forceGC()` 反覆生成長度 30,000 的
>   List 逼 Full GC、Web 上 Retaining Path 恆為 null、Profile 模式因 `assert` 被消除而靜默失效）
>
> 三種否決不可混用。例如「記憶體資訊拿不到」這句話對第四項是**錯的**——它拿得到，
> 只是讀的時機不對，而那正是 §P25 能成立的原因。

### ❌ app 內不可觀測（誠實劃界，勿浪費工）

以下 Google 信號的核心部分在 Dart 執行之前、或 OS/build 層，kit **無法觀測**，不應為湊數硬做代理：

| 信號 | 為何 app 內拿不到 |
|:---|:---|
| **DEX 優化**（Feb 2027 強制） | build-time R8 指標，runtime 零 Dart API。完全不可行 |
| **Zero-tap sign-in restoration**（Apr 2027） | 靜默重登發生在 Flutter engine attach 之前的 native `BackupAgent.onRestore`（Kotlin/Java），framework 無 binding |
| **App Startup Time** | Dart 只拿得到「首幀」這個殘缺代理；真起點（VM warmup、`Application.onCreate` 前）在 Dart 執行之前 |
| **Wake locks / Wakeups / 背景耗電** | Android kernel 電源會計，`PowerManager.WakeLock` acquire/release 在 OS 層，Dart 觀測不到 |
| **真 ANR（>5s 卡死）** | 卡死的 main isolate 連 `addTimingsCallback` 都排不進；要監看需第二個 isolate 當 watchdog，超出「單 isolate 純觀測 + 極輕相依」範疇（§P20 只能觀測「慢幀」不能觀測「完全卡死」） |

### 第七部分優先順序建議

1. ~~**§P21 記憶體壓力**（trivial、強化既有、零風險）→ 暖身首選~~ → **✅ 已完成（PR #155）**。
   Issue #158 曾嘗試為它附加 ImageCache 水位以補強收斂能力，**實作完成後因 SDK 行為整案撤回**
   （`PaintingBinding` 先清快取才通知 observer，讀到的恆為 0；死因與實測見上方 §P21 撤回紀錄）。
   該需求改由 **§P25 水位計**承接（low priority，主動查看時讀取，不綁 OS 事件）
2. **§P20 掉幀維度**（旗艦、對齊 Core Vital、鏈推斷價值最高）→ **⚠️ 目前為「待裁決」而非待辦**：與 Anti-Feature #1（2026-08-14 覆核）否決的變體同源，需先解決 debug build 誤報爭議；若裁決通過，另需把 timestamp 地雷釘死在計畫
3. **§P22 權限** / **§P23 crash 鏈快照** → 依需要，兩者 API surface 都待再確認是否值得暴露
4. **§P25 ImageCache 水位計**（low priority）→ 承接 Issue #158 撤回的需求，不綁 OS 事件

> **🔴 §P21 的一條結構性風險（2026-09-08 查 Google 官方文件發現，此前未載）**：
> `didHaveMemoryPressure()` 在 Android 端是由 **`onTrimMemory`** 餵的
> （`packages/flutter/lib/src/widgets/binding.dart:400` → `SystemChannels.system` 的 `memoryPressure`），
> 而 Google 已將 `onTrimMemory` **多數 callback 標為 deprecated**，只剩
> `TRIM_MEMORY_UI_HIDDEN` 與 `TRIM_MEMORY_BACKGROUND`，理由是「**它們無法有效預防 LMK 事件**」
> （來源：<https://developer.android.com/topic/performance/vitals/lmk>）。
>
> **意義**：§P21 這個「Dart 層唯一的 OOM 前導信號」，未來**觸發密度可能比原提案假設的更稀疏**。
> 這不影響 PR #155 已落地實作的正確性，但它是 §P25 的另一個存在理由——
> **押注單一 OS 事件的排查路徑有結構性上限，主動量測不受此限**。

> 各項寫入路徑：§P20 新增 `lib/src/models/jank_entry.dart` + `lib/src/inspectors/jank_inspector.dart` + 動 `inspector_registry.dart`/`flutter_inspector.dart`/`console_tab.dart`；§P21/§P22/§P23 皆強化既有維度，不新增檔案。

---

## ❌ 拒絕實現的「垃圾」功能（Anti-Features）

堅守「不走向微核心 / 過度工程」：

1. **完整效能 / Jank / 記憶體 Profiler**
   - *拒絕*：FPS 追蹤、frame drop、記憶體 profiling 是**另一個產品維度**，不是「錯誤排查」。Flutter 官方 DevTools 已有強大的 Performance/Memory view，in-app 重造只會是低配輪子。偏離主線，effort=high，**砍**。
   - **2026-08-14 覆核，維持原判**：曾評估一個看似繞得過本條的變體——不做 profiler 面板，只用 stdlib `SchedulerBinding.addTimingsCallback` 把「單幀超標」轉成一筆離散事件併入 `mergedTimeline`（零新相依，且是 app 層級 hook，無 §P10 那種逐 widget 接線問題）。**仍然否決，死因是 debug build**：debug 無 AOT、assert 全開，`buildDuration` 系統性偏慢數倍，判定掉幀會**大量誤報**而非漏報——timeline 會被假 jank 洗版，反過來污染 Console 這條原本乾淨的排查鏈。而本 kit 是 debug-only 工具，**誤判不是邊緣情況，是唯一情況**。連官方 DevTools 都須警告「debug 效能數據不具參考性、請用 profile mode」，in-app overlay 更無立場宣稱測得準。此變體與 Anti-Feature #6（第五個 `TimelineSource` 的全鏈路成本）亦有衝突，但**不必走到那一步就已出局**。
   - **2026-09-01 交叉核對補記**：第七部分的 **§P20 掉幀/凍結幀維度**由 Google Play Core Vital 角度重新提出了**同一個設計**，且未回應本條的 debug build 誤報死因。**兩節目前互相衝突，尚未裁決**——在裁決前本條維持原判，§P20 不得逕自進入排程。詳見 §P20 節首的待裁決警示。
   - **2026-09-04 記憶體洩漏分析（`leak_tracker`）深入評估維持原判**：深入剖析官方 `dart-lang/leak_tracker` 後，確認其核心機制（`MemoryAllocations` 依賴 assert、`forceGC` 激進記憶體配置引發嚴重 Jank、Web/WASM 下 Retaining Path 恆為 null、以及 5 分鐘無操作導致 notGCed 誤判的特殊情況打補丁）完全不符合 In-App 偵錯器定位。堅決拒絕 Direct In-App 內建整合，維持外部獨立；記憶體排查僅保留已落地的 §P21 記憶體壓力前導信號（PR #155），詳細機制與五層分解詳見第六部分 §3 核心決策三。
   - > 附帶結論（供日後看到同類套件清單時參考）：社群「Flutter 效能／崩潰分析」套件清單對本 kit **無一適用**——後端 telemetry SDK（sentry / crashlytics / newrelic / bugly …）與本 kit「資料不出裝置」的定位方向相反；FPS 小工具（statsfl / fps_monitor …）做的事十幾行 stdlib 即可取代且 `FrameTiming` 資料更完整（分得出 build 慢還是 raster 慢），但受制於上述 debug build 問題，取代了也沒用。**崩潰捕捉本 kit 已自有**（`uncaught_error_handler.dart` 三路 chain 且保留舊 handler），不需要 armor 這類「優雅恢復」——debug 階段要的是崩潰立刻現形，不是被吞掉。

2. **跨 session 持久化 / 本機落盤的 crash history**
   - *拒絕*：把 buffer 定期寫 SQLite/Hive、重啟後還原——聽起來很美，但引入磁碟 IO、序列化版本相容、隱私（log 含敏感資料落盤）三重複雜度與風險。**排查的證據用 #3 的「一鍵匯出」帶走即可**，不需要工具自己當資料庫。違反「砍掉一半再砍一半」。**砍**。

3. **完整 HAR timing waterfall（DNS/TLS/TTFB 分段）**
   - *拒絕*：Dio 在多數版本拿不到可靠的分段 timing，硬湊出來的瀑布圖是**假精度**，反而誤導排查。保留 #4 的 total duration + timeout 判斷已足夠。匯出走標準 JSON 即可，不追 HAR 的完整 timings 物件。**砍**（HAR 匯出本身可選保留，但不偽造 timing）。

4. **API Mocking / 動態回應改寫**
   - *拒絕*：同上一份 brainstorm 的判斷——在 debug overlay 裡注入 mock 規則會讓工具代碼翻倍，且極易因 debug 庫 bug 中斷宿主的正式網路流。**嚴重違反「Never break userspace」**。交給外部 proxy。**砍**。

5. **B 級 WebView 除錯器（breakpoint / step / DOM inspector / profiler / JS REPL）**
   - *拒絕*：breakpoint/profiler 需要 CDP，inline 模擬是假貨；DOM inspector 工程量爆炸且 Eruda 頁內已有（#10 Phase 0 食譜即覆蓋此需求）；JS REPL（從 dashboard 對 WebView 執行任意 JS）技術上可行但那是「操控」不是「觀測」，跨越產品邊界且有安全面問題。README 直接指路 chrome://inspect 與 Safari Inspector。**砍**（REPL 若未來需求真實再議）。

6. **WebView 專屬 tab / 第五個 TimelineSource**
   - *拒絕*：WebView log 就是 log、fetch 就是 network。加 enum、開新 tab 是為不存在的區別打補丁，會讓 filter / 報告 / UI 全鏈路長出特殊情況。provenance 用 `NetworkOrigin` + `LogEntry.data` 標記足矣。**砍**。

7. **直接相依 webview 套件（提供包裝好的 InspectorWebView widget）**
   - *拒絕*：綁死 `webview_flutter` 或 `flutter_inappwebview` 其一，就把另一半使用者關在門外（inappwebview_inspector 正是此坑）；兩個都支援則相依翻倍、版本矩陣地獄。host-injection 模式已驗證兩次（`DiagnosticInfoSource`、`DatabaseBrowserSource`），沒有理由背棄。**砍**。同理**跨 iframe / Service Worker 橋接**——複雜度與受眾完全不成比例，**砍**。

*（以下隨第四部分新增 · 2026-07-23）*

8. **State 檢查器 / Widget Tree 瀏覽器**
   - *拒絕*：DevTools 已有且做得更好。in-app 重造需要反射或大量 Element tree walk，代價高且永遠是 DevTools 的子集。**砍**。

9. **自動化測試整合**
   - *拒絕*：超出 debug inspector 邊界。inspector 的使用者是人（開發者/QA），不是 CI。如果測試需要讀 inspector 資料，那是消費端的事，不該改變 inspector 的設計重心。**砍**。

---

## 📅 下一步實作路徑（2026-07-24 重排 · 鏈推斷優先）

> **重排理由（2026-07-24）**：原四階段 Phase Plan 以「先滅紅燈」為排序原則，把 §D1 ConsoleTab 搜尋/過濾放在最高優先。重新檢視後判定這個定性有問題——
>
> **排查的核心動作是「鏈推斷」（不知道要找什麼，要看事情怎麼演變成這樣），不是「點查詢」（已知道要找什麼，把它撈出來）。** 過濾服務的是後者，而且它**主動切斷因果鏈**：搜到 3 筆 timeout，前後的 API 呼叫與路由跳轉全被濾掉。§D1 標的 🔴 紅燈紅在「ConsoleTab 缺 NetworkTab 有的東西」的**功能對稱性**，不是**排查能力**。
>
> 新排序原則：**往時間軸加資訊 → 標記已有資訊 → 檢索既有資訊 → 打磨**。判準是「這一項有沒有讓時間軸上出現原本拿不到的資訊」——有的優先，因為那才是推斷因果的原料。

### Tier 1 · 往時間軸加資訊（真正服務因果推斷）

| 項目 | 內容 | 寫入路徑 | Effort | 狀態 |
|------|------|----------|:---:|:---:|
| **§P13** App 生命週期標記 | `WidgetsBindingObserver` → 各狀態轉一筆 info log（尾巴附 top-most page） | `lifecycle_handler.dart`（新）+ `flutter_inspector.dart` | low | ✅ PR #100 |

> **本層唯一項目已完成**（PR #100，2026-07-24 合入 main）。判準是「有沒有讓時間軸出現原本拿不到的資訊」——§P13 補上「當時 app 在前景還背景」+「切換發生在哪一頁」兩個原本無從得知的維度，是真正的新資訊。實作另深化了 `detach()` 的 observer teardown 與 top-page 尾巴（見 §P13 實作現況）。**Tier 1 清空，下一步進 Tier 2。**
>
> ~~§P2 錯誤上下文快照~~ 原列於本層，已於 2026-07-24 否決（見 §P2）：它快照的導航/網路事件**本來就在 timeline 上**，是把已有資訊換位置而非新增維度；且「挑兩個維度釘在 error 旁」預設了因果單線，與「錯誤常是綜合因素」的實情衝突。

### Tier 2 · 標記已有資訊（低成本、有感）

| 項目 | 內容 | 寫入路徑 | Effort | 狀態 |
|------|------|----------|:---:|:---:|
| **§P7** Error 高亮強化 | error 行淡紅底色 | `console_tab.dart` 的 `_LogEntryRow` / `_NetworkEntryRow` | trivial | ✅ PR #101 |
| ~~**§P11**~~ → **§P1** 錯誤爆發偵測 | ~~先重構通知 channel~~（✅ 已隨 §P24 完成），再接 error 計數 + 告警 | `flutter_inspector.dart` + `dashboard_modal.dart` | ~~low +~~ low | ⬜ 下一順位（前提已就緒） |
| **§P6** Dashboard Badge | tab 的 error count badge | `dashboard_modal.dart` | low | ✅ `b4846ea` |
| **§D6** Inspector 自身頁面污染 NavigatorTab | 收斂 inspector 內部 push 的識別（**方案 B**），讓 detail view 不進使用者導航軌跡 | 新增 helper + `navigator_observer.dart` + 4 處 dashboard 呼叫端 | low | ✅ 已完成 |

> **§D6 是既有 bug 而非新功能**，排在 Tier 2 的理由是它侵蝕的是**既有功能的可信度**（NavigatorTab 的資料正確性），不是錦上添花；且污染量與排查強度成正比——越認真追查越髒。已於 2026-07-26 用 probe test 實測確認 `NetworkDetailView` 會進入 `navigatorInspector.entries`（見 §D6）。
>
> **§P7 已完成**（PR #101，2026-07-25 合入 main）。實際成本確如預估的 trivial，但 diff 主體不在高亮本身——動工才發現「網路請求是否失敗」的判定在三處各手寫一份且已漂移，收斂成 `NetworkEntry.isFailed` 並一併修掉 errorType-only 失敗不產生錯誤群組的既有 bug（見 §P7 實作現況）。**這是本輪的一條經驗**：trivial 項目的成本估在「要寫的程式碼」上通常準，但會低估「動到的既有判定有多少份」。
>
> **📝 更新（2026-09-06）**：**§P11 已隨 §P24 Crash 系統通知完成**（Issue #156），下句的「§P11 必須排在 §P1 之前」已成既成事實——通知 id/channel 已參數化，**§P1 動工時前提已就緒**，Tier 2 剩餘工作僅 §P1 本身。
>
> ~~**下一步：§P11 → §P1。§P11 必須排在 §P1 之前**，否則會被迫在 `NetworkNotifier` 內長 if/else 區分「網路摘要」與「錯誤爆發」兩種通知語意。~~ §P14 若要做，併入 §P7 的高亮機制，不單獨排程——§P7 已完成，該機制（`_kErrorRowTint` + 逐 Row 的 `tileColor` 判斷）現已存在，屆時只需多認一種 `data` flag。

### Tier 3 · 檢索既有資訊（原 Phase 1，已降級）

| 項目 | 內容 | 寫入路徑 | Effort |
|------|------|----------|:---:|
| ~~**§D1 + §P5**（**合併**）~~ | 過濾 + 點擊清過濾並捲回主時間軸 — ✅ 已完成（PR #128 · 2026-08-14）。`console_utils.dart` 由「可選」變為實際新增；入口依合併決策改以點擊過濾結果觸發，未採用 §P5 原構想的 FAB | `console_tab.dart` + `console_utils.dart` | med |
| ~~**§P3** Timeline 書籤~~ | 長按標記 + bookmark-only 過濾 + 報告前綴 — ✅ 已完成（PR #115） | `console_tab.dart` + `diagnostic_report.dart` | low |

> **§D1 與 §P5 應合併為一項**，不該分居原 Phase 1 與 Phase 4：單獨的過濾切斷前後文，單獨的 §P5 只能跳最新 error；合起來才完整——搜到 → 點擊 → 清過濾並捲到該位置 → 站回完整時間軸看前後。這也是 §D3 ±5s 側欄想解決卻解錯的問題（見 §D1 重新定性 ③）。
>
> ~~§D3 ±5s 同時段側欄~~ 已於 2026-07-24 否決（見 §D3）。**注意**：§D3 原記「由 §P2 錯誤上下文快照取代」，但 §P2 隨後亦被否決——兩者同病（都想在 error 旁另闢一塊「相關資訊」，一個用固定時間窗猜、一個用固定維度猜）。該需求的實際覆蓋者是**既有的 `mergedTimeline()`**：完整時間軸不預先挑什麼相關，把所有維度攤平讓排查者自己判斷。

### Tier 4 · 打磨（依回饋排程，寫入路徑互不重疊）

| 項目 | 內容 | Effort | 狀態 |
|------|------|:---:|:---:|
| ~~**§P8** 慢請求標記~~ | NetworkTab 的 duration 閾值 + 🐢 標記 — ✅ 已完成（PR #111） | trivial | ✅ |
| **§P4** 快速複製 Diagnostic Snippet | NetworkDetailView 一鍵 cURL + error payload | trivial~low | ⬜ |
| **§P16** 生態日誌適配器 | `logger` (LogOutput) / `talker` (Observer) / `logging` 純介面轉譯適配器與 README 接線食譜 | trivial~low | ⬜ |
| **§P18** 輕量網路效能統計條 | NetworkTab 頂部純計算 Stats Bar (Total / Fail / Avg Latency / Bytes) | low | ⬜ |
| **§P25** ImageCache 水位計 | Storage tab 內常駐顯示 `currentSizeBytes`/`maximumSizeBytes`/張數，**打開時才讀不輪詢**；不開新 Performance tab | low | ⬜ |
| **§P19** StackTrace 非同步鏈正規化 | 框架噪聲折疊 (`[... N frames of framework internals]`) 與非同步中斷因果鏈還原 | low~med | ✅ |
| **§D4** DatabaseTab 搜尋/過濾 | 搜尋 + operation FilterChip | low~med | ⬜ |
| **§P17** 原生折疊式 JSON 樹狀檢視器 | `JsonTreeViewer` 遞迴節點展開、語法高亮、路徑複製與搜尋 | med | ⬜ |
| **§P9** Diagnostic Report JSON | 結構化 JSON 匯出格式 | med | ⬜ |
| ~~**§P15** 鍵值儲存檢視器（KV Browser）~~ | `KeyValueBrowserSource` 介面 + **獨立 Storage tab**（非併入 Database Tab）+ 讀寫操作 + README 範例 — ✅ 已完成（PR #137） | medium | ✅ |
| ~~**§P10** Rebuild 異常偵測~~ | ~~全清單唯一需逐 widget 接線，非 app層級 flag~~ | ~~med~~ | ❌ |

> **§P8 已完成**（PR #111 / Issue #110，v1.9.0 週期）——閾值改為 `FlutterInspector.slowRequestThreshold`
> 可設定（預設 2s）並顯示於 UI，且 NetworkTab 與 ConsoleTab 混合時間軸**兩處都標**。
>
> **2026-08-28 生態評估新增**：納入 **§P16 生態適配器**（trivial~low）、**§P18 輕量網路統計條**（low）、**§P19 堆疊正規化**（low~med）與 **§P17 原生折疊 JSON 檢視器**（med）。四者皆為零新相依、高排查 ROI 之打磨項目。本層活躍待辦現為 6 項（§P4 / §P16 / §P18 / §D4 / §P17 / §P9）——**§P19 已於 PR #149 完成**（2026-09-01 實查確認 `log_formatters.dart:95` `normalizeStackTrace()` 與 `log_detail_view.dart:94` 的 concise/raw 切換皆已就位），故不計入。
>
> **§P4 的 effort 下修為 trivial~low**（2026-08-06 實查）：`buildCurl` / `buildPlainText` / `shareText`
> 皆已存在且已接 redaction 旗標，`PopupMenuButton<_ShareAction>` 選單也已在 detail view 就位——
> 本項實為「既有選單多加一個 enum 值 + 一個組裝 formatter」，非從零新建 UI。
>
> **本層排序已依 effort 升序編排**。各項寫入路徑互不重疊，可任意挑選或並行。

### 不排程

| 項目 | 理由 |
|------|------|
| ~~§D5 Redaction 涵蓋缺口~~ | debug 工具應以資訊完整為先，遮罩是排查絆腳石；既有實作保留原樣 |
| ~~§P2 錯誤上下文快照~~ | 快照的事件本來就在 timeline 上（換位置非新增維度）；推導堆疊會失準卻被當事實；**預先挑兩個維度違背「錯誤常是綜合因素」**——需求由 `mergedTimeline()` 覆蓋 |
| ~~§P14 `inspector.mark()`~~ | 與 `log()` 無功能差異，是渲染差異非資訊差異；併入 §P7 或用 emoji 約定取代 |
| ~~§P12 離線/斷網標記~~ | 需 `connectivity_plus` 新相依，`DioExceptionType.connectionError` 已覆蓋多數情境；改寫 README 食譜 |
| ~~§D3 ±5s 側欄~~ | 固定時間窗與「找因果」目標不匹配，由 §P2 取代 |

---

> **收尾補記（2026-08-06 實查校正）**：Tier 4 的 **§P8 慢請求標記實際已於 PR #111 完成**，
> 文件此前仍列為待辦——本層由 5 項降為 4 項（§P4 / §D4 / §P9 / ~~§P10~~）。同時查明 §P4 的既有
> 可重用零件比原估計完整（`buildCurl` / `buildPlainText` / `shareText` 皆已接 redaction、
> `_ShareAction` 選單已存在），effort 下修為 trivial~low，成為本層最低成本入口。
> **這是同一份文件第三次出現「標為待辦、實際已完成」**（§D6 於 2026-07-27、§P8 於 2026-08-06、§P19 於 2026-09-01 查核發現）——
> 「每次 release 後回頭跑一次 Tier 表實查核對」的建議前兩次都沒被執行，**因此不再只是建議**：狀態欄以實查為準，文件與 codebase 衝突時一律信 codebase。第三次漂移同時暴露另一個癥狀——本節標題的版本號曾停在 v1.9.0，而 pubspec 實為 v2.4.0，說明漂移不限於 Tier 表。
>
> **收尾建議（2026-07-25 二次更新）**：排查鏈的基礎建設已近完備（10 項原始功能中 9 項完成）。**Tier 1（§P13）已於 PR #100 完成**——真正往 timeline 加上原本拿不到的維度（前景/背景 + 切換頁面），且動工前逐項實查、無隱藏成本坑到。**Tier 2 的 §P7 已於 PR #101 完成**（error 行淡紅底，只染 error 不染 warning）。**下一步：§P11 → §P1 錯誤爆發偵測**（綁定排程，§P11 先行）——§P6 Dashboard Badge 已於 `b4846ea`（2026-08-07）完成，**Tier 2 僅剩此一項**。原被列為最高優先的 §D1 仍在 Tier 3 並與 §P5 合併，§P2 整項否決，理由見各節。
>
> **📝 更新（2026-08-14）**：上句的「§D1 仍在 Tier 3」已過時——**§D1 + §P5 合併項已於 PR #128 完成**，Tier 3 因此清空。Tier 2 的 §P11 → §P1 仍為下一步，未受本次影響。
>
> **§P7 帶出的一條估計偏差**：trivial 項目的 effort 估在「要寫的程式碼」上是準的（高亮本體只有兩行 `tileColor`），但**低估了「會動到幾份既有判定」**——實作時發現「網路請求是否失敗」在三個檔案各手寫一份且已漂移各漏一種失敗類型，收斂它才是 diff 的主體，並順帶修掉一個靜默的既有 bug（errorType-only 的傳輸失敗不產生錯誤群組卡片）。文件其餘標為 trivial/low 的項目，建議動工前先 grep 一次「這個判斷在幾個地方被重寫過」，那才是真實成本所在。
>
> ⚠️ **本段是 PR #101 動工當下的歷史狀況，非現存問題**（2026-08-06 實查確認）。該次收斂已完成：單一判定來源為 `network_entry.dart:109` 的 `NetworkEntry.isFailed`，四個消費端（`network_tab.dart:51`、`console_tab.dart:259`、`diagnostic_report.dart:209`、`network_utils.dart:184`）全數走它，`lib/` 內無殘留的手寫失敗判定。（`theme_color.dart:17` 的 `>= 400` 是 status code 配色分級、`network_utils.dart:56` 的 `>= 400 && < 500` 是 4xx/5xx 錯誤分組，皆非失敗判定，勿誤認為漏網。）**引用本段教訓時請連同本註記一起讀**，別把已修好的案例當待辦。
>
> **本輪的一條共通判準**（§D3 / §P2 均據此否決）：**不要替排查者預先決定「什麼跟這個錯誤相關」**。固定時間窗（§D3）、固定維度（§P2）都是工具在猜，而真實錯誤常是綜合因素——完整時間軸把所有維度攤平、由人邊看邊判斷，才是對的形狀。凡是提案想在 error 旁另闢一塊「相關資訊」的，先用這條判準檢驗。
>
> **本次重排同時修正了三處與實際 codebase 不符的估計**：§D1 的 `InspectorSearchBar`（實為私有 `_SearchBar`）與 `entriesAtLevel()`（回傳型別接不上混合流）、§P2 的 `NavigatorStackResolver.currentStack`（不存在）。文件其餘「重用既有零件」的宣稱建議在動工前逐項實查，勿直接採信。
>
> **§P10 已取消（2026-08-14 規格審查）**：功能規格撰寫完成後判定價值太窄——只在「開發者已懷疑
> 特定 widget 有 rebuild bug」時才有用，無法主動偵測問題（Flutter 無全域 rebuild 回呼）。
> opt-in per-widget 的接線成本（每個可疑 widget 手動加 mixin + 呼叫 `guardRebuild()`）與收益
> 不成比例。**Tier 4 由 4 項降為 3 項後，因 §P15（KV Browser）新增又回到 4 項（§P4 / §P15 / §D4 / §P9）**。
> **2026-08-22 更新**：§P15 已於 PR #137 完成（實作為獨立 Storage tab），本層剩 3 項（§P4 / §D4 / §P9）。
