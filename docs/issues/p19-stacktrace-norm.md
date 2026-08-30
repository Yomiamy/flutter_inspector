## 問題描述 (Problem)
在 Flutter 應用中發生非同步例外時，拋出的 StackTrace 會充斥大量 `package:flutter/*` 與 `dart:*` 的內部底層呼叫，且因為 `async/await` 的特性，會被 `<asynchronous suspension>` 分割得支離破碎。這讓排查者極難一眼在 `LogDetailView` 中定位到真實出錯的業務邏輯程式碼。

## 根本原因（已驗證）(Root cause - verified)
Flutter 與 Dart 在遇到非同步錯誤時，原始的 StackTrace 字串會詳實記錄所有 Frame，但並未提供針對業務邏輯的去噪 (De-noising) 與框架折疊機制。目前 `LogEntry` 與 `LogDetailView` 僅直接顯示未處理的原始字串。

## 修復方案 (Fix)
- **A** `lib/src/utils/log_formatters.dart`：新增 `normalizeStackTrace` 純函式進行折疊 (Frame Folding) 與標記 (Async Gap Demangling)，並擴充 `buildLogPlainText` 支援精簡模式參數。
- **B** `lib/src/ui/widgets/detail_section.dart`：為標題列加入 `trailing` 參數以支援後續的切換按鈕排版。
- **C** `lib/src/ui/dashboard/tabs/console/log_detail_view.dart`：升級為 `StatefulWidget`，實作「原始/精簡」的 StackTrace 視圖切換，並將對應複製與分享選項整合至 Share 選單。

## 排除範圍 (Out of scope)
- 與 IDE 的深層跳轉串接（如 `vscode://` 等協定）。
- 發布環境的混淆堆疊 (Obfuscated StackTrace) 自動反混淆處理。

## 驗證方式 (Verification)
- 進入 `LogDetailView` 查看含有錯誤的 Log，確認預設顯示折疊後的 StackTrace，且清楚標示 `<-- async gap -->`。
- 點擊「精簡/原始」切換按鈕，確認視圖能正確切換，且底層資料結構字串不被竄改。
- 透過 Share 選單複製/分享精簡版本，確認輸出內容與畫面相符。
