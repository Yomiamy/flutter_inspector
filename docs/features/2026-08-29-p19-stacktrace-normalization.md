# §P19 StackTrace 非同步鏈正規化 (StackTrace Async Gap Normalization)

## What & Why (背景與目的)
Flutter 拋出的 `StackTrace` 往往充斥大量框架內部的呼叫（如 `package:flutter/src/widgets/framework.dart`、`dart:async`、`dart:isolate` 等），往往長達數十行。在發生非同步錯誤時，堆疊更會被 `<asynchronous suspension>` 切割，使得真正出錯的業務程式碼（宿主 App 的代碼）被淹沒在框架噪聲中。開發者與 QA 排查時難以一眼看出出錯的原始位置。
本提案旨在透過正規化 StackTrace，自動折疊連續的框架內部呼叫（Frame Folding），清楚標示非同步跳轉點（Async Gap Demangling），並預設突出顯示業務邏輯層的程式碼。藉此大幅降低視覺噪聲，提升從 `LogDetailView` 獲取排查線索的效率。

## User Story (使用者故事)
- 作為開發者或 QA，當我在 `LogDetailView` 中檢視包含 StackTrace 的 Error Log 時，我希望預設看到的是「去噪後」的精簡堆疊（Concise Stack），將長篇大論的 Flutter / Dart 內部呼叫折疊起來，讓我一眼看見我自己 App 內的程式碼行。
- 作為開發者，當遇到非同步錯誤時，我希望堆疊中的 `<asynchronous suspension>` 能被明確標示為非同步跳轉鏈，幫助我理解跨事件迴圈的錯誤脈絡。
- 作為開發者，我希望保留查看與複製「原始堆疊 (Raw Stack)」的能力，以便在特殊情況下調查框架內部的崩潰。
- 作為 QA，當我一鍵分享或匯出診斷報告時，我希望能選擇帶出更容易閱讀的精簡堆疊資訊，讓工程師能更快定位問題。

## Acceptance Criteria (驗收條件)
1. **框架噪聲折疊 (Frame Folding)**：
   - 當 `LogDetailView` 顯示 `StackTrace` 時，預設模式下，連續屬於 `package:flutter/*` 或 `dart:*` 的 frame 會被折疊成單行提示（例如 `[... 12 frames of framework internals]`）。
   - 未被折疊的業務程式碼（例如 `package:宿主App/*`）必須被清晰保留。
2. **非同步鏈拼接 (Async Gap Demangling)**：
   - 原始堆疊中的 `<asynchronous suspension>` 應被轉換或標示為直觀的非同步中斷點。
3. **視圖切換與複製功能**：
   - `LogDetailView` 的 Stack Trace 區塊需提供一個輕量的切換機制（例如 Toggle 開關或按鈕），讓使用者能自由在「精簡視圖 (Concise)」與「原始視圖 (Raw)」間切換。
   - `LogDetailView` 既有的 Share 選單必須支援分享/複製目前的精簡堆疊版本或完整的原始堆疊版本。
4. **資料不滅原則**：
   - `LogEntry.stackTrace` 必須始終保留原始字串。正規化與折疊僅在 Presentation 層（UI 與字串格式化工具）進行，絕不修改資料層。

## Scope & Boundaries (範圍與邊界)
- **Scope**:
  - 擴充 `lib/src/utils/log_formatters.dart`，加入將字串形式的 StackTrace 解析為精簡堆疊格式的純函式邏輯。
  - 更新 `lib/src/ui/dashboard/tabs/console/log_detail_view.dart` 的 `_stackTraceSection` 實作。
  - 可評估引入 Dart 官方維護之 `stack_trace` 套件作為輕量相依，或撰寫輕量的 Regex 剖析器。
- **Out of Scope**:
  - **IDE 跳轉整合**：我們只做字串展示與文字選取，不處理與 IDE 的深層連結協定串接（例如 `idea://` / `vscode://`）。
  - **自動反混淆 (Deobfuscation)**：若 App 發布時已開啟混淆，我們只展示混淆後的堆疊，不在此功能內處理 mapping file 的解析。
