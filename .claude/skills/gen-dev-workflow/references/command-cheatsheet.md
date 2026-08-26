# 執行方式與跳入階段指令 (Command Cheatsheet)

## 啟動完整流程
```text
使用者：幫我做 <需求描述>

你：好，開始執行開發流程。（effort 依「推論等級表」明確帶入，`xhigh` 的 400 風險註記見 `references/delegation-and-parallel.md`）
    # STAGE 0a：功能規格（What & Why）
    Task("planner", "為 <需求描述> 撰寫功能規格", effort: "xhigh")
    → 產出 docs/features/YYYY-MM-DD-<feature>.md → 展示 → ⏸ 暫停確認
    # STAGE 0b：實作計畫（How）——兩階段不可合併，0a 未確認不得進 0b
    → Task("planner", "依已確認的規格產出實作計畫", effort: "xhigh")
    → 產出 docs/plans/YYYY-MM-DD-<feature>.md → 展示 → ⏸ 暫停確認
    # STAGE 1：先展示命名，確認後才建立
    → Skill("gen-gh-issue") 依計畫產出 Issue body（五區段 zh-tw）
    → Task("brancher", "產出分支/worktree 名稱草稿，先不要建立", effort: "high")
    → 展示 Issue 標題/內容 + 分支/worktree 名稱 → ⏸ 暫停確認
    → 確認後才執行 gh issue create 與 worktree/branch 建立
    → Task("implementer", "執行 <plan 路徑>", effort: "max")
    → Task("reviewer", "審查 <branch-name>", effort: "xhigh")
    → [若不通過] Task("implementer", "修正以下問題：<reviewer 回報>", effort: "max")
    → Task("publisher", "用 gen-pr skill 產 PR 描述，發布 <branch-name>", effort: "high")
    → 暫停確認 → 完成
```

## 從既有 issue id 啟動（跳過 STAGE 0a/0b）
```text
使用者：開發 issue #54

你：好，直接進 STAGE 1。（effort 依「推論等級表」明確帶入）
    Task("brancher", "解析 issue #54 內容為實作 brief，依 ticket-id-dev-prep 規則
                       決定 prefix/slug，先只產出名稱草稿不要建立", effort: "high")
    → [等 brancher 完成] → 展示解析後的 brief + branch/worktree 名稱 → ⏸ 暫停確認
    → 確認後才建立 worktree + branch → cd 進新 worktree
    → Task("implementer", "依 issue brief 執行實作", effort: "max")
    → Task("reviewer", "審查 <branch-name>", effort: "xhigh")
    → [若不通過] Task("implementer", "修正以下問題：<reviewer 回報>", effort: "max")
    → Task("publisher", "用 gen-pr skill 產 PR 描述，發布 <branch-name>", effort: "high")
    → 暫停確認 → 完成
```

## 組合速查與續接/管理型指令

| Command | Action |
|---------|--------|
| `/gen-dev-workflow quick <描述>` | 小修正快速通道（限 ≤3 檔），不建 worktree |
| `幫我做 <描述>` | 預設新功能完整流程，全程每個關卡暫停確認 |
| `幫我做 <描述> --pause-level balanced` | 完整流程，只在重要節點暫停，減少打斷 |
| `/gen-dev-workflow batch "<A>" "<B>" --pause-level balanced` | 批次佇列：多項各自獨立 worktree/branch/PR 依序執行。**建議帶 `balanced`**——批次的意義是減少打斷，每項若還停五次就失去意義（不建議 `autonomous`，那會讓每個 PR 都不經過目就送出） |
| `繼續` ／ `繼續上次` | 接續本 session 或當前 branch 的未完成流程 |
| `繼續批次` | `/clear` 後於新 session 接續批次的下一項 |
| `停止批次` | 中止批次（只刪佇列檔，branch/PR/worktree 保留） |
| **quick 做到一半發現超出範圍** | **沒有指令**——由 Claude 判斷後停下提議，或你直接說「這超出範圍了，走完整流程」。作法是收工重來，不是接續升級（見 [`execution-modes.md`](execution-modes.md) 的「超出範圍時」） |
| `PR #<id> 合併了，清理 worktree` | STAGE 6：**先推進狀態**（見下方「狀態前置步驟」）→ 同步文件 → commit → 移除 worktree（branch 保留） |

## 跳入特定階段 (`mode: jump`)

所有跳入指令都以 `mode: "jump"` 寫入狀態檔。每條呼叫都須依「推論等級表」明確帶 `effort` 參數。

🔴 **每條跳入指令的第一步都是推進狀態，不可跳過。** 本表只列觸發語與動作；動手前先跑下方「狀態前置步驟」的對應指令，否則該次執行不會留在狀態機的軌跡上。

| Command | Stage | Action |
|---------|-------|--------|
| `/gen-dev-workflow spec <description>` | 0a | 重新規劃功能規格 |
| `/gen-dev-workflow plan <spec-path>` | 0b | 重新產出實作計畫 |
| `/gen-dev-workflow branch <issue>` | 1 | 只需要建 Issue + Worktree |
| `/gen-dev-workflow implement <plan-path>` | 2 | 繼續實作 |
| `/gen-dev-workflow code-review <branch>` | 3 | 執行代碼審查 |
| `/gen-dev-workflow publish <branch>` | 4 | 建立 PR |
| `/gen-dev-workflow review #<PR>` | 5 | 處理 PR review 意見 |
| `/gen-dev-workflow cleanup <branch>` | 6 | PR 合併後清理 worktree（branch 保留）|

### 狀態前置步驟（STAGE 5 / 6 獨立入口）

兩種入口擇一，依當前工作區有無 state 檔決定：

```bash
# 既有工作區已存在 state 檔
wf-state.sh advance <state_file> 5 --confirmed     # STAGE 5
wf-state.sh advance <state_file> 6 --confirmed     # STAGE 6

# 新對話／獨立進入（尚無 state 檔）
wf-state.sh init --mode jump --stage 5 --branch <branch> --set pr=<PR>
wf-state.sh init --mode jump --stage 6 --branch <branch>
```text

跑完該 stage 的工作後**收尾也要記**：`wf-state.sh stage-done <檔> 5`（或 `6`）。

> 🔴 **STAGE 6 沒有 hook 兜底，文件是唯一防線。**
> `wf-guard-stage-check.sh` 只攔 `responder` agent 的派發（`PreToolUse` / `matcher: Agent`），所以 STAGE 5 漏跑前置步驟會被擋下。但 STAGE 6 全程在主對話呼叫 skill（`gen-sync-docs-by-branchs` → `gen-commit` → `worktree-close-cleanup`），**不派發任何 agent，hook 永遠不會觸發**。
> 漏跑的後果不是報錯，是靜默：state 檔停在 `4`，`4→6` 這條合法轉移從未被記錄，稽核軌跡就此斷掉——而且直到 state 檔被刪都不會有人發現。
