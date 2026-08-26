# flutter_inspector_kit

App 內除錯檢視工具（Flutter package）：把 log / network / navigator / database
四種來源收在單一 API 後面，攤平成一條混合時間軸。

**設計主張**：排查靠「鏈推斷」（不知道要找什麼，看事情怎麼演變成這樣），不是
「點查詢」。任何會切斷前後文的設計都要先過這一關——這是否決 §D3（±5s 側欄）與
§P2（錯誤上下文快照）的理由，動 filter / timeline 前先讀。

## 架構文件（不要重寫，先讀）

| 想知道 | 讀 |
|:---|:---|
| 分層、設計原則、WeakReference/錯誤鉤子/WebView 防護 | `docs/architecture/overview.md` |
| 每個檔案是什麼、放哪 | `docs/architecture/file-reference.md` |
| 八條主要流程的時序圖（含 mergedTimeline 歸併） | `docs/architecture/data-flow.md` |

⚠️ 這些文件會漂移——曾出現 `file-reference.md` 寫死版號、實際版本早已前進數個 minor 的情況。
**以程式碼為準**，發現不符就順手修文件。

## 文件沒寫、但改壞會很痛的三件事

**1. `RingBuffer.onMutate` → `revision` 是唯一的變更通道**

四個 buffer 的 `onMutate` 全接到 `InspectorRegistry._bump()`，任一 buffer 變動就
`revision.value++`。UI 只訂閱這一個 `ValueListenable<int>`，不逐 inspector 掛 listener。

- `onMutate` 內**不可**再對同一 buffer `add`/`replace`/`clear`（重入仍在堆疊上的變更）
- `InspectorRegistry` **不 dispose**（app-scoped 長生命週期）→ **取消訂閱是訂閱方的責任**，
  加了 listener 就必須在 `dispose()` 移除，否則洩漏

**2. `mergedTimeline()` 回傳 buffer 內的原始指標，不複製**

所以 network entry 從 pending → completed，下次讀自然反映最新狀態，**不存在第二份真相**。
過濾發生在收集階段（`if` 決定要不要讀某個 buffer），不是排序階段。
要改成回傳 copy 之前，先想清楚會破壞這個不變式。

**3. 緩衝型 vs 即時查詢型，是兩種不同的東西**

| | 緩衝型（inspector） | 即時查詢型（browser source） |
|:---|:---|:---|
| 資料 | 過去發生的事件，進 RingBuffer(500) | 當下的實際內容，呼叫時才查 |
| 進時間軸 | ✅ | ❌ |
| 註冊 | 內建四個，固定 | host 自行 register |

`TimelineSource` 只有 `{log, network, nav, db}`——**Storage tab 沒有對應項**，
它是純即時查詢，不產生時序事件。`OperationLogSource` 是唯一的橋：把緩衝型的
`DatabaseInspector` 包成 `DatabaseBrowserSource`，所以 Database tab 的下拉選單裡
會同時出現「真實 DB」與「Operation log」兩種來源。

## 指令

```bash
flutter test                                  # 全套 554 個，15–20s
flutter test test/ui/console_tab_test.dart    # 單檔
flutter analyze lib/ test/
./scripts/gen_test_coverage.sh                # coverage + genhtml
make analyze_lint                             # dart analyze
make format                                   # dart format
make fix                                      # dart fix --apply
```

**既有雜訊**：`flutter analyze lib/ test/` 目前有 **7 個 info**——6 個
`deprecated_member_use`（`withOpacity` ×4、Radio 的 `groupValue`/`onChanged`）
加 1 個 `invalid_runtime_check_with_js_interop_types`（`share_text_web.dart:15`）。
看到這 7 個不用查，**多出來的才是你這次引入的**。

## 發版：版號在四處

`pubspec.yaml` → `README.md` → `CHANGELOG.md` → **`lib/src/version.dart`**

IMPORTANT: 第四處最常漏（v1.6.0 已中招一次）。`FlutterInspector.version` 讀的就是
`packageVersion`，漏改會讓診斷報告印出錯的版本號。

## 驗證只在本機，沒有 CI

repo **沒有 `.github/`**——沒有任何 workflow 會在 PR 上跑測試或 analyze。
上面那些指令是唯一的把關，**你不跑就沒人跑**。

⚠️ `Makefile` 有一批從樣板留下的死 target，相依根本不存在：
`build_runner`／`build_watch`／`build_clean`（無 `build_runner` 相依）、
`launcher_icon`（無 `flutter_launcher_icons`）、`intl`（無 `intl_utils`）、
`analyze_custom`（無 `custom_lint`）、`get`（跑 `pod install`，但 root 沒有 `ios/`）。
**只有 `analyze_lint`／`format`／`fix` 能用。**

`example/` 是手動 demo，不是測試目標——`example/test/widget_test.dart` 是
`flutter create` 的 counter 樣板、從未改過。要眼見為憑就 `cd example && flutter run`，
別指望在那裡跑 `flutter test` 會抓到東西。

## 其他

- 風格／流程規範在 `.claude/rules/`（自動載入，勿在此重複）
- 開發流程走 `.claude/skills/gen-dev-workflow`
- `best_practices.md` 與 `.claude/rules/flutter-styles.md` 內容高度重疊，但**受眾不同**：
  前者給 CodeRabbit／Qodo 的 PR bot 讀（`.coderabbit.yaml`、`.pr_agent.toml`），
  後者給 Claude Code 讀。**別合併或去重**
- `network_notifier.dart` 與 `share_text.dart` 用 conditional export 切 `_io`/`_web`，
  **改一邊要同步另一邊的簽章**，否則只有 web build 會炸、單測抓不到
