# 功能規格：Console 搜尋／過濾 + 點擊清過濾捲回主時間軸（§D1 + §P5）

> 來源：`docs/brainstorm/2026-09-04-features-brainstorm.md` §D1（L268）+ §P5（L474）
> Tier 3 · 檢索既有資訊 ｜ Effort: med ｜ 排查價值：⭐⭐⭐

## What：這個功能是什麼

在 ConsoleTab 的四源混合時間軸（log / network / nav / db）上，補上 NetworkTab 已有而
Console 缺的檢索能力，**並且讓檢索完能回到完整脈絡**：

1. **搜尋欄** — 關鍵字比對 entry 的文字內容
2. **LogLevel 過濾** — verbose / debug / info / warning / error 多選 FilterChip
3. **errors-only 快捷** — 一鍵等價於「warning + error level ＋ 失敗的網路請求」
4. **點擊結果跳回主時間軸** — 點搜尋結果 → 清掉過濾 → 捲到該筆位置

## Why：為什麼是這四項綁在一起

### 為什麼不能只做過濾（§D1 單獨）

文件 2026-07-24 的重新定性講得很清楚：

> **過濾是點查詢（你已知道要找什麼），排查是鏈推斷（你不知道要找什麼）。**

單獨的過濾**主動切斷因果鏈** —— 搜「timeout」剩 3 筆 error，前後的 API 呼叫與路由跳轉
全被濾掉。但排查要問的不是「這筆 error 長什麼樣」，是「為什麼走到這裡」。

### 為什麼不能只做跳轉（§P5 單獨）

§P5 原案只能跳到「最新一筆 error」，跳不到「我搜到的那一筆」。

### 合起來才閉環

```text
搜到 → 點擊 → 清過濾 + 捲到該位置 → 站回完整四源時間軸看前後
```

這也正是 §D3（±5s 側欄）想解決卻解錯的同一個問題 —— 側欄用固定時間窗**猜**相關範圍，
跳回主時間軸則讓使用者自己決定要往前看多遠。

## 使用者故事

**US-1**：QA 回報「結帳頁偶爾轉圈不會停」。開發者開 Console，搜 `checkout`，
看到 3 筆相關請求，點最後一筆 → 過濾清空、時間軸捲到該筆 → 看見它前面
一筆 `NavigatorEntry` push 了兩次，確認是重複導航造成重複請求。

**US-2**：開發者只想快速掃有沒有錯誤，點 `⚡ errors-only`，
四源裡的 error log 與失敗網路請求一次到齊，不必逐一切 source chip。

**US-3**：開發者知道問題在 log 而非網路，點 `warning` + `error` 兩個 level chip，
info/debug 的雜訊消失，但網路與導航事件仍在（level 過濾只作用於 log 類 entry）。

## 驗收條件

| # | 條件 |
|---|------|
| AC-1 | 搜尋欄輸入關鍵字後，只顯示文字內容命中的 entry；清空還原全部 |
| AC-2 | 搜尋比對**四種 entry 各自的可讀欄位**（log: message/stackTrace；network: url/method/status；nav: routeName/displayName；db: tableName/operation） |
| AC-3 | LogLevel chip 多選，**只作用於 LogEntry**；未選任何 level 等同全選 |
| AC-4 | LogLevel 過濾啟用時，非 log 類 entry（network/nav/db）**不被濾掉** |
| AC-5 | `⚡ errors-only` 是**單一條件內部的聯集**（唯一的 OR）：`LogEntry` 取 `level ∈ {warning, error}` **OR** `NetworkEntry` 取 `isFailed == true`。兩者型別互斥，寫成 AND 結果恆為空 —— 這是本規格唯一的聯集，不可與 AC-6 的條件間交集混淆 |
| AC-5a | `⚡ errors-only` 啟用時，`NavigatorEntry` 與 `DatabaseEntry` **一律濾掉**（它們沒有「錯誤」語意，不適用 AC-4 的放行例外） |
| AC-6 | 搜尋 × source 過濾 × level(或 errors-only) 三者**正交疊加**：**條件與條件之間一律取交集（AND）**，任一條件為空即該條件不設限。⚠️ 唯一的聯集發生在 AC-5 的 errors-only **內部**（跨型別 OR），不影響本條的條件間 AND |
| AC-6a | **level + 搜尋**：選 `error` chip ＋ 搜 `cart` → `LogEntry` 需同時滿足 `level==error` 且文字含 `cart`；`NetworkEntry`/`NavigatorEntry`/`DatabaseEntry` **只需**文字含 `cart`（依 AC-4，level 不施加於非 log entry）。即：成功的 `GET /api/cart` **仍然顯示** |
| AC-6b | **level + source**：選 `error` chip ＋ source 切到 `Network` → 結果為所有 network entry（level 對其不設限），不是空清單 |
| AC-6c | **搜尋 + source**：搜 `cart` ＋ source 切到 `Log` → 只有 message/stackTrace 含 `cart` 的 log |
| AC-6d | **三者同時**：`error` chip ＋ 搜 `cart` ＋ source 切到 `Log` → 只有 `level==error` 且文字含 `cart` 的 log（此時 AC-4 的例外不生效，因為 source 已排除非 log 型別） |
| AC-6e | **errors-only + 搜尋**：`⚡ errors-only` ＋ 搜 `cart` → 先取 AC-5 的內層聯集（warning/error log ∪ isFailed 請求），**再與**搜尋條件取交集。即 `(errorsOnly(e)) && (keyword(e))`，關鍵字套在聯集之後、不是只套其中一支 |
| AC-7 | 過濾有作用時點擊任一 entry → 清空所有過濾條件 + 時間軸捲動到該 entry 位置 |
| AC-8 | 過濾無作用（未過濾）時點擊 entry → 維持既有行為（開 detail view），不觸發跳轉 |
| AC-9 | 過濾後無命中時顯示 `No matches`（對齊 NetworkTab 既有文案） |
| AC-10 | 既有功能零回歸：source chip、📌 Bookmarks、refresh、clear、error 底色高亮 |

## 範圍邊界

### 在範圍內

- `ConsoleFilter` + `applyConsoleFilter()` 純函式（鏡射既有 `NetworkFilter` / `applyNetworkFilter`）
- ConsoleTab 的搜尋欄、LogLevel chip、errors-only chip UI
- 點擊跳轉：清過濾 + `ScrollController.animateTo`
- 對應單元測試（過濾邏輯）與 widget 測試（跳轉行為）

### 明確不在範圍內

| 不做 | 理由 |
|------|------|
| 提取 `network_tab.dart` 的私有 `_SearchBar` 為共用元件 | 跨檔重構會擴大 diff 與回歸面；Console 先自建一份，日後兩邊都穩定再談收斂 |
| 為 `TimestampedEntry` 增加 `searchableText` 等新介面成員 | 該介面刻意鎖為窄契約（`abstract interface class`，註解明寫「存在的唯一理由是提供排序鍵」），不為過濾污染它 |
| §P5 原案的「⬆ Jump to Latest Error」浮動按鈕 | 合併後由「搜尋 → 點擊跳轉」覆蓋；獨立 FAB 會與點擊跳轉語意重疊 |
| 捲動位置的持久化／錨定 entry identity | Console 是持續有新事件湧入的流，錨定機制成本高（見下方風險），本次跳轉為一次性 |
| DatabaseTab 的搜尋過濾（§D4） | 獨立項目，寫入路徑不重疊，不併入 |

## 已知風險與設計約束

### R-1：搜尋語意必須是「過濾」，不是「捲動」

既有 `NetworkTab` 把 `applyNetworkFilter()` 結果直接餵 `ListView.builder`，
不匹配的 entry 根本不建立，全程無 `ScrollController`。Console 必須沿用**過濾語意**。

捲動語意在此會壞掉：Console 是持續有新事件湧入的混合流，捲到第 300 筆後新事件進來
會把目標推走，要修就得引入「錨定 entry identity + 重算 index」的狀態管理 ——
為一個搜尋框長出一整套機制。

**但 AC-7 的跳轉需要 `ScrollController`。** 兩者不衝突：`ScrollController` 只在
「點擊結果」這個一次性動作使用（`animateTo` 後即結束），不用於維持捲動狀態。

### R-2：`entriesAtLevel()` 接不上，不可重用

`LogInspector.entriesAtLevel()` 回傳 `List<LogEntry>`，而 ConsoleTab 渲染的是
`mergedTimeline` 的四源混合流 `List<TimestampedEntry>` —— 型別接不上。
需另寫吃 `List<TimestampedEntry>` 的過濾函式。

（`entriesAtLevel()` 現有 2 處呼叫都在 `dashboard_modal.dart` 算 badge，不受影響。）

### R-3：`InspectorSearchBar` 不存在

文件早期估計說「元件已存在只需接入」是錯的。`network_tab.dart` 內是**私有的
`_SearchBar`**，跨檔不可見。本次在 console 側自建一份（見「不在範圍內」的理由）。

### R-4：level 過濾對非 log entry 的語意（AC-4 的由來）

`LogLevel` 只有 `LogEntry` 有。若把「未命中 level」直接判為過濾掉，
network/nav/db 三種 entry 會在使用者點任一 level chip 時**全部消失** ——
這會讓 level 過濾實質變成「只看 log」，與 source chip 功能重疊且違反正交性。

**正確語意**：level 約束只施加於 `LogEntry`，其餘型別不受 level 條件影響。

**與搜尋併用時最容易寫錯**（AC-6a 的由來）：選 `error` chip ＋ 搜 `cart` 時，
直覺會想成「找 cart 的錯誤」而把成功的 `GET /api/cart` 濾掉 —— 但那是**把 level
條件套到了 NetworkEntry 上**，違反本節語意，並讓 level chip 退化成 source chip。

正確做法是各條件獨立求值後取交集，level 條件在遇到非 `LogEntry` 時直接回 `true`：

```dart
// ── 外層：條件與條件之間一律 AND（AC-6）──
bool matches(TimestampedEntry entry) =>
    _matchesLevel(entry) && _matchesKeyword(entry);

// level 只約束 LogEntry，其餘型別一律放行
bool _matchesLevel(TimestampedEntry entry) {
  if (errorsOnly) return _matchesErrorsOnly(entry);  // errors-only 取代 level
  if (levels.isEmpty) return true;
  if (entry is! LogEntry) return true;   // ← AC-4 / AC-6a 的關鍵
  return levels.contains(entry.level);
}

// ── 內層：唯一的 OR（AC-5）──
// 型別互斥，寫成 AND 恆為空；nav/db 無「錯誤」語意故一律濾掉（AC-5a）
bool _matchesErrorsOnly(TimestampedEntry entry) => switch (entry) {
  final LogEntry e =>
    e.level == LogLevel.warning || e.level == LogLevel.error,
  final NetworkEntry e => e.isFailed,   // 重用 §P7 的收斂判定（R-5）
  _ => false,
};
```

**兩層結構一句話**：條件之間 AND，errors-only 內部 OR。搞混會得到兩種錯誤結果 ——
把內層寫成 AND → errors-only 永遠空清單；把外層寫成 OR → 搜尋失效（任一條件命中就顯示）。

### R-5：`errors-only` 必須重用 `NetworkEntry.isFailed`

§P7 的教訓（同一份文件記載）：「網路請求是否失敗」的判定曾在三個檔案各手寫一份
且已漂移、各漏一種失敗類型，最後收斂成 `NetworkEntry.isFailed`。

本次 errors-only 的網路側判定**一律呼叫 `entry.isFailed`**，不得重寫等價邏輯。

## 影響範圍

| 檔案 | 動作 |
|------|------|
| `lib/src/utils/console_utils.dart` | **新增** — `ConsoleFilter` + `applyConsoleFilter()` |
| `lib/src/ui/dashboard/tabs/console_tab.dart` | 修改 — 搜尋欄、level chips、errors-only chip、ScrollController、點擊跳轉 |
| `test/utils/console_utils_test.dart` | **新增** — 過濾邏輯單元測試 |
| `test/ui/tabs/console_tab_test.dart` | 新增或擴充 — 跳轉與正交疊加的 widget 測試 |

**零改動**：`TimestampedEntry`（窄契約不動）、`LogInspector`、`network_tab.dart`、
`NetworkFilter`、四個 model 檔。
