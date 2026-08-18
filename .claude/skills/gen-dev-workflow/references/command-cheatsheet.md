# 執行方式與跳入階段指令 (Command Cheatsheet)

## 啟動完整流程
```
使用者：幫我做 <需求描述>

你：好，開始執行開發流程。（effort 依「推論等級表」明確帶入，`xhigh` 的 400 風險註記見 `references/delegation-and-parallel.md`）
    Task("planner", "規劃 <需求描述>，產出 plan 文件", effort: "xhigh")
    → [等 planner 完成] → 展示計畫摘要 → 暫停確認
    → Skill("gen-gh-issue") 依計畫產出 Issue body（五區段 zh-tw）
    → Task("brancher", "用上述 Issue body 執行 <plan 路徑>", effort: "high")
    → Task("implementer", "執行 <plan 路徑>", effort: "max")
    → Task("reviewer", "審查 <branch-name>", effort: "xhigh")
    → [若不通過] Task("implementer", "修正以下問題：<reviewer 回報>", effort: "max")
    → Task("publisher", "用 gen-pr skill 產 PR 描述，發布 <branch-name>", effort: "high")
    → 暫停確認 → 完成
```

## 從既有 issue id 啟動（跳過 STAGE 0a/0b）
```
使用者：開發 issue #54

你：好，直接進 STAGE 1。（effort 依「推論等級表」明確帶入）
    Task("brancher", "解析 issue #54 內容為實作 brief，依 ticket-id-dev-prep 規則
                       決定 prefix/slug，建立 worktree + branch", effort: "high")
    → [等 brancher 完成] → 展示解析後的 brief + branch/worktree 名稱 → 暫停確認
    → cd 進新 worktree
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
| `/gen-dev-workflow batch "<A>" "<B>"` | 批次佇列：多項各自獨立 worktree/branch/PR 依序執行 |
| `繼續` ／ `繼續上次` | 接續本 session 或當前 branch 的未完成流程 |
| `繼續批次` | `/clear` 後於新 session 接續批次的下一項 |
| `停止批次` | 中止批次（只刪佇列檔，branch/PR/worktree 保留） |
| `PR #<id> 合併了，清理 worktree` | STAGE 6：同步文件 → commit → 移除 worktree（branch 保留） |

## 跳入特定階段 (`mode: jump`)

所有跳入指令都以 `mode: "jump"` 寫入狀態檔。每條呼叫都須依「推論等級表」明確帶 `effort` 參數。

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
