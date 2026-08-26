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
> ⚠️ **已知限制：MCP 呼叫無法逐次帶 `--print-timeout`。** 逾時只能靠 server 層的環境變數（`gemini-mcp-tool` 側的 `GEMINI_MCP_TIMEOUT` / `AGY_PRINT_TIMEOUT`，預設為數十分鐘等級）統一設定，**單次派發無法調整**，且預設值遠長於一般任務——實務上等同沒有有效的即時保護，卡住仍多半得人為中斷。派發前把任務拆到合理粒度；若要縮短，須在啟動 MCP server 的環境設定，不在派發端。
