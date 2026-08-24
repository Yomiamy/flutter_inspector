# 獨立入口狀態機防護與 PreToolUse Hook 守衛實作計畫 (Gap 2.6)

依據 [`docs/features/2026-08-14-wf-standalone-entry-guard.md`](../features/2026-08-14-wf-standalone-entry-guard.md) 之需求規格制定。

---

## 1. 架構設計與資料流 (Architecture & Data Flow)

```text
[Claude Code / Antigravity]
           │
           │ 觸發工具: Agent / invoke_subagent (派發 responder)
           ▼
┌────────────────────────────────────────────────────────┐
│ PreToolUse Hook: wf-guard-stage-check.sh              │
│ 1. 檢查派發目標是否為 responder                        │
│    └─ 否 → exit 0 放行                                 │
│ 2. 獲取當前分支 $(git branch --show-current)           │
│ 3. 搜尋 .claude/workflow-state/<branch>.json 狀態檔     │
│    └─ 無匹配檔（非 workflow 分支） → exit 0 放行         │
│ 4. 檢查狀態檔 .stage                                   │
│    ├─ stage == "5" 或 "responder" → exit 0 放行         │
│    └─ stage != "5" → exit 1 阻擋並在 stderr 輸出修復命令 │
└────────────────────────────────────────────────────────┘
```

---

## 2. 檔案異動清單 (File Changes)

| 檔案路徑 | 類型 | 異動說明 |
| :--- | :---: | :--- |
| `.claude/skills/gen-dev-workflow/SKILL.md` | 修改 | STAGE 5/6 區塊明訂第一步推進狀態機之硬性規則 |
| `.claude/skills/gen-dev-workflow/scripts/wf-state.sh` | 修改 | `legal_transition()` 新增 `4->5`, `5->4`, `5->5`, `4->6`, `5->6`, `6->done` |
| `.claude/hooks/wf-guard-stage-check.sh` | 新增 | `PreToolUse` Hook 腳本，嚴格分支綁定與 responder 卡控 |
| `.agents/hooks.json` | 修改 | 註冊 `wf-guard-stage-check` 於 Antigravity `PreToolUse` |
| `.claude/settings.local.json` | 修改 | 註冊 `wf-guard-stage-check` 於 Claude `PreToolUse` |
| `docs/brainstorm/2026-08-25-workflow-brainstorm.md` | 修改 | 更新 Gap 2.6 狀態為已修復與落地現況表格 |

---

## 3. 任務拆分與實作清單 (Task Breakdown)

### Task 1: 文件層規範硬性化 (方案 A)
- 修改 `SKILL.md`，在 STAGE 5 與 STAGE 6 標明不可跳過之第一步狀態推進指令。

### Task 2: 狀態機轉移表擴充
- 修改 `wf-state.sh` 之 `legal_transition()`，允許 `4->5`, `5->4`, `5->5`, `4->6`, `5->6`, `6->done`。

### Task 3: 實作 PreToolUse Hook (方案 C)
- 撰寫 `.claude/hooks/wf-guard-stage-check.sh`，實作雙 Schema 解析、嚴格分支比對、阻擋與精準 stderr 提示。
- 賦予執行權限 `chmod +x`。

### Task 4: Hook 配置與系統註冊
- 於 `.claude/settings.local.json` 與 `.agents/hooks.json` 註冊該 Hook。

### Task 5: 邊界測試與驗證
- 驗證無狀態檔放行、非 responder 放行、Stage 4 阻擋、Stage 5 放行。
- 更新 brainstorm 追蹤文件。
