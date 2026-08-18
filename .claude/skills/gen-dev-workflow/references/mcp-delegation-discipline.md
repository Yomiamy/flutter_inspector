# MCP 委派紀律與底層機制

> **委派後端：`gemini-mcp-tool`（MCP 工具 `mcp__gemini-cli__ask-gemini`）。** brancher、implementer、publisher 透過此 MCP 工具委派。
> 需求：`gemini-cli` MCP server 已在 Claude Code 設定中啟用（`npx -y gemini-mcp-tool@1.1.8`，鎖定版本避免 rug-pull；升級前先確認 `npm view gemini-mcp-tool version` 並人工審查再調整）。
> MCP 不可用時各 agent 會自動退回 Fallback 模式，功能仍可運作但不會委派。
>
> **為何不是 `agy -p`：** 底層後端相同（`gemini-mcp-tool` 內部就是走 antigravity-cli），但 **`agy -p` headless 路徑實際不可用**——不吃 stdin、權限會卡死，委派一律落到 fallback。MCP 路徑則實測可寫檔、可跑 shell、可 `git commit`，是同一個後端唯一能真正委派的傳輸層。
>
> 🔴 **三條委派紀律（每次派發都適用）：**
> 1. **工作目錄寫死在 prompt 裡**——MCP 呼叫無法指定 cwd，不寫絕對路徑，子進程可能在主 repo 而非 worktree 動手。
> 2. **跨出工作目錄一律先問**——派發 prompt 必須明令：需要存取／修改該目錄以外的檔案時，停止並回報，不自行動手。
> 3. **回報不等於事實**——子進程說「已完成、已 commit」是宣稱。驗收一律親自跑 `git log` / `git status` / 測試確認。
>
> ⚠️ **已知限制：MCP 呼叫無法帶 `--print-timeout`。** 長任務沒有逾時控制，卡住只能人為中斷——派發前把任務拆到合理粒度。

> **多 workflow 並行：** 同一 repo 可同時跑多個獨立 workflow（多個終端 / 多個 session）。STAGE 1 起隔離 key 是**獨立 worktree**（沿用 `ticket-id-dev-prep` 規則建立）——每個 workflow 跑在自己的 worktree 目錄裡，state 檔天然分開存放，彼此零衝突，不需要任何鎖或中央索引。唯一需要額外處理的窗口是「兩個流程都還在 STAGE 0a/0b（尚無 worktree，仍在原 repo 目錄）」，靠 **workflow-id** 持久化區分（見 `references/state-machine.md`）。

> **Claude Workflow 編排（可選加速層）。** 本流程內**特定的並行、唯讀或路徑不重疊、且該段落內部不需要問使用者**的環節，可改用 Claude `Workflow` 工具（JS 腳本 fan-out 多 subagent）執行，取代逐個 `Task(...)` 串接。適用點只有三處：**STAGE 0a 雙線 context 收集**、**STAGE 2 同批獨立任務**、**STAGE 3 多 angle 對抗式審查**（範例與鐵則見 `references/workflow-parallel.md`）。
>
> **硬性邊界（違反即破壞流程，絕不可越界）：**
> - **絕不**把整條 orchestrator 包成單一 Workflow 腳本——Workflow 背景執行、跑完才回，中途無法暫停問人，會直接摧毀本流程 7 個人在迴圈中的暫停確認點。
> - Workflow 只用於**單一段落內部**的 fan-out，**暫停點永遠由主對話掌控**，落在任何 Workflow 呼叫的外面。一個 Workflow 呼叫 = 一段不可中斷的並行，跑完回到主對話才暫停。
> - **前置條件：** 使用者需明確 opt-in 多 agent 編排（說「ultracode」、「用 workflow」、「多 agent」或類似）。未 opt-in 時，這三處一律退回原本的 `Task(...)` / 序列作法，功能完全相同，只是不 fan-out。
> - state 檔、model 策略、委派規則**完全不變**——Workflow 只換「並行執行的載體」，不換流程語意。
