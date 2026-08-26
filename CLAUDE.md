# flutter_inspector_kit

App 內除錯檢視工具（Flutter Package）：把 log / network / navigator / database 四種來源收在單一 API 後，攤平成一條混合時間軸。

**核心設計哲學**：排查靠「鏈推斷」（看事件演變脈絡），而非「點查詢」。任何切斷前後文的設計皆不被接受（如已否決的 ±5s 側欄與錯誤上下文快照）。

## 1. 架構文件導覽

| 主題 | 參照路徑 | 核心內容 |
|:---|:---|:---|
| 系統架構 | `docs/architecture/overview.md` | 分層、設計原則、WeakReference、錯誤鉤子、WebView 防護 |
| 檔案索引 | `docs/architecture/file-reference.md` | 模組結構與檔案職責（若與程式碼衝突以程式碼為準） |
| 資料流向 | `docs/architecture/data-flow.md` | 8 條主要流程時序圖（含 `mergedTimeline` 歸併機制） |

## 2. 核心不變式與致命陷阱 (Critical Invariants)

以下為本專案不可違背的關鍵設計約束，修改前必須理解：

1. **`RingBuffer.onMutate` → `revision` 為唯一變更通道**
   - 4 個 buffer 的 `onMutate` 統一觸發 `InspectorRegistry._bump()`（`revision.value++`）。
   - UI 僅訂閱單一 `ValueListenable<int>`，禁止逐個 inspector 掛載 listener。
   - `onMutate` 內**嚴禁重入**（不可再次對同一 buffer 執行 `add`/`replace`/`clear`）。
   - `InspectorRegistry` 屬 App-scoped 長生命週期**不 dispose**；所有訂閱方（UI/Widget）**必須在 `dispose()` 中主動移除 listener**，否則必致記憶體洩漏。

2. **`mergedTimeline()` 回傳原始物件指標（禁止防禦性複製）**
   - 時間軸直接引用 buffer 內部 entry 物件，確保異步狀態（如 network pending → completed）自動反映最新值，**不存在第二份真相**。
   - 過濾邏輯必須在收集階段（決定是否讀取 buffer）完成，而非排序後過濾。

3. **緩衝型 (Inspector) vs 即時查詢型 (Browser Source) 嚴格分流**
   - **緩衝型**（`log`, `network`, `nav`, `db`）：事件寫入 `RingBuffer(500)`，進入時間軸，由套件固定內建。
   - **即時查詢型**（如 `Storage`、外部 DB）：呼叫時即時拉取，不產生時序事件，不進時間軸，由 Host 主動註冊。
   - `OperationLogSource` 為唯一特例：將緩衝型 `DatabaseInspector` 包裝為 `DatabaseBrowserSource`。

4. **條件匯出（Conditional Export）雙向簽章一致性**
   - `network_notifier.dart` 與 `share_text.dart` 透過條件匯出切換 `_io.dart` 與 `_web.dart`。
   - **修改任一側公開介面時，必須同步修改另一側的函式簽章**，否則 Web build 會崩潰且單元測試無法捕捉。

5. **Flutter Package 純淨性與依賴限制**
   - 本套件為輕量級除錯工具，核心禁止引入任何重量級狀態管理庫（如 BLoC、Riverpod、Provider），以原生效能元件（`ValueNotifier`、`StatefulWidget`）實作。

## 3. 指令集與驗證基準 (Commands & Baseline)

```bash
# 測試
flutter test                                  # 全套測試 (554 tests, ~15–20s)
flutter test test/ui/console_tab_test.dart    # 單檔測試

# 分析與程式碼格式化
flutter analyze lib/ test/                    # 靜態分析
make analyze_lint                             # dart analyze
make format                                   # dart format .
make fix                                      # dart fix --apply
./scripts/gen_test_coverage.sh                # 覆蓋率報告產生 (coverage + genhtml)
```

- **既有分析雜訊基準**：目前 `flutter analyze lib/ test/` 存在 **7 個既有 info**（6 個 `deprecated_member_use` 關於 `withOpacity` / `groupValue`，以及 1 個 `share_text_web.dart:15` 的 js interop 型別檢查）。**唯有超出這 7 個的新增 warning/info 才是本次改動引入的問題**。
- **無 CI 機制（本機嚴格驗證）**：Repo 未設置 `.github/` CI workflow，所有測試與靜態分析完全依賴開發者與 Agent 本機執行確認。
- **Makefile 死指令警告**：僅 `analyze_lint`、`format`、`fix` 可用；其餘如 `build_runner`、`launcher_icon`、`intl`、`analyze_custom`、`get` 等 target 缺少外部相依，禁止調用。
- **Demo 專案邊界**：`example/` 僅為手動示範沙盒（`cd example && flutter run`），其內部測試檔為預設樣板，不作為自動化測試驗證目標。

## 4. 發版規範：4 處版本號同步

發布新版本時，必須**同時更新以下 4 處版本號**（任何一處遺漏皆屬發版 Bug）：
1. `pubspec.yaml`
2. `README.md`
3. `CHANGELOG.md`
4. `lib/src/version.dart`（`FlutterInspector.version` 依賴此檔，漏改將導致診斷輸出錯誤版本）

## 5. 規範體系與邊界分工

- **`CLAUDE.md`**（本檔）：AI Agent 開發與對話之主要上下文，專注於專案架構不變式、踩坑防護與指令集。
- **`best_practices.md`**：專供 CodeRabbit / Qodo Merge 等 PR Review Bot 讀取之審查標準，**請勿與本檔合併或去重**。
- **`.agents/rules/`（或 `.claude/rules/`）**：細部程式碼風格（`flutter-styles.md`）、專家原則（`expert-rules.md`）與 RTK 規範。
- **開發流程**：標準開發與 Feature 推進請遵循 `.claude/skills/gen-dev-workflow`。

