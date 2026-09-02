# 實作計畫：記憶體壓力事件（§P21）

- **日期**：2026-09-03
- **規格**：`docs/features/2026-09-03-memory-pressure-marker.md`
- **Effort**：trivial

---

## 1. 資料結構

**不新增任何資料結構。** 這是本項最重要的設計判斷。

事件的完整資訊量是「一個時間點 + 發生在哪一頁」，沒有結構化欄位可存。
既有 `LogEntry` 已能承載（`message` + `level` + `activeRoute`），
新增 `MemoryEntry` / `MemoryInspector` / 第五個 `TimelineSource` 會讓
過濾、報告、UI 全鏈路長出特殊情況，卻換不到任何新資訊——正是 Anti-Feature #6 的形狀。

資料流沿用既有路徑，一條線到底：

```
OS (onTrimMemory / didReceiveMemoryWarning)
  → WidgetsBinding.handleMemoryPressure()
  → LifecycleHandler.didHaveMemoryPressure()      ← 本次唯一新增的節點
  → onLog（建構時注入的 FlutterInspector.log）
  → LogEntry（activeRoute 由 log() 自行填入）
  → RingBuffer.add → onMutate → revision.value++  ← 既有唯一變更通道
  → ConsoleTab 重繪
```

---

## 2. 任務拆分

**單一任務，序列執行。** 改動集中在一個檔案，無並行空間。

### Task 1 · `didHaveMemoryPressure()` + 測試 + 文件

**寫入路徑**：
- `lib/src/core/lifecycle_handler.dart`（實作）
- `test/core/lifecycle_handler_test.dart`（測試）
- `lib/src/core/flutter_inspector.dart`（**僅** doc comment）
- `README.md`、`CHANGELOG.md`（文件）

#### 1a. 實作

於 `lifecycle_handler.dart` 的 `didChangeAppLifecycleState` 之後新增：

```dart
  @override
  void didHaveMemoryPressure() {
    try {
      final page = topPageLabel?.call();
      final suffix = (page == null || page.isEmpty) ? '' : ' · $page';
      onLog('Memory pressure$suffix', level: LogLevel.warning);
    } catch (e, s) {
      debugPrintStack(
        stackTrace: s,
        label: 'inspector memory pressure log failed: $e',
      );
    }
  }
```

四個決定，全部對齊既有那支：

| 決定 | 理由 |
|:---|:---|
| `LogLevel.warning`（非 `info`） | 這是 OOM/LMK 前導信號，不是狀態轉換。要能被既有 warning/error 過濾與高亮機制撈起來，否則插進時間軸卻沉在資訊流裡 |
| 沿用 `topPageLabel` 尾巴 | 「壓力發生在哪一頁」與 §P13 的「切換發生在哪一頁」同型，零額外成本 |
| 保留 try-catch | `topPageLabel` 是 host 注入的 callback，會拋。雖然 binding 這條路徑會接住（見下方 1b），但不該讓 host 的錯誤汙染 `FlutterError`，且與既有 callback 寫法一致 |
| 類別 doc comment 同步更新 | 現有註解寫「Records app lifecycle transitions」，需擴及記憶體壓力 |

#### 1b. 測試（🔴 不可照抄既有 guard 測試）

**規格 §5.4 的發現**：`binding.dart:1372` 的 `handleMemoryPressure()`
**每個 observer 各自包 try-catch**（`:1376-1387`），
而 `didChangeAppLifecycleState` 的廣播迴圈**沒有**。

既有測試 `guard: onLog throws does not propagate` 靠「例外中斷廣播迴圈、
後續 `_HostObserver` 收不到」來證明 guard 存在。
**該手法在本路徑上驗不到東西**——即使拿掉 try-catch，binding 也會接住，
`_HostObserver` 照樣被呼叫，測試恆綠但零驗證力。

**正確寫法**：直接斷言「拋錯時不產生 log、且不向外拋出」。

新增的 case（對應驗收條件 1–7）：

| # | 測試名 | 斷言 |
|:---:|:---|:---|
| 1 | `memory pressure produces one warning log` | callCount==1、level==`warning`、訊息含 `Memory pressure` |
| 2 | `memory pressure: topPageLabel appended after " · "` | 訊息 == `Memory pressure · HomePage (/home)` |
| 3 | `memory pressure: null and empty label omit the suffix` | 訊息 == `Memory pressure`（兩種輸入） |
| 4 | `memory pressure: not attached produces no log` | callCount==0 |
| 5 | `memory pressure: no log after detach` | detach 後再觸發，callCount 不變 |
| 6 | `memory pressure: throwing topPageLabel is caught` | `returnsNormally` 且 logged==false（**不使用 `_HostObserver`**） |

觸發方式：`WidgetsBinding.instance.handleMemoryPressure()`（公開方法，無需 mock）。

沿用既有測試檔的 `handler` + `tearDown` 慣例，避免 observer 洩漏到其他 case。

#### 1c. 文件

- `flutter_inspector.dart` 的 `captureLifecycleEvents` doc comment：
  補一句它現在也記錄記憶體壓力事件。**不改任何程式碼**。
- `README.md`：平台覆蓋度——Android 經 `onTrimMemory`、iOS 經 `didReceiveMemoryWarning`、
  **Web 實質不會觸發**（避免使用者誤判為套件故障）。
- `CHANGELOG.md`：Unreleased 條目。

---

## 3. 驗證

```bash
flutter test test/core/lifecycle_handler_test.dart   # 單檔快驗
flutter test                                        # 全套（既有 554 + 新增）
flutter analyze lib/ test/                          # 不得超出既有 7 個 info 基準
```

**版本號不動**——本計畫不含發版。發版走 `gen-update-publish-info`（4 處同步）。

---

## 4. 刻意不做

| 項目 | 理由 |
|:---|:---|
| `AlertThrottler` 節流 | 未實測觸發頻率，預先加是解決想像中的問題。實測洗版才接（已支援建構式注入） |
| 抽出 `_logWithPageSuffix()` 共用 helper | 兩處各 5 行、字面不同（`App lifecycle: ${state.name}` vs `Memory pressure`）。抽共用要嘛傳格式參數要嘛傳前綴字串，都比重複兩行更難讀。**第三次出現才抽** |
| `captureMemoryPressure` 獨立旗標 | 已裁決併入（規格 §3） |
| 新增 model／inspector／UI 檔 | 見 §1 |

---

## 5. 風險與回滾

改動落在單一 callback，**不觸碰任何既有程式碼路徑**——
既有 `didChangeAppLifecycleState`、`attach`/`detach`、UI、model 全數不動。

最壞情況是新 callback 行為不如預期，刪掉該方法即完全回到現狀，無殘留。
