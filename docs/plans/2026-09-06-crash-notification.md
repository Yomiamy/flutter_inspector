# 實作計畫：Crash 系統通知

- **日期**：2026-09-06
- **規格**：`docs/features/2026-09-06-crash-notification.md`
- **總 Effort**：low（5 個任務）

---

## 1. 資料結構與設計決策

### 1.1 核心洞察：不要新增 Notifier 類別

**錯誤的作法**（會被退回）：新增 `CrashNotifier` 類別，複製一份 init／permission／
platform-guard 邏輯。那會產生兩份幾乎相同的平台初始化程式碼，且兩者都要維護
`_io`/`_web` 雙分支——四份檔案的維護成本，換一個「語意不同」的假需求。

**正解**：`NetworkNotifier` 內部的 `_notificationId` / `_channelId` 參數化後，
它已經是「一則可獨立定址的通知」的通用能力。crash 通知只是**用不同參數再建一個實例**。

```dart
// 網路摘要（既有，行為不變）
NetworkNotifier(onTap: _openNetworkFromNotification)   // 預設 network id/channel

// 崩潰告警（新增）
NetworkNotifier.crash(onTap: _openConsoleFromNotification)  // crash id/channel
```

> ⚠️ 類別名稱維持 `NetworkNotifier` 不改。改名是跨檔案的大 diff，
> 且 `_web`/`_io` 雙側 + 既有測試 + 匯出都要動，**與本功能無關**。
> 若日後覺得名稱不貼切，另開重構 issue。**本次不做**。

### 1.2 參數化的最小形式

只動兩個私有常數，改為 `final` 實例欄位，由具名建構式決定：

| 欄位 | network（既有值，不可改） | crash（新增） |
|:---|:---|:---|
| `_notificationId` | `0x6E657477`（'netw'） | `0x63726173`（'cras'） |
| `_channelId` | `flutter_inspector_network_v2` | `flutter_inspector_crash` |
| `_channelName` | `Network Inspector` | `Crash Inspector` |
| `ongoing` | `true`（常駐摘要） | `false`（離散事件，可滑掉） |

**`_legacyChannelId` 的刪除只屬於 network 實例** —— crash 實例不得重複執行該刪除
（會在 crash channel 上做無意義的 Android 呼叫）。

---

## 2. 任務拆分

> 🔴 **任務順序不可調換**：T1 是 T2 的前提（§P11 綁定關係）。
> T1/T2 寫入同一組檔案，**必須序列執行，不可並行**。

### T1. `NetworkNotifier` 通知參數化（§P11 重構）

**目標**：把寫死的通知 id / channel 抽成實例欄位，公開簽章零變更。

**寫入路徑**：
- `lib/src/notifications/network_notifier_io.dart`
- `lib/src/notifications/network_notifier_web.dart`（🔴 簽章必須同步）

**作法**：
1. `_notificationId` / `_channelId` / `_channelName` 由 `static const` 改為 `final` 實例欄位
2. 既有預設建構式**維持原簽章**，內部帶入原本的 network 常數值 → 既有呼叫端與測試零修改
3. 新增具名建構式 `NetworkNotifier.crash({...})`，帶入 crash 常數值
4. `buildDetails` 增加 `ongoing` 參數（預設 `true` 保持既有行為）
5. `_deleteLegacyChannel()` 僅在 network 實例執行（用一個 `final bool _deleteLegacy` 欄位控制，
   預設建構式 `true`、crash 建構式 `false`）
6. `_web` stub 同步新增 `NetworkNotifier.crash` 具名建構式（no-op）

**驗收**：
- [ ] `flutter test test/notifications/` 全綠且**測試檔未修改**
- [ ] `_io` 與 `_web` 的公開成員清單逐一比對一致

---

### T2. Crash 通知接線

**目標**：新增 `showCrashNotification` 旗標，在既有 crash 捕捉點推通知。

**寫入路徑**：
- `lib/src/core/flutter_inspector.dart`

**作法**：
1. 新增建構式參數 `this.showCrashNotification = false`（緊鄰 `showNetworkNotification` 宣告，
   維持既有參數排列慣例）
2. 新增 `_initCrashNotifier()`，沿用 `_initNetworkNotifier` 的既有模式：
   `await notifier.init()` 後才接線（避免持有指向未初始化 notifier 的 callback）
3. 接線點：**不改 `UncaughtErrorHandler`**。它的 `onLog` 已經是 `log`，
   crash 通知掛在 `log()` 的 error 分支，或在建構 `UncaughtErrorHandler` 時包一層
   forward——**由實作者選較小的 diff，但不得在 `UncaughtErrorHandler` 內部新增通知相依**
   （那會讓純邏輯類別綁上平台通知）
4. 通知內容：title = `Crash · <exceptionType>`，body = 訊息摘要（截斷至合理長度）
5. 點擊 → 開 Console tab（比照既有 `_openNetworkFromNotification`）

**⚠️ 必須確認的既有行為**：
`showCrashNotification` 開啟但 `captureUncaughtErrors` 關閉時，crash 根本不會被捕捉。
**這個組合要在 dartdoc 明講**（「需搭配 `captureUncaughtErrors: true`」），
不要偷偷自動開啟 `captureUncaughtErrors`——那是替使用者做決定。

**驗收**：
- [ ] 預設關閉時行為與現況完全一致
- [ ] 兩種通知可同時存在、互不覆蓋
- [ ] crash 節流不消耗網路通知的節流額度（各自持有 `AlertThrottler`）

---

### T3. 測試

**寫入路徑**：`test/notifications/network_notifier_test.dart`（擴充）

**🔴 必守本套件的 mock-free 測試風格**：
既有測試**從不呼叫 `init()`**（會拋 `LateInitializationError`，需平台 binding）。
測試只驗證「不可用狀態下的安全 no-op」與「throttler 接線順序」。
**新測試必須沿用此模式，不得為了測通知內容而引入整套 plugin mock。**

**涵蓋**：
- [ ] `NetworkNotifier.crash()` 建構式在未 init 時 `isAvailable == false`
- [ ] crash 實例的 `showOrUpdate` 在不可用時安全 no-op
- [ ] crash 與 network 兩個實例持有**不同的** notification id（透過可測的方式驗證，
      若需要則將 id 開為 `@visibleForTesting` getter）
- [ ] crash 實例的 throttler 與 network 實例互不干擾（注入兩個 throttler 驗證）
- [ ] `buildDetails(ongoing: false)` 的 Android `ongoing` 為 `false`

---

### T4. 文件同步：brainstorm 更新 + 更名

**寫入路徑**：`docs/brainstorm/2026-09-04-features-brainstorm.md` → 更名

**作法**：
1. 新增 **§P24. Crash 系統通知** 段落（沿用該文件既有的提案格式：
   痛點／好品味設計／公開 API／重用／effort／排查價值）
2. 更新 **§P11** 段落：原文寫「若 §P1 最終不做，這項重構本身沒有獨立存在的理由，
   應與 §P1 綁定排程」→ 改為「§P1 與 §P24 皆依賴本重構，任一動工即需先行」
3. 更新「完成度總覽」與「優先順序總表」，納入 §P24
4. `git mv docs/brainstorm/2026-09-04-features-brainstorm.md docs/brainstorm/2026-09-06-features-brainstorm.md`
5. 🔴 **更名後全 repo grep 舊檔名**，修掉所有引用
   （`grep -rn "2026-09-04-features-brainstorm" . --exclude-dir=.git`）

---

### T5. 驗證

- [ ] `flutter test`（554 tests 基準，不得減少）
- [ ] `flutter analyze lib/ test/`（不超出既有 7 個 info）
- [ ] `make format`
- [ ] 🔴 **套件層級 web 編譯必須成功** —— 條件匯出簽章漂移的**唯一可靠防線**。
      `flutter test` 跑在 VM 上，全程走 `_io` 分支，`_web.dart` 根本不會被載入，
      因此少一個建構式、簽章對不上都能測全綠（CLAUDE.md 不變式 #4）。
      人工比對公開成員清單是輔助，**不可取代此步**——編譯器擋得住，人眼擋不住。

      **🔴 不可用 `example/` 當關卡**（2026-09-06 實測確認）：`example/` 依賴 ObjectBox，
      而 ObjectBox 是 native-only（`dart:ffi`），在該目錄跑 `flutter build web`
      **永遠失敗且與本功能無關**：
      ```
      package:example/demos/objectbox_demo.dart → objectbox-5.3.2/lib/src/native/*
      Error: Dart library 'dart:ffi' is not available on this platform.
      ```
      **正確作法**：建一個只依賴本套件的最小專案（scratchpad 即可），
      `main.dart` 至少實例化一次 `FlutterInspector(... showNetworkNotification: true,
      showCrashNotification: true)` 讓條件匯出的兩個建構式都進入編譯圖，再 `flutter build web`。
      2026-09-06 已在改動前跑過一次基準：**套件單獨編 Web 為綠**（20.5s，無錯誤），
      故 T5 若失敗即為本次改動所致，不會與既有問題混淆。

---

## 3. 破壞性分析

| 風險 | 緩解 |
|:---|:---|
| **條件匯出簽章漂移**（最大風險） | T1 驗收比對 `_io`/`_web` 公開成員；**T5 以 `flutter build web` 實際編譯把關**（編譯期失敗，非人工檢查） |
| 既有網路通知行為改變 | 預設建構式帶入原常數值，既有測試不修改即須全綠 |
| Android channel 未註冊 | crash channel 於 `init()` 註冊，非首次 crash 時才建 |
| legacy channel 被重複刪除 | `_deleteLegacy` 旗標，僅 network 實例執行 |

## 4. 並行性判定

**🔴 全序列**。T1→T2 有嚴格依賴（參數化未完成，接線無處可接）；
T1/T2 寫入 `network_notifier_*.dart` 與 `flutter_inspector.dart`，
T3 依賴 T1/T2 的實際簽章。T4 雖路徑不重疊（只動 docs），但依賴最終實作結果撰寫，
排在 T3 之後最省返工。
