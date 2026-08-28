# §P19 StackTrace 非同步鏈正規化 實作計畫

## Data Structures & Logic (資料結構與邏輯)

本功能著重於 Presentation 層的字串處理與 UI 狀態管理，不改變資料層 `LogEntry` 儲存的原始堆疊字串。

1. **自訂輕量剖析器 (`normalizeStackTrace`)**：
   - 考量到避免引入不必要的套件依賴，我們實作一個輕量的純文字剖析函式，針對 `StackTrace` 字串以換行符號 (`\n`) 切割。
   - **框架噪聲折疊 (Frame Folding)**：逐行檢查，若該行包含 `package:flutter/` 或 `dart:`，則視為框架內部呼叫並累加計數。當遇到業務程式碼（不包含上述字串）時，將前面累加的框架行數折疊輸出為 `  [... N frames of framework internals]`，接著輸出該行業務程式碼。
   - **非同步鏈拼接 (Async Gap Demangling)**：遇到 `<asynchronous suspension>` 時，同樣先清空並輸出先前的折疊計數，並將其替換為更直觀的標示，例如 `  <-- async gap -->`。
2. **匯出格式化擴充 (`buildLogPlainText`)**：
   - 為 `buildLogPlainText` 增加 `bool isConcise = true` 參數。當 `isConcise` 為 `true` 且存在 stack trace 時，呼叫 `normalizeStackTrace` 進行去噪；若為 `false` 則輸出原始字串。

## File Modifications (檔案異動清單)

1. **`lib/src/utils/log_formatters.dart`**
   - 新增 `String normalizeStackTrace(String rawStack)` 純函式。
   - 修改 `buildLogPlainText` 的簽章與實作，加入 `isConcise` 判斷。

2. **`lib/src/ui/widgets/detail_section.dart`**
   - 為 `DetailSection` 增加 `Widget? trailing` 參數。
   - 在 `build` 方法中更新排版：若有傳入 `trailing`，則將 Title 與 Trailing 放置於 `Row` 中（例如利用 `MainAxisAlignment.spaceBetween` 排版）。

3. **`lib/src/ui/dashboard/tabs/console/log_detail_view.dart`**
   - 將 `LogDetailView` 從 `StatelessWidget` 重構為 `StatefulWidget`。
   - 引入狀態 `bool _isConcise = true`。
   - 在 `_stackTraceSection` 呼叫 `DetailSection` 時，傳入 `trailing` 參數（例如使用 `Switch` 或 `TextButton` 作為切換開關），並根據 `_isConcise` 的值來決定顯示 `normalizeStackTrace` 的結果或原始字串。
   - 擴充 `_ShareAction` enum 為：`copyConcise`、`copyRaw`、`shareConcise`、`shareRaw`，並更新分享選單 (PopupMenuButton) 提供對應的選項，在執行分享/複製時傳遞對應的 `isConcise` 旗標給 `buildLogPlainText`。

## Task Breakdown (任務拆分)

以下任務可指派給 STAGE 2 的實作者：

### Task 1: 實作核心正規化邏輯與匯出擴充
**修改檔案**：`lib/src/utils/log_formatters.dart`
- 撰寫 `normalizeStackTrace` 邏輯。
- 擴充 `buildLogPlainText` 支援精簡模式參數。
*(註：本任務為純邏輯層，無外部依賴，可與 Task 2 完全並行處理。)*

### Task 2: 基礎 UI 元件擴充
**修改檔案**：`lib/src/ui/widgets/detail_section.dart`
- 替 `DetailSection` 加入 `trailing` 屬性並更新 Title 區塊排版。
*(註：本任務僅修改共用 UI 元件，可與 Task 1 並行處理。)*

### Task 3: 實作 LogDetailView 視圖與互動
**修改檔案**：`lib/src/ui/dashboard/tabs/console/log_detail_view.dart`
**相依性**：需等待 Task 1 與 Task 2 完成。
- 重構為 `StatefulWidget` 並加入 `_isConcise` 狀態。
- 實作 StackTrace 區塊的切換按鈕。
- 擴充 AppBar 的分享選單，串接新的複製與分享動作。
