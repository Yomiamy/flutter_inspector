Resolves #148

## 目的 (Purpose)
解決 Flutter 拋出非同步例外時，StackTrace 充斥內部框架呼叫且被 `<asynchronous suspension>` 分割，導致排查困難的問題。

## 變更摘要 (Changes)
1. **新增 `normalizeStackTrace` 函式** (`log_formatters.dart`)：
   - 自動將連續的 `package:flutter/*` 或 `dart:*` 呼叫折疊。
   - 將 `<asynchronous suspension>` 轉換為清晰的 `<-- async gap -->` 標示。
2. **擴充 `DetailSection`** (`detail_section.dart`)：
   - 支援傳入 `trailing` 參數，以便在標題列放入擴充操作按鈕。
3. **升級 `LogDetailView`** (`log_detail_view.dart`)：
   - 轉為 `StatefulWidget` 並加入「精簡 / 原始」視圖的切換按鈕。
   - 擴充右上角的 Share 選單，提供複製與分享的獨立「精簡」與「原始」選項。
4. **修正測試** (`log_detail_view_test.dart`)：
   - 調整測試斷言以匹配新的按鈕文案 (Copy concise, Copy raw 等)。

## 安全性與邊界 (Safety)
- 底層 `LogEntry.stackTrace` 維持不變 (Immutable)。
- 未引入額外的第三方套件，保持模組輕量化。
