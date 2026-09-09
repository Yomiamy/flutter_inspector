# 功能規格：鍵值儲存檢視器（Key-Value / SharedPreferences Browser）（§P15）

> 來源：`docs/brainstorm/2026-09-08-features-brainstorm.md` §P15（L712–760）
> Effort（提案原估）: medium ｜ 排查價值：⭐⭐⭐⭐⭐
> **驗收條件共 38 條**（rev.2 由 33 條擴充，見修訂紀錄）
> **範圍已定案：完整讀寫**（列表 + 搜尋 + inline 編輯 + 刪除 + 清空），非唯讀版。
> 本文件只描述 What & Why。How（實作拆解、任務粒度）屬 STAGE 0b，不在此。

---

## 修訂紀錄

### 2026-08-21（rev.2）歸屬決策翻案：Database Tab → 獨立 Storage Tab

**改了什麼**

| 章節 | 變更 |
|------|------|
| §「為什麼歸入 Database Tab，不新增第五個 Tab」 | 整節改寫為「為什麼獨立為 Storage Tab」 |
| U-1（是否更名 Storage Tab） | **結案**——被本次決策取代，不再是未決事項 |
| AC-30 ~ AC-33（不破壞既有功能） | 形狀重寫並擴充為 AC-30 ~ AC-38：從「不破壞 Database Tab 內部」改為「Storage tab 條件性掛載 + 不影響既有四個 tab」。**AC 總數 33 → 38** |
| §範圍邊界 In scope | 「Database Tab 的 source 選擇擴充」→「Dashboard 新增 Storage Tab」 |
| R-4 / U-5 | 標記**已消失**（見該節），保留原文作歷史紀錄 |
| §影響範圍 | `database_tab.dart` 從「修改」移到「不修改」；`dashboard_modal.dart` 新增為「修改」 |

**為什麼**

使用者原話：「還是有必要區分他是 Database 還是 SharedPreference，東西不只給 QA，RD 也會看。」

**區分儲存引擎本身就是排查資訊。** 原規格以「概念同源」論證兩者可合併，但那個論證只
站在 QA 的視角。RD 的排查需求是「這筆資料實際上躺在哪個引擎」——SQLite 的資料異常和
SharedPreferences 的資料異常，成因、修法、責任歸屬都不同。把兩者混進同一個 tab，
等於在使用者最需要這個訊號的時候把它抹掉。

**同時修正一個已證實錯誤的理由。** 原規格寫「bottom navigation 的 tab 數已在臨界值，
再加一個就必須做 scrollable tab bar——付出導航結構退化的代價」。

實查 `lib/src/ui/dashboard/dashboard_modal.dart:156`：**已經是 `isScrollable: true`**。
scrollable 早就開了，那個「代價」根本不存在。此理由已從本規格移除，不留存。
（記取教訓：拿未經查證的技術限制去支撐產品決策，是最糟的一種論證。）

**不變的部分**：完整讀寫範圍、介面與資料模型、寫入操作的安全設計、稽核 log、
零新相依（AC-1 ~ AC-29 逐字不動）。本次翻案只動「這個 UI 掛在哪裡」，不動「這個 UI 做什麼」。

---

## What：這個功能是什麼

在 Inspector Dashboard 內提供一個**鍵值儲存的瀏覽與操作介面**，讓使用者在 App 執行中
直接看到並修改 `SharedPreferences` / `FlutterSecureStorage` 這類扁平 key-value 儲存的內容。

能力共五項：

1. **列表** — 列出某個 KV source 的所有 key、value、型別
2. **搜尋** — 以關鍵字比對 key（與 value）過濾列表
3. **inline 編輯** — 就地修改某個 key 的 value
4. **刪除** — 移除單一 key
5. **清空** — 清除該 source 的全部 key

其中 3/4/5 為寫入操作，一律**二次確認 + 自動記 Console log**（詳見「寫入操作的安全設計」）。

資料來源以 **host-injection** 提供：套件定義介面，消費端 App 注入實作。套件本身
**不引入** `shared_preferences` / `flutter_secure_storage` 任何相依。

---

## Why：為什麼要做，以及為什麼是這個形狀

### 為什麼是真實問題

Database Tab 已能瀏覽 SQLite / ObjectBox，但那只覆蓋了「結構化本地持久化狀態」。
實務上讓 QA 卡住的另一半——Token、Feature Flag、快取旗標、上次登入時間——幾乎都躺在
`SharedPreferences` 裡，而這一塊在 App 內**完全沒有任何檢視手段**。

現況下 QA 遇到「Token 過期但沒清乾淨導致 401 循環」「Feature Flag 卡在錯誤值導致畫面空白」
「快取污染導致舊資料一直出現」時，唯一的路徑是：停下測試 → 找開發者 → 拉 `adb shell` 或
解 iOS sandbox → 手動翻 XML / plist。這條路徑不是「慢」，是**在 QA 手上根本不存在**——
它把一個 30 秒能確認的問題，變成一次跨人協作。

### 為什麼必須可寫，不能只做唯讀

這是本規格最關鍵的範圍判斷，需要說清楚，因為它直接決定 effort 是 medium 還是 small。

唯讀版能回答「現在的值是什麼」，但 QA 的真實工作流是**驗證假設**：

- 「我懷疑是 Token 沒清掉」→ 需要**清掉 Token 再跑一次**才能確認
- 「這個隱藏功能開關在哪」→ 需要**把 flag 改成 true** 才能進去測
- 「重現全新安裝狀態」→ 需要**清空**

唯讀版讓 QA 看到值之後，仍然得回頭找開發者才能改。也就是說：**唯讀版解決了「看見」，
但沒有解決「不必找開發者」——而後者才是這個功能的實際價值來源。**
既然痛點的定義是「QA 必須請開發者介入」，只做唯讀等於保留了痛點本身。

### 為什麼獨立為 Storage Tab，而不是併入 Database Tab

**因為「這筆資料存在哪個引擎」本身就是排查資訊。**

使用者的判斷（2026-08-21 定案）：「還是有必要區分他是 Database 還是 SharedPreference，
東西不只給 QA，RD 也會看。」

這個功能有兩類使用者，需求方向相反：

| 使用者 | 心智模型 | 對「引擎」的態度 |
|--------|---------|-----------------|
| QA | 「App 本地存了什麼」 | 不在意引擎，只想找到那個值 |
| RD | 「這個異常出在哪一層」 | **引擎是關鍵訊號**——SQLite 的資料錯與 SharedPreferences 的資料錯，成因、修法、負責的模組都不同 |

把兩者混在同一個 tab（哪怕內部有分段切換器），會讓「資料實際躺在哪」這個訊號變成
需要多按一下才能確認的次要資訊。而對 RD 來說，那正是他打開這個工具要看的第一件事。

導航結構本身就在傳遞資訊：**tab 的分界＝儲存引擎的分界**。這不是把同源的東西拆散，
是讓 UI 結構誠實反映底層的真實差異。兩者除了「都是本地持久化」之外，介面不共享任何方法
（一邊 `listTables`/`fetchRows`，一邊 `listAll`/`setValue`/`remove`/`clear`），
操作模式也不同（Database Tab 唯讀瀏覽，Storage Tab 可寫入）。強行合併是製造假的共通性。

> **已排除的錯誤論證（留存以免重蹈）**：本規格 rev.1 曾主張「tab 數已在臨界值，再加一個
> 就必須做 scrollable tab bar」。**實查 `dashboard_modal.dart:156` 證明此說法不成立——
> `isScrollable: true` 早已開啟。** 該理由已刪除，不作為任何決策的依據。

> **U-1 結案**：原問題「Database Tab 是否應更名為 Storage Tab」已被本決策取代。
> 答案是**兩者都不動**：既有 Database Tab 保留原名原行為（一個字不改），
> KV 另開名為 **Storage** 的新 tab。零更名風險。

### 為什麼是 host-injection

套件零新相依是既有慣例，且已驗證三次：

| 介面 | 套件**不**引入的相依 |
|------|---------------------|
| `DiagnosticInfoSource` | `device_info_plus` |
| `DatabaseBrowserSource` | `sqflite` |
| `WebViewBridgeAdapter` | webview 套件 |

第四次沿用同一模式，不需要新發明。這不只是「少一個相依」的潔癖——`shared_secure_storage`
這類套件帶 native 通道與平台部署下限，把它塞進一個 debug 工具套件會直接污染所有消費端的
建置設定（見 MEMORY 中「Example native-plugin 平台下限」的既有教訓）。

---

## 使用者故事

### US-1（QA）確認 Token 狀態
> 身為 QA，當 App 陷入 401 循環時，我要在 Inspector 內直接看到 `auth_token` 的當前值與
> 過期時間戳，好判斷是「Token 真的過期」還是「後端誤判」，不必請開發者拉 adb。

### US-2（QA）清掉 Token 重現全新狀態
> 身為 QA，當我懷疑登入狀態污染時，我要能刪掉 `auth_token` 這一個 key 後重啟流程，
> 好在不重裝 App（會連帶清掉我準備好的其他測試資料）的前提下驗證假設。

### US-3（QA）手動開啟 Feature Flag
> 身為 QA，當我要測一個尚未對外開放的功能時，我要能把 `feature_new_checkout` 從 `false`
> 改成 `true`，好立刻進入該流程測試，不必等開發者出一個特製版本給我。

### US-4（QA）重現全新安裝
> 身為 QA，當我要驗證首次啟動引導流程時，我要能一鍵清空整個 SharedPreferences，
> 好取得等同全新安裝的狀態，而不必真的移除並重裝 App。

### US-5（QA）在大量 key 中找到目標
> 身為 QA，當某個 source 有上百個 key 時，我要能用關鍵字搜尋（例如輸入 `token`）
> 快速定位，好不必用肉眼逐列掃描。

### US-6（開發者）確認寫入真的生效
> 身為開發者，當我懷疑某段程式沒有正確寫入偏好設定時，我要能在功能操作後立刻回到
> Inspector 重新整理列表，好確認值是否如預期改變。

### US-7（開發者）追溯是誰改了狀態
> 身為開發者，當 QA 回報一個現象時，我要能在 Console 或診斷報告中看到「Inspector 曾在
> 某時刻把某 key 改成某值」，好分辨這個現象是 App 的 bug，還是 QA 用 Inspector 手動改
> 出來的假象。
>
> 這條是**觀測者效應的反制**：一個能改變被觀測系統狀態的 debug 工具，如果不留痕跡，
> 它製造的困惑會比它解決的多。

### US-8（開發者）同時檢視多個儲存
> 身為開發者，當 App 同時使用 SharedPreferences 與 SecureStorage 時，我要能在同一處
> 切換檢視兩者，好比對「一般偏好」與「敏感資料」是否一致。

### US-9（消費端開發者）接入成本可預期
> 身為導入此套件的開發者，我要能照著 README 範例實作介面並在建構 `FlutterInspector`
> 時注入，好在不新增任何相依、不改動既有 `databaseSources` 接線的前提下啟用此功能。

---

## 驗收條件

每條均可機械驗證（單元測試或 widget test）。

### 介面與資料模型

- **AC-1** 套件匯出 `KeyValueBrowserSource` 抽象介面，具備 `String get name`、
  `Future<List<KeyValueEntry>> listAll()`、`Future<void> setValue(...)`、
  `Future<void> remove(String key)`、`Future<void> clear()` 五個成員。
- **AC-2** 套件匯出 `@immutable` 的 `KeyValueEntry` 資料類，並實作 `operator ==`、
  `hashCode`、`toString()`（與 `DatabaseTableInfo` 的既有慣例一致）。
- **AC-3** `pubspec.yaml` 的 `dependencies` 在本功能前後**逐字相同**——不新增
  `shared_preferences`、`flutter_secure_storage` 或任何其他相依。

### 註冊機制

- **AC-4** `FlutterInspector` 建構式接受可選具名參數 `keyValueSources`，未傳入時
  對應 getter 回傳空清單，且 Dashboard **不顯示 Storage tab**（見 AC-30）。
- **AC-5** `FlutterInspector` 提供 `registerKeyValueSource(...)` 可在建構後動態註冊，
  註冊後對應 getter 反映新增結果。
- **AC-6** 對應 getter 回傳不可變（unmodifiable）清單，外部修改會拋錯——與
  `databaseSources` 既有行為一致。

### 讀取

- **AC-7** 選中某個 KV source 時，畫面列出該 source `listAll()` 回傳的所有 entry，
  顯示 key、value 與型別。
- **AC-8** `listAll()` 回傳空清單時顯示空狀態文案，不顯示錯誤。
- **AC-9** `listAll()` 拋出例外時顯示 `ErrorCard` 並提供重試，重試會再次呼叫
  `listAll()`（沿用 Database Tab 既有的 loading / error / empty 三態處理形態）。
- **AC-10** 提供重新整理動作，觸發後重新呼叫 `listAll()` 並更新列表。
- **AC-11** 在搜尋欄輸入關鍵字後，列表只顯示 key 或 value 含該關鍵字的 entry；
  清空關鍵字後恢復完整列表。
- **AC-12** 搜尋比對不分大小寫。

### 寫入：編輯

- **AC-13** 對某個 entry 觸發編輯並輸入新值後，畫面**先**顯示二次確認，使用者確認前
  **不**呼叫 `setValue()`。
- **AC-14** 確認後呼叫 `setValue()`，傳入的 key 與新 value 與使用者輸入一致。
- **AC-15** 在二次確認中選擇取消時，`setValue()` **完全不被呼叫**，且列表維持原值。
- **AC-16** `setValue()` 成功後，列表反映新值（重新載入或就地更新皆可）。
- **AC-17** `setValue()` 拋出例外時，錯誤訊息可見，且不會使畫面停在無限 loading。
- **AC-18** 使用者輸入的字串無法轉換為該 entry 原型別（例如對 `int` 型別輸入 `abc`）時，
  顯示驗證錯誤且**不**呼叫 `setValue()`。

### 寫入：刪除

- **AC-19** 觸發刪除後先顯示二次確認，確認前不呼叫 `remove()`；確認後以正確 key 呼叫。
- **AC-20** 取消刪除時 `remove()` 不被呼叫，該 entry 仍在列表中。
- **AC-21** `remove()` 成功後該 entry 從列表消失。

### 寫入：清空

- **AC-22** 觸發清空後顯示二次確認，且該確認**明確標示將被清除的 source 名稱與筆數**
  （比單鍵刪除更強的防護，因為此操作不可逆且影響範圍最大）。
- **AC-23** 取消清空時 `clear()` 不被呼叫，列表內容不變。
- **AC-24** 確認後呼叫 `clear()`，成功後列表變為空狀態。

### 寫入：稽核軌跡

- **AC-25** 每次成功的 `setValue()` 都產生**恰好一筆** `LogLevel.info` 的 Console log，
  內容可辨識出「來源 source 名稱」「key」「新值」。
- **AC-26** 每次成功的 `remove()` 產生恰好一筆 info log，可辨識出 source 名稱與 key。
- **AC-27** 每次成功的 `clear()` 產生恰好一筆 info log，可辨識出 source 名稱。
- **AC-28** 寫入操作**失敗**時（介面方法拋例外）**不**產生「成功」語意的 log。
  > **U-2 已於 STAGE 0b 定案（2026-08-21）＝失敗不額外記 error log。** 失敗已由
  > `ErrorCard` 當場呈現，補一筆 error log 只是換個地方講同一件事；且會讓
  > AC-25~27 的「恰好一筆」斷言退化為「恰好一筆 info 加恰好一筆 error」的組合。
  > 日後若出現「事後才發現寫入失敗過」的實例，再另案評估。
- **AC-29** 使用者**取消**二次確認時不產生任何 log（未發生的事不該留痕跡）。

### Tab 掛載（2026-08-21 rev.2 新增／改寫）

- **AC-30** 未注入任何 `keyValueSources` 時，Dashboard **不顯示 Storage tab**，
  tab 總數與本功能實作前**逐字相同**（無 custom tab 時 4 個、有 custom tab 時 5 個）。
  > 條件性顯示比照 `customTab` 的既有慣例（`dashboard_modal.dart:44` 的
  > `hasCustomTab ? 5 : 4`）。理由有二：一是與既有慣例一致；二是永遠空白的 tab
  > 是純粹的噪音——沒注入 source 就沒有東西可看。
- **AC-31** 注入至少一個 `keyValueSource` 時，Dashboard 顯示標題為 **`Storage`** 的
  新 tab，且該 tab 的 `TabBarView` 子項為 KV 視圖。
- **AC-32** Storage tab 位於 **Database tab 之後**、custom tab 之前。
  > 順序理由：既有四個 tab 的 index 0~3 是公開契約（見 AC-33），
  > 只能往尾端追加。Storage 緊鄰 Database 也符合「兩者都是本地儲存」的視覺分組。
- **AC-33** 既有四個 tab 的 index 不變：Console(0)、Network(1)、Navigator(2)、Database(3)。
  `openDashboard(initialIndex: 1)` 仍開在 Network tab。
  > 這是**既有公開行為**，`flutter_inspector.dart:363-365` 的 doc comment 已把
  > 這組 index 寫成契約，且 `_openNetworkFromNotification()` 硬編碼 `initialIndex: 1`。
- **AC-34** 注入 KV source 時，`initialIndex` 的 clamp 上界隨 tab 總數同步調整
  （超出範圍的 index 被夾到最後一個 tab，而非夾到舊的上界）。

### 不破壞既有功能

- **AC-35** `database_tab.dart` 在本功能前後**逐字未變更**（獨立 tab 後完全不需觸碰）。
  Database Tab 的 widget 樹、`DropdownButton<DatabaseBrowserSource>`、
  `is OperationLogSource` 分岔、`_clearDatabase()` 的無確認行為全部原封保留。
- **AC-36** 既有 Dashboard 測試在未修改測試碼的前提下通過。
  > ⚠️ **實查修正（2026-08-21）**：先前認為「既有測試沒有寫死 tab 數」是**錯的**。
  > 實查發現三個檔案共 5 處寫死：
  > `dashboard_modal_test.dart:17`（`findsNWidgets(4)`）、`:56`（clamp 斷言 index 為 `3`）、
  > `:70`（`findsNWidgets(5)`）、
  > `dashboard_error_badge_test.dart:40`、`:97`（皆 `findsNWidgets(4)`）。
  > 這些測試**全部不注入 `keyValueSources`**，因此在 AC-30 的條件性顯示下自然仍為
  > 4／5 個 tab，斷言不需修改即通過。這正是選擇條件性顯示（而非無條件新增）的
  > 第三個、也是最硬的理由：**無條件新增 tab 會讓這 5 處斷言全紅。**
- **AC-37** `KeyValueTable` 的四個既有唯讀呼叫端（`network_detail_view.dart` 三處、
  `log_detail_view.dart` 一處）渲染結果不變，既有測試不需修改即通過。
- **AC-38** `OperationLogSource` 的清空按鈕行為（僅在 op-log source 顯示）不受影響
  ——因為 `database_tab.dart` 零改動（AC-35），此條為 AC-35 的必然結果。

---

## 範圍邊界

### In scope

- `KeyValueBrowserSource` 介面與 `KeyValueEntry` 資料類
- `FlutterInspector` 的 `keyValueSources` 建構參數與 `registerKeyValueSource()`
- Dashboard 新增條件性顯示的 **Storage tab**（`dashboard_modal.dart` 的 tab 計數、
  tab 清單、`TabBarView` children 三處同步）
- KV source 選擇器（Storage tab 內部自己的 `DropdownButton<KeyValueBrowserSource>`）
- KV 列表 UI：列表、搜尋、重新整理、loading / error / empty 三態
- 寫入 UI：inline 編輯、刪除、清空，各含二次確認
- 寫入操作的自動 Console log
- README 的 `SharedPreferences` 與 `FlutterSecureStorage` 接線範例

### Out of scope（明確不做）

- **套件內建任何 KV 實作**——不提供 `SharedPrefsBrowserSource`，僅在 README 給範例碼。
  理由同 `DatabaseBrowserSource` 不內建 sqflite 實作。
- **新增 key**——本功能是「檢視與修正既有狀態」。憑空新增一個 App 從未寫過的 key，
  幾乎不會是有效的排查手段（App 讀不到就是讀不到），卻要引入「型別選擇 UI」的完整複雜度。
  真有需求再說。
- **變更既有 key 的型別**——編輯限定在原型別內。跨型別修改的實際需求未經驗證，
  而它會讓 AC-18 的驗證邏輯膨脹成型別轉換矩陣。
- **巢狀 / 結構化 value 的樹狀編輯器**——若 value 是 JSON 字串，就當純字串編輯。
- **復原（undo）**——寫入即生效。二次確認已是防線，undo 需要維護操作歷史與反向操作，
  複雜度與這個 debug 工具的定位不匹配。
- **敏感值遮蔽**——本功能的**全部價值**就是看見 Token 的真實值。此處遮蔽等於自廢武功。
  > **未決事項 U-3**：這是否與既有 `redactSensitiveData` 的全域語意衝突，需在 STAGE 0b
  > 確認既有旗標的作用範圍是否會意外波及此處。
- **抽出共用的 `SearchBar` 元件並回頭重構 ConsoleTab / NetworkTab**（見 R-2）
- **診斷報告（`buildDiagnosticReport`）納入 KV 內容**——寫入操作的 log 本來就會進
  Timeline，已足夠。把整份 KV dump 進報告會讓報告膨脹且含敏感值。
- **監看 KV 變化並即時推播**——需要 source 提供變更通知，介面複雜度倍增。手動重新整理夠用。

---

## 寫入操作的安全設計

這是本功能與既有所有唯讀功能的根本差異：**Inspector 第一次會改變被觀測系統的狀態**。
三道防線：

### 防線一：二次確認（防誤觸）

編輯、刪除、清空三者皆需確認後才實際呼叫介面方法。分級如下：

| 操作 | 影響範圍 | 確認強度 |
|------|---------|---------|
| 編輯 | 單一 key，可再改回來 | 標準確認，顯示 key 與新舊值 |
| 刪除 | 單一 key，不可逆 | 標準確認，顯示 key 與將被刪除的值 |
| 清空 | 全部 key，不可逆 | **強化確認**：明確標示 source 名稱與筆數（AC-22） |

> **實查發現 F-1**：套件內**目前沒有任何 `showDialog` / `AlertDialog` 使用**。
> `database_tab.dart:63` 的 `_clearDatabase()` 是直接執行、零確認。
> 也就是說「二次確認」在此專案是**全新的 UI 模式，沒有既有元件可重用**，
> 不是「照抄現成 dialog」。這會影響 effort 估算。
>
> 附帶觀察（不在本功能範圍，僅記錄）：既有的 op-log 清空同樣無確認。
> 但那清的是 Inspector 自己的 buffer，不是 App 的持久化狀態，風險等級不同，
> 此處不主張一併修改——**既有行為零改動**是硬性約束。

### 防線二：自動稽核 log（防觀測者效應）

每次成功寫入自動產生一筆 `LogLevel.info` 的 Console log。這不是「nice to have」，
是這個功能能否被信任的前提：見 US-7。

已驗證可用的 API（`flutter_inspector.dart:281`）：

```dart
void log(
  String message, {
  LogLevel level = LogLevel.info,
  String? stackTrace,
  Map<String, dynamic>? data,
})
```

`data` 欄位可承載結構化資訊（source / key / 新值），無需新增任何 model 欄位。

> **未決事項 U-4**：log 訊息中是否應包含**舊值**。包含的話追溯性更完整
> （「原本是什麼被改成什麼」），但會讓一筆 log 變長。傾向包含，STAGE 0b 定案。

### 防線三：失敗不留假痕跡

寫入失敗時不得產生成功語意的 log（AC-28），取消時不得產生任何 log（AC-29）。
一份會騙人的稽核軌跡比沒有更糟。

---

## 風險與未決事項

### R-1（高）`KeyValueTable` 不可重用於寫入路徑——提案原文的重用清單有誤

**實查結果**（`lib/src/ui/widgets/key_value_table.dart`）：

- 它是 `StatelessWidget`，建構參數只有 `data: Map<String, dynamic>?` 與 `emptyLabel`
- value 一律以 `'${e.value}'` 渲染，**沒有任何 callback、沒有任何互動能力**
- 四個既有呼叫端全部是唯讀展示（`network_detail_view.dart:62/66/77`、
  `log_detail_view.dart:92`）

提案原文寫「重用 `KeyValueTable`（已能渲染 Map）」——**這句只在唯讀情境成立**。
本功能定案為完整讀寫，編輯與刪除需要 per-entry 的互動與 callback，現有 widget 給不了。

兩條路，各有代價：

| 方案 | 代價 | 破壞風險 |
|------|------|---------|
| A. 擴充 `KeyValueTable` 加入可選 callback | 動到 4 個既有唯讀呼叫端所依賴的 widget | 中——參數雖可選，但 build 邏輯分岔，等於在共用元件裡種下「有無 callback」的特殊情況 |
| B. 新寫獨立的 KV 列表 widget | 兩個 widget 表面上「都在畫 key-value」 | 低——既有四處零改動 |

**規格層的判斷傾向 B**，理由是 Linus 準則的直接應用：方案 A 是在一個乾淨的
`StatelessWidget` 裡塞入一組 `if (onEdit != null)` 的特殊情況，去服務一個
**渲染需求本來就不同**的使用場景（唯讀 KV table 顯示的是 `Map<String, dynamic>`，
KV browser 顯示的是帶型別的 `KeyValueEntry` 清單並需要 per-row 操作）。
兩者共用的只有「左右兩欄」這個視覺巧合，不是同一個抽象。

**已定案採 B**（使用者拍板）。**AC-37 把「既有四處不受影響」釘成硬性驗收條件。**

### R-2（中）`_SearchBar` 不可重用，且已重複兩份

**實查結果**：

- `console_tab.dart:289` — `class _SearchBar extends StatefulWidget`
- `network_tab.dart:129` — `class _SearchBar extends StatelessWidget`

兩份**同名、私有（`_` 前綴）、形態已漂移**（一個有狀態一個無狀態）。私有代表
無法 import，形態漂移代表就算改成公開也不能直接合併。

提案原文「重用 `_SearchBar` 元件」**不成立**。選項：

| 方案 | 代價 |
|------|------|
| A. 為 KV 視圖新寫第三份搜尋欄 | 技術債從 2 份變 3 份 |
| B. 先抽共用元件再用 | 範圍擴大到 ConsoleTab + NetworkTab 兩個既有 tab，需回歸測試 |

本規格**不預先決定**。但明確標記：選 B 等於把「重構既有兩個 tab」納入本功能，
會顯著改變 effort 與破壞風險評估——這是 STAGE 0b 必須明說並讓使用者拍板的事，
不該偷偷夾帶。若選 A，應在程式碼留下註記說明技術債已知。

### R-3（低）可信的重用——已逐項驗證屬實

以下三項提案宣稱經實查確認可靠：

- **`DatabaseBrowserSource` 的 host-injection 模式**
  （`lib/src/models/database_browser_source.dart`）：abstract class + `String get name`
  + `Future` 方法 + `@immutable` 資料類（含完整 `operator ==` / `hashCode` / `toString`）。
  形狀可直接鏡射。
- **註冊機制**（`lib/src/core/flutter_inspector.dart`）：`:191` getter 回傳
  `List.unmodifiable([...])`、`:214` 建構參數 `List<DatabaseBrowserSource>?`、
  `:234` 建構式內注入、`:264` `registerDatabaseSource()` 動態註冊。四點皆可鏡射。
- **`inspector.log()`**（`:281`）：簽名已確認，可承載寫入稽核。

### ~~R-4（中）Database Tab 的 source 選擇需容納兩種不同型別的來源~~ → **已消失（2026-08-21 rev.2）**

**此風險因歸屬決策改為獨立 Storage Tab 而不復存在。**

Storage tab 有自己的 `DropdownButton<KeyValueBrowserSource>`，泛型明確、
與 `DropdownButton<DatabaseBrowserSource>` 井水不犯河水。「兩種型別如何共存於
一個選擇器」這個問題**沒有被解決，是被取消了**——最好的一種消失方式。

連帶結果：`database_tab.dart` 從「必須修改」變成「一個字不用改」（AC-35）。

> **U-5 結案**：不需要任何共同上層抽象。`KeyValueBrowserSource` 與
> `DatabaseBrowserSource` 保持完全獨立，兩者都不新增 supertype。

<details>
<summary>歷史紀錄：rev.1 的原始風險描述（保留，說明為何日後不該又想合併）</summary>

實查結果（`database_tab.dart`）：現有 `DropdownButton<DatabaseBrowserSource>` 的
泛型參數就是 `DatabaseBrowserSource`，且 `_selectedSource` 欄位型別亦然。
`initState` 直接 `widget.inspector.databaseSources.first`，body 依 `_selectedSource is
OperationLogSource` 分岔。

要讓同一個選擇器同時列出 KV source，必然觸及這段既有程式。

風險點在於：把兩個不共享任何方法的介面塞進同一個 dropdown，很容易長出
`if (selected is KeyValueBrowserSource) ... else ...` 這種型別判斷分岔。
一旦選擇器內部開始用 `is` 判斷型別來決定渲染什麼，就是資料結構設計失敗的訊號。

原未決事項 U-5：是否引入共同上層抽象（共有 `name` 的 marker interface）讓選擇器
不需 `is` 判斷——但那是為單一使用場景發明抽象。

</details>

> 🔴 **給未來的自己**：若日後有人提議「把 Storage 併回 Database，共用一個 dropdown」，
> 計畫文件 §2 保留了槍斃該方案的實查證據（`database_tab_test.dart` L114/121/151
> 把 `DropdownButton<DatabaseBrowserSource>` 的泛型參數寫死在斷言裡）。
> 合併會直接弄紅那三條既有測試。**證據仍然有效，不要重新調查。**

### R-5（中）SecureStorage 的非同步與平台差異

介面全數回傳 `Future`，已涵蓋 `FlutterSecureStorage` 的非同步特性。但兩點需注意：

- SecureStorage 在部分平台可能不支援列舉全部 key（`readAll` 的支援度依平台而異）。
  介面契約應允許實作回傳部分結果或拋例外，UI 端以 AC-9 的錯誤處理承接。
- `KeyValueEntry.type` 對 SecureStorage 恆為 `String`（其儲存模型本就只有字串）。
  AC-18 的型別驗證在此情境等於不做任何限制，這是正確行為，非缺陷。

> **誠實標註**：我未實查 `flutter_secure_storage` 各平台的 `readAll` 支援矩陣。
> 上述為介面設計上的保守假設，README 範例撰寫時應驗證。

### R-6（低）UI 測試需要 fake source

驗收條件中的寫入相關項（AC-13 ~ AC-29）都需要「確認介面方法是否被呼叫、以什麼參數」。
這需要一個可記錄呼叫的 fake `KeyValueBrowserSource`。介面小（五個成員）、無相依，
手寫 fake 成本低，不需引入 mock 套件。

> **誠實標註**：我未實查 `test/` 現有是否有可沿用的 fake `DatabaseBrowserSource`。
> 若有，形狀可鏡射；STAGE 0b 應先確認。

---

## 影響範圍（初判，供 STAGE 0b 細化）

- **新增**：`lib/src/models/key_value_browser_source.dart`（介面 + `KeyValueEntry`）
- **新增**：KV 瀏覽 / 編輯 UI（檔案位置由 STAGE 0b 決定）
- **修改**：`lib/src/core/flutter_inspector.dart`（建構參數 + getter + 註冊方法；
  另需更新 `:363-365` 的 `openDashboard` doc comment，補上 Storage tab 的說明）
- **修改**：`lib/src/ui/dashboard/dashboard_modal.dart`（rev.2 新增；見下方接點清單）
- **修改**：套件 export 檔（新介面對外公開）
- **修改**：README（兩套接線範例）
- **不修改**：`lib/src/ui/dashboard/tabs/database_tab.dart`（rev.2：獨立 tab 後零接觸，AC-35）
- **不修改**：`lib/src/ui/widgets/key_value_table.dart`（R-1 方案 B）
- **不新增**：任何 `pubspec.yaml` 相依（AC-3）

#### `dashboard_modal.dart` 的接點（已逐行查證，2026-08-21）

| 行號 | 現況 | 需要什麼 |
|------|------|---------|
| `:44` | `final tabCount = hasCustomTab ? 5 : 4;` | 改為依 `hasCustomTab` + `hasStorageTab` 兩個布林計算 |
| `:47` | `length: tabCount` | 無需改（吃上面的值） |
| `:48` | `initialIndex.clamp(0, tabCount - 1)` | 無需改（AC-34 自動滿足） |
| `:156` | `isScrollable: true` | **無需改——已經是 true** |
| `:158-168` | `tabs: [...]` 清單 | 在 Database 之後、custom 之前插入 `if (hasStorageTab) const Tab(text: 'Storage')` |
| `:72-79` | `TabBarView children: [...]` | 同位置插入條件性子項，**順序必須與 tabs 清單一致** |

> ⚠️ `tabs` 與 `children` 兩份清單的順序必須手動保持同步，這是此檔案既有的
> 結構性弱點（custom tab 已經有同樣的問題）。**本功能不重構它**（YAGNI），
> 但實作時兩處必須一起改，漏一處會導致 tab 標題與內容錯位。

---

## 主要不確定處彙總

| 編號 | 未決事項 | 狀態 |
|------|---------|------|
| U-1 | Database Tab 是否更名為 Storage Tab | ✅ **結案（rev.2）**：兩者都不動，KV 另開 Storage tab |
| U-2 | 寫入失敗是否記 error log | STAGE 0b |
| U-3 | 既有 `redactSensitiveData` 是否會波及 KV 值顯示 | STAGE 0b（需實查） |
| U-4 | 稽核 log 是否包含舊值 | STAGE 0b |
| U-5 | 兩類 source 共存於選擇器的資料結構設計 | ✅ **取消（rev.2）**：問題隨獨立 tab 消失 |
| R-1 | `KeyValueTable` 擴充 vs 新寫 | 已定案：新寫（方案 B） |
| R-2 | 搜尋欄新寫第三份 vs 先抽共用 | 已定案：新寫第三份（方案 A） |
| **新** | Storage tab 是否條件性顯示 | ✅ **定案（rev.2）**：是，比照 `customTab` 慣例（AC-30），且這是既有 5 處 tab 數斷言不變紅的前提 |
