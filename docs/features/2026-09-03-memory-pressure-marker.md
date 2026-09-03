# 功能規格：記憶體壓力事件（§P21）

- **日期**：2026-09-03
- **來源**：`docs/brainstorm/2026-09-01-features-brainstorm.md` §P21（第七部分 · Google Play 品質要求 × 執行時期排查）
- **Tier**：Tier 4 打磨 · 第七部分優先序建議第 1 順位（暖身首選）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位排查「App 用著用著就被系統殺掉」的開發者／QA，
> 我希望**記憶體壓力事件出現在混合時間軸上**，
> 這樣我就能看出壓力是「在載入那張大圖之後」「在那支回傳巨大 JSON 的 API 之後」才密集出現，
> 而不是只知道 App 消失了、卻無從得知前因。

### 為什麼這件事現在做

Google Play 2026 Q3「Elevating app quality」把 Memory usage（RSS+Swap / Bitmap）列為 **Feb 2027 強制**門檻。
但真正的 RSS 數值需要 platform channel，粗糙且跨平台不一致——
**`didHaveMemoryPressure()` 是 Dart 層唯一拿得到的 OOM/LMK 前導信號**，
且它天然就是「帶時間戳的離散事件」，正好是本套件混合時間軸要的因果原料。

### 為什麼它不會重蹈 §P20 的覆轍

§P20（掉幀維度）目前卡在「待裁決」，死因是 debug build 效能失真導致誤報。
**本項不受該問題影響**——記憶體壓力是 **OS 主動送來的事件**，
不是套件自己拿 duration 跟門檻比對出來的判定。沒有門檻，就沒有誤判空間。

---

## 2. 範圍邊界

### ✅ 做

- `LifecycleHandler` 多覆寫一個 `didHaveMemoryPressure()` callback
- 事件寫入既有 log 維度，`LogLevel.warning`
- 沿用既有 `topPageLabel` 尾巴（記錄壓力發生在哪一頁）
- README 補充平台覆蓋度說明
- 對應單元測試

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 新增 `captureMemoryPressure` 旗標 | **已裁決併入既有 `captureLifecycleEvents`**（見 §3） |
| 新增 `MemoryEntry` / `MemoryInspector` / `RingBuffer` | 事件只有一個時間點，無結構化欄位可存；新增第五個 `TimelineSource` 是 Anti-Feature #6 |
| 讀取實際 RSS / 記憶體用量數值 | 需 platform channel，粗糙且跨平台不一致（文件已劃為 app 內不可觀測） |
| 記憶體洩漏偵測 / profiling | Anti-Feature #1 明確否決，交由官方 DevTools |
| 事前加節流（throttle） | 尚未實測觸發頻率，先加是解決想像中的問題。實測到洗版才接既有 `AlertThrottler` |

---

## 3. 已裁決的設計決策

**公開 API：併入既有 `captureLifecycleEvents`，不新增旗標。**（2026-09-03 使用者拍板）

理由是資料結構層面的——兩者是**同一個 `WidgetsBindingObserver` 的兩個 callback**，
共用同一套 `attach()` / `detach()` / `_attached` 生命週期管理。

獨立旗標會製造一個真正的特殊情況：**旗標與 observer 不再一對一**，
`attach()` 得判斷「至少一個為真」、`detach()` 得判斷「兩個都關」、
每個 callback 內再各自檢查一次自己的旗標——為了一個 bool 長出四處判斷。

**已知代價（可接受）**：既有使用者開啟 `captureLifecycleEvents` 後會**多收到**記憶體壓力 log。
這不是破壞 userspace——無 API 消失、無簽章變更、無行為反轉，
只是同一維度多一種事件，性質等同 §P13 當初為生命週期訊息加上 top-page 尾巴。

---

## 4. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | `captureLifecycleEvents: true` 時，記憶體壓力事件產生一筆 log | 單元測試：`WidgetsBinding.instance.handleMemoryPressure()` → 斷言 log 一筆 |
| 2 | 該 log 的 level 為 `LogLevel.warning`（非 `info`） | 單元測試斷言 level |
| 3 | 訊息含可辨識文字，並在有 top page 時附上「· page」尾巴 | 單元測試斷言訊息內容 |
| 4 | `topPageLabel` 回傳 null／空字串時，訊息不含尾巴、不編造 | 單元測試（對齊既有 `didChangeAppLifecycleState` 的同型 case） |
| 5 | 未 attach 時不產生 log | 單元測試 |
| 6 | `detach()` 後不再產生 log | 單元測試 |
| 7 | `topPageLabel` 拋錯時不向宿主傳播、不產生半套 log | 單元測試 |
| 8 | 事件出現在 ConsoleTab，並被既有 warning/error 過濾與高亮機制正確處理 | 既有機制認 `LogLevel`，隨測試通過即成立 |
| 9 | `flutter test` 全綠（既有 554 tests + 新增） | 指令執行 |
| 10 | `flutter analyze lib/ test/` 不超出既有 7 個 info 基準 | 指令執行 |

---

## 5. 實查發現（影響實作，非臆測）

以下皆為本次規格階段實地查證，非文件轉述：

1. **重用前提成立**：`lifecycle_handler.dart:11` 確為 `class LifecycleHandler with WidgetsBindingObserver`，
   `:49` 僅覆寫 `didChangeAppLifecycleState` 一個 callback。多覆寫一個即可。

2. **接線零改動**：`flutter_inspector.dart:237` 建構 `LifecycleHandler(onLog: log, topPageLabel: _currentTopPageLabel)`、
   `:241` 依旗標 `attach()`、`:295` `detach()` 皆已就位。**本項不需改動接線**，
   僅需更新 `captureLifecycleEvents` 的 doc comment 說明它現在也涵蓋記憶體壓力。

3. **`activeRoute` 已自動帶上**：`FlutterInspector.log` 於 `:311` 自行呼叫 `_currentTopPageLabel()` 填入 `activeRoute` 欄位。
   `topPageLabel` 尾巴是**訊息文字**的一部分（給人讀），與 `activeRoute` 欄位（給機器用）兩者並存，對齊既有生命週期事件的作法。

4. **🔴 錯誤傳播行為隨 SDK 版本而異（2026-09-03 PR review 後修正，見下方勘誤）**：
   `handleMemoryPressure()` 的 per-observer try-catch 是 **Flutter 3.44.0 才加入的**。
   本套件 `pubspec.yaml` 宣告 `flutter: ">=3.10.0"`，
   **在 3.10.0 ～ 3.41.x（即絕大多數支援版本）該迴圈沒有 per-observer try-catch**，
   與 `didChangeAppLifecycleState` 完全同型——例外逃逸會中斷廣播，
   排在本 handler 之後註冊的 observer 全部收不到。

   **結論**：本項的 try-catch **是真正的保護**（不只是避免汙染 `FlutterError`），
   且測試**應該**沿用既有 `_HostObserver` 手法——那才是在 SDK 下限上唯一有鑑別力的斷言。
   同時保留 `FlutterError` 斷言，因為在 3.44.0+ 上 `hostCalled` 會恆為 true、失去鑑別力。
   兩個斷言並存，整個支援範圍內才都驗得到 guard。

   > **勘誤**：本節原記載「`handleMemoryPressure()` 每個 observer 各自包 try-catch，
   > 故 `_HostObserver` 手法無效」。該結論**只在 Flutter 3.44.0+ 成立**，
   > 是我只查了本機 SDK（3.44.1）就下的定論，未對照 `pubspec.yaml` 宣告的版本下限。
   > 由 PR #155 的 CodeRabbit review 指出，經逐版查證 upstream `binding.dart` 確認：
   > 3.10.0 / 3.16 / 3.19 / 3.22 / 3.24 / 3.27 / 3.29 / 3.32 / 3.35 / 3.38 / 3.41 皆無，
   > 3.44.0 起才有。**教訓：驗證 SDK 行為時，基準是 `pubspec.yaml` 的版本下限，不是本機裝的版本。**

5. **測試觸發點**：`WidgetsBinding.instance.handleMemoryPressure()` 為公開方法，可直接於測試呼叫，
   不需要 platform channel mock。

6. **平台覆蓋度**（README 需說明，避免使用者誤判為套件故障）：
   Android 經 `onTrimMemory` 轉發、iOS 經 `didReceiveMemoryWarning`、**Web 實質不會觸發**。

---

## 6. 影響範圍

| 檔案 | 動作 |
|:---|:---|
| `lib/src/core/lifecycle_handler.dart` | 新增 `didHaveMemoryPressure()` 覆寫（約 12 行） |
| `lib/src/core/flutter_inspector.dart` | **僅** doc comment 補述（`captureLifecycleEvents` 涵蓋範圍） |
| `test/core/lifecycle_handler_test.dart` | 新增測試 case（對應驗收條件 1–7） |
| `README.md` | 平台覆蓋度說明 |
| `CHANGELOG.md` | 版本條目 |

**不動**：`inspector_registry.dart`、`ring_buffer.dart`、任何 UI 檔、任何 model 檔。

---

## 7. 風險

| 風險 | 等級 | 處置 |
|:---|:---:|:---|
| 觸發頻率過高洗版時間軸 | 低 | 不預先節流。實測到才接既有 `AlertThrottler`（已支援建構式注入） |
| 既有使用者多收到 log | 極低 | 已於 §3 評估為非破壞性，同維度多一種事件 |
| 誤報 | 無 | OS 主動送出的事件，無門檻判定，不存在 §P20 的 debug build 誤報問題 |
