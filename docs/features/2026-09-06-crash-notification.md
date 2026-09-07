# 功能規格：Crash 系統通知（Crash Notification）

- **日期**：2026-09-06
- **狀態**：已實作（Issue #156 / PR #157）
- **關聯**：§P11（多告警類型重構 NetworkNotifier）為本功能的**解鎖前提**

---

## 1. 背景與問題（Why）

目前 `flutter_inspector_kit` 僅在 **API 呼叫**時推送系統通知（`showNetworkNotification`），
由 `NetworkNotifier` 維護一則「持續更新的網路活動摘要」。

**缺口**：崩潰（uncaught error）發生時**沒有任何系統層級的即時提示**。

現況下 crash 的三個來源已被 `UncaughtErrorHandler` 完整捕捉並寫入 log 時間軸
（`captureUncaughtErrors = true` 時），但：

- App 在**背景**時，QA／開發者完全不知道剛剛發生了 crash
- 即使在前景，也得**主動打開 dashboard** 才會發現 error 進了 timeline
- 網路異常有系統通知、崩潰卻沒有——這個**不對稱**沒有正當理由

**使用者故事**：
> 身為 QA，我在測試流程中把 app 切到背景／正在操作別的畫面，
> 我希望 app 一發生 crash 就跳出系統通知，讓我當下就知道要回頭查，
> 而不是測完一輪才發現 timeline 裡躺著三個 error。

---

## 2. 範圍（What）

### 2.1 納入範圍

**新增建構式旗標 `showCrashNotification`（預設 `false`）**，開啟後：

| Crash 來源 | 對應 hook | 現況 |
|:---|:---|:---|
| Flutter framework 錯誤 | `FlutterError.onError` | ✅ 已捕捉（`uncaught_error_handler.dart:41`） |
| Widget build 錯誤 | `ErrorWidget.builder` | ✅ 已捕捉（`:76`） |
| 非同步／平台錯誤 | `PlatformDispatcher.instance.onError` | ✅ 已捕捉（`:56`） |

三者皆已被捕捉，**本功能不新增任何 hook**，只是在既有捕捉點多推一則系統通知。

### 2.2 明確不納入（Out of Scope）

- ❌ **不新增緩衝維度**：crash 已是 `LogEntry`（`LogLevel.error`），不新增 Entry／Inspector／RingBuffer
- ❌ **不做錯誤爆發偵測（§P1）**：本功能是「每個 crash 一則通知（受節流）」，
  不是「N 秒內 M 個錯誤才告警」的 spike 偵測。§P1 是獨立提案，不在本次範圍
- ❌ **不改變既有 `showNetworkNotification` 的任何對外行為**
- ❌ **Web 平台不支援**：沿用既有 `_web` stub 的 no-op 慣例（`flutter_local_notifications`
  透過 `dart:io`，必須排除在 web import graph 外以維持 WASM 相容）

---

## 3. 關鍵設計決策

### 3.1 必須先做 §P11 重構（不可繞過）

**這是本規格最重要的判斷。**

`NetworkNotifier` 目前把「一則通知」寫死成兩個私有常數（2026-09-06 實查確認）：

```dart
network_notifier_io.dart:31  static const int _notificationId = 0x6E657477; // 'netw'
network_notifier_io.dart:33  static const String _channelId = 'flutter_inspector_network_v2';
```

若直接在 `NetworkNotifier` 內加 crash 通知，會被迫長出 `if/else` 區分
「網路摘要」與「崩潰告警」兩種語意——**這正是「特殊情況」的壞味道**。

**正解（§P11 的設計）**：把 `id` + `channel` 參數化，讓 `NetworkNotifier` 成為
這個通用能力的**其中一個呼叫者**，而非通知邏輯的擁有者。

**已具備、無需再動的部分**（2026-09-06 實查確認，與 §P11 的 2026-08-23 校正一致）：

- `AlertThrottler` **已支援建構式注入**（`:19,22` `AlertThrottler? throttler`），
  crash 通知直接傳入自己那份實例即可，節流器邏輯**零修改**
- `_io` / `_web` 雙向簽章一致的條件匯出模式已成熟，照抄即可

**剩餘缺口僅為兩個私有常數的參數化** —— 這是 §P11 把 effort 由 `low` 下修為
`trivial~low` 的依據，本次實查證實該判斷仍然成立。

### 3.2 通知必須獨立於網路通知

- **獨立 notification id**：crash 通知不可覆蓋網路摘要通知，兩者必須能同時存在
- **獨立 channel**：Android 上使用者可分別關閉「網路」與「崩潰」兩類通知
- **crash 通知不是 `ongoing`**：網路摘要是持續更新的常駐通知（`ongoing: true`），
  crash 是**離散事件**，應為可滑掉的一般通知

### 3.3 節流：沿用 `AlertThrottler`，不發明新機制

crash 可能在一秒內連續觸發數十次（例如 build 迴圈中的錯誤）。
沿用既有 `AlertThrottler`（2 秒窗），**crash 通知持有自己的實例**，
與網路通知的節流互不干擾。

### 3.4 與既有去重機制的關係

`UncaughtErrorHandler._lastLoggedDetails`（`:26`）已處理
「`FlutterError.onError` + `ErrorWidget.builder` 對同一錯誤雙擊」的去重。
**通知走在 log 之後**，因此自動繼承這層去重，不需要另寫一套。

---

## 4. 驗收條件

### 4.1 行為

- [ ] `showCrashNotification` 預設 `false`；不開啟時行為與現況**完全一致**
- [ ] 開啟後（**且 `captureUncaughtErrors` 亦為 `true`**，否則 hook 未掛載、無事件可通知），
      三種 crash 來源任一觸發 → 推送一則系統通知
- [ ] 通知內容含：錯誤類型（`exceptionType`）與訊息摘要
- [ ] 點擊通知 → 開啟 dashboard 的 Console tab（對齊既有網路通知點擊開 Network tab 的慣例）
- [ ] crash 通知與網路通知**可同時存在**，互不覆蓋
- [ ] 連續 crash 受 `AlertThrottler` 節流，且**不消耗網路通知的節流額度**

### 4.2 不可回歸（Never break userspace）

- [ ] `NetworkNotifier.showOrUpdate()` **公開簽章不變**，既有呼叫端零修改
- [ ] `showNetworkNotification` 的既有行為（含 legacy channel 刪除）完全不受影響
- [ ] 既有 `test/notifications/network_notifier_test.dart` **全數通過且不需修改**
- [ ] Web build 不引入 `dart:io`；`_io` / `_web` 雙向簽章一致

### 4.3 測試

- [ ] 新增 crash 通知的 unit test（沿用既有 mock plugin + 注入 throttler 的測試模式）
- [ ] 涵蓋：預設關閉、三種來源各觸發一次、節流生效、與網路通知互不干擾
- [ ] `flutter test` 全綠（既有 554 tests 不得減少）
- [ ] `flutter analyze lib/ test/` 不超出既有 7 個 info 基準

---

## 5. 文件更新需求（使用者明確要求）

本功能需**同步寫入 brainstorm 文件**：

- **目標檔**：`docs/brainstorm/2026-09-04-features-brainstorm.md`
- **檔名前綴更新**：依專案慣例（日期前綴 = 最後實質更新日）
  更名為 `2026-09-06-features-brainstorm.md`
- **寫入位置**：作為新提案編號（沿用 `§P` 序列，接續現有最大編號 §P23 → **§P24**）
- **內容**：本功能的痛點、好品味設計、與 §P11 的綁定關係、effort 與排查價值
- **同步更新**：§P11 段落需註明「除 §P1 外，§P24 亦依賴本重構」——
  因 §P11 原文寫明「若 §P1 最終不做，這項重構本身沒有獨立存在的理由，應與 §P1 綁定排程」，
  本功能的出現改變了該綁定關係，文件必須反映

> ⚠️ 更名須用 `git mv` 保留檔案歷史，並檢查是否有其他文件引用舊檔名。

---

## 6. Effort 評估

| 項目 | Effort | 說明 |
|:---|:---:|:---|
| §P11 通知參數化重構 | trivial~low | 僅兩個私有常數參數化（實查確認） |
| crash 通知本體 | low | 新旗標 + 既有捕捉點接線 + `_io`/`_web` 雙分支 |
| 測試 | low | 沿用既有測試模式 |
| 文件更新 + 更名 | trivial | — |

**總計**：low ｜ **價值**：⭐⭐⭐⭐（補上網路／崩潰的通知不對稱，QA 場景剛需）

---

## 6.5 已知限制：啟動期空窗不通知（不處理）

`init()` 是非同步平台通道呼叫，而 error hook 在建構式中**同步**掛載。
從建構式回傳到 `init()` 完成之間（數十至數百毫秒），`_available` 仍為 `false`，
此期間發生的 crash **會寫入 log，但不會顯示系統通知**。

**這是可修的，但決定不修。** 修法是把空窗期的 crash 排進佇列，`init()` 完成後 flush
補發（約十餘行）。判定為 edge case 而不排程——需要「app 啟動最初數十毫秒內就崩潰」
且「該次崩潰必須靠系統通知才會被發現」兩個條件同時成立；實務上此時開發者正盯著螢幕，
且 log 與 timeline 皆已完整記錄。

> ⚠️ **不要把 `_crashNotifier` 於 `await` 前指派誤認為此問題的修正。**
> 那次改動（PR #157 review 回應）只消除了「欄位為 null 而靜默丟棄」的結構缺陷，
> **對使用者可見行為毫無改變**——修正前後空窗期都不會通知，只是攔截點從
> `_notifyCrash` 的 null 檢查移到 `showCrash` 的 `_available` 檢查。
> 若日後要真正解決，唯一路徑是上述佇列補發。

## 7. 風險與注意事項

1. **條件匯出雙向簽章**（CLAUDE.md 核心不變式 #4）：
   `_io` 與 `_web` 任一側公開介面改動**必須同步改另一側**，
   否則 Web build 崩潰且**單元測試無法捕捉**。這是本次改動最大的破壞風險。

2. **Android channel 註冊時機**：新 channel 需在 `init()` 一次註冊，
   不可在首次 crash 時才建立（會遺失第一則通知）。

3. **crash 通知不應在 `_available == false` 時消耗節流額度**：
   沿用既有 `showOrUpdate` 的「可用性 guard 先於節流檢查」順序（`:184-186` 的既有註解已說明此設計）。
