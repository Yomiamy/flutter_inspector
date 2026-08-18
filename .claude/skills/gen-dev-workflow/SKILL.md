---
name: gen-dev-workflow
description: |
  完整開發流程編排器。使用者說「幫我做 X 功能」時觸發，自動依序驅動所有 agent 直到 PR 建立，只在關鍵決策點暫停確認。
  也可用既有 GitHub issue id 直接進入 STAGE 1（跳過 STAGE 0a/0b 規劃），例如「開發 issue #42」「處理 #54」。
  PR 實際合併後，可另外觸發 STAGE 6 清理該 PR 對應的 worktree（branch 一律保留不刪除）。
  小修正可走 quick 模式（單暫停點、不建 worktree），例如「快速修正 <描述>」「/gen-dev-workflow quick #54」。
  多個獨立需求可走 batch 模式（各自 worktree/branch/PR 依序執行，每項間需使用者 /clear 換新 context），例如「依序做完這幾項」「/gen-dev-workflow batch §P4 §P6 #42」「繼續批次」。
  暫停頻率可用 pause_level 調整（strict 預設全停／balanced 只停關鍵三點／autonomous 全不停）。
  觸發條件：dev workflow, 開始開發, 新功能開發, 幫我做 X 功能, 繼續, 繼續上次, 繼續開發, /gen-dev-workflow, 開發 issue #<id>, 處理 #<id>, 快速修正, quick fix, PR #<id> 合併了 清理 worktree, batch, 批次, 依序做完, 繼續批次, 不要中途問我
---

# Dev Workflow（自動編排模式）

你是整個開發流程的**總指揮**。使用者給你一個需求，你自動驅動所有 agent 跑完整個週期，只在必要時暫停。

## 編排流程

```text
    使用者：「幫我做 X 功能」
           │
           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 0a：功能規格                             │
    │  → 呼叫 planner agent                           │
    │  → 🟢 並行 2 條（已 opt-in → 可用 Workflow）：   │
    │     A. 專案 context 收集（讀檔 / git log）       │
    │     B. 相似功能代碼調查（既有實作參考）          │
    │     → planner 收斂兩者後撰寫規格                 │
    │  → 產出 docs/features/YYYY-MM-DD-<feature>.md   │
    │    （What & Why：使用者故事、驗收條件、範圍邊界） │
    │  ⏸ 暫停：展示功能規格，等使用者確認              │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 0b：實作計畫                             │
    │  → 呼叫 planner agent（依據已確認的功能規格）    │
    │  → 產出 docs/plans/YYYY-MM-DD-<feature>.md      │
    │    （How：資料結構、檔案異動、任務拆分）          │
    │  ⏸ 暫停：展示實作計畫，等使用者確認              │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 1：建立 Issue + Worktree                 │
    │  → 呼叫 gen-gh-issue skill 產出 Issue body       │
    │    （五區段 zh-tw：Problem/Root cause/Fix/        │
    │     Out of scope/Verification）                  │
    │  → 呼叫 brancher agent 產出分支名草稿             │
    │    （prefix/slug 規則沿用 ticket-id-dev-prep）    │
    │  ⏸ 暫停：展示 Issue 標題/內容 + 分支/worktree 名稱│
    │          等使用者確認或修改                       │
    │  → 委派執行 gh issue create                     │
    │  → brancher 依 ticket-id-dev-prep 規則建立       │
    │    worktree + branch，主對話 cd                  │
    │    進新 worktree 繼續後續所有 stage               │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 2：實作（逐任務動態分級）                  │
    │  → 呼叫 implementer agent                       │
    │  → 解析計畫，判斷並行模式：                       │
    │     • ≥2 個獨立任務、寫入路徑不重疊 → 🟢 並行    │
    │       （已 opt-in → 同批可用 Workflow fan-out）  │
    │     • 否則 → 🔴 序列逐任務                        │
    │  → 逐任務選 model：機械性→快/便宜｜整合→標準     │
    │     ｜設計判斷/跨層→最強                         │
    │  → 委派實作任務，verifier 兩階段驗收          │
    │  🪶 Ponytail：派發模板必附〈規則塊〉，驗收把  │
    │     計畫外抽象/依賴/防禦分支當品質不佳退回    │
    │  ⏸ 每個任務（或每批並行）完成後暫停：            │
    │      展示變更檔案 + 測試結果摘要                  │
    │      問「確認繼續下一個任務嗎？」                  │
    │  ⏸ 遇到模糊需求：問使用者後繼續                  │
    └──────────────────────┬──────────────────────────┘
                           │ 所有任務確認完成
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 3：審查                                    │
    │  → 呼叫 reviewer agent（不委派，親自判斷）      │
    │  → 已 opt-in → 多 angle 對抗式審查（Workflow    │
    │    平行 verifier 找 bug，reviewer 收斂判斷）     │
    │  🪶 Ponytail：第五 lens「過度工程/可簡化」找    │
    │     計畫外抽象；僅 plan 外加料 / 刪即更小 diff  │
    │     兩種情況阻擋退回，與安全衝突時安全勝出      │
    │  ⏸ 暫停：展示審查報告，問「確認繼續嗎？」         │
    │  ┌─ 使用者確認（通過）                      ─┐   │
    │  └─ 不通過 / 使用者要求修正                   │   │
    │       → 退回 STAGE 2 修正 → 再回 STAGE 3 ───┘   │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認通過
                           ▼
    ┌─────────────────────────────────────────────────┐
    │  STAGE 4：發布                                    │
    │  → 呼叫 publisher agent                         │
    │  → publisher 內部用 gen-pr skill 產 PR 描述      │
    │    （gen-pr 格式：Summary + 修正問題/修正方式）   │
    │  → 委派分析 Diff，Claude 校對草稿              │
    │  ⏸ 暫停：展示 PR 草稿，等使用者確認發布          │
    └──────────────────────┬──────────────────────────┘
                           │ 使用者確認
                           ▼
                      PR 建立完成 ✦
                      流程結束，Claude 停止。
                      （worktree 與本地 branch 一律保留，不自動刪除；
                       PR 合併後可手動觸發 STAGE 6 清理 worktree）

    ──────────────────────────────────────────────────
    STAGE 5：回覆 PR Review（獨立入口，由你手動觸發）
    ──────────────────────────────────────────────────
    觸發方式：你說「PR #42 有新的 review 意見」
    🔴 第一步（不可跳過）：推進狀態至 STAGE 5
       - 既有工作區已存在 state 檔：wf-state.sh advance <state_file> 5 --confirmed
       - 新對話／獨立進入：wf-state.sh init --mode jump --stage 5 --branch <branch> --set pr=<PR>
    → 呼叫 responder agent 處理每條意見
    → 處理完畢 → 呼叫 reviewer agent 重新審查
    → 審查通過 → 呼叫 publisher agent 更新 PR 描述與留言
    → 呼叫 wf-state.sh stage-done 5 結束 STAGE 5

    ──────────────────────────────────────────────────
    STAGE 6：清理 Worktree（獨立入口，由你手動觸發）
    ──────────────────────────────────────────────────
    觸發方式：PR **實際合併後**，你說「PR #42 合併了，清理 worktree」
    🔴 第一步（不可跳過）：推進狀態至 STAGE 6
       - 既有工作區已存在 state 檔：wf-state.sh advance <state_file> 6 --confirmed
       - 新對話／獨立進入：wf-state.sh init --mode jump --stage 6 --branch <branch>
    → 【文件同步】先呼叫 gen-sync-docs-by-branchs skill
    → 【提交同步結果】呼叫 gen-commit skill 將文件變更 commit 進 git
    → 呼叫 worktree-close-cleanup skill 移除 STAGE 1 建立的 worktree
    → 僅移除 worktree 本身，**對應 branch 一律保留、不刪除**
```

---

## 暫停點規則

| 暫停時機 | 你要做什麼 | 繼續條件 |
|---------|-----------|---------|
| 功能規格完成後 | 展示功能規格（使用者故事、驗收條件、範圍），問「確認嗎？」 | 使用者確認 |
| 實作計畫完成後 | 展示實作計畫（任務清單、檔案異動），問「確認開始實作嗎？」 | 使用者確認 |
| Issue + 分支建立前 | 展示 Issue 標題、描述內容、分支名稱，問「確認建立嗎？」 | 使用者確認或修改後確認 |
| 每個實作任務完成後 | 展示變更檔案清單 + 測試結果，問「確認繼續下一個任務嗎？」 | 使用者確認 |
| 審查報告完成後 | 展示完整審查報告，問「確認繼續發布嗎？或需要修正？」 | 使用者確認 → STAGE 4，或退回 STAGE 2 |
| 遇到模糊需求 | 問最小必要問題（≤ 2 個），不要問多 | 使用者回答後自動繼續 |
| PR 草稿完成後 | 展示草稿，問「確認發布嗎？」 | 使用者確認 |

**不應該暫停的情況：** 分支建立、任務間自動切換、STAGE 2 內部失敗 retry、STAGE 3 審查失敗退回 STAGE 2、測試執行、並行單元間的協調。這些全部自動處理。

### 暫停粒度（`pause_level`）

上表是 `strict`（預設）的行為。使用者可在啟動時加參數調整（如 `--pause-level balanced`）：

| level | Stage 關卡 | STAGE 2 任務間 | 適用 |
|:---|:---|:---|:---|
| `strict`（預設） | 全停（上表七項） | **每個任務都停** | 不熟的功能、要盯著看 |
| `balanced` | 只停 `0b` 計畫確認 / `2` 實作整體完成 / `4` PR 發布前 | **不停** | 計畫已看過，想一路跑到 PR |
| `autonomous` | 全不停 | 不停 | 批次佇列、純機械性改動 |

**判定的唯一來源是腳本的 `should_pause()`**：照常在每個暫停點呼叫 `stage-done` / `task-done`，看它回傳「等待使用者確認」就停下，回傳「自動推進」就直接繼續。`pause_level` 僅關掉詢問，不關掉狀態機校驗與防禦（異常值一律退回 strict）。
⚠️ `autonomous` 會讓 PR 不經過目直接送出，除非明確要求，否則優先建議 `balanced`。

---

## 核心規範與實作細節 (References)

為了保持本文件的專注，以下所有操作機制、底層紀律、邊界條件與擴充模式的具體規則，請在執行相關步驟前查閱對應的 reference 文件：

- **狀態機與 Session 續接機制**：[`references/state-machine.md`](references/state-machine.md)（涵蓋 `wf-state.sh` 的呼叫時機、狀態推進法則）
- **MCP 委派紀律**：[`references/mcp-delegation-discipline.md`](references/mcp-delegation-discipline.md)（涵蓋使用 `gemini-mcp-tool` 的三條硬性紀律）
- **Token 預算與強制交接機制**：[`references/token-budget-gate.md`](references/token-budget-gate.md)（涵蓋大於 150k 時強制打 WIP commit 並切換 session 的閉環處理）
- **Worktree 與分支建立（STAGE 1）**：[`references/branch-worktree-rules.md`](references/branch-worktree-rules.md)（涵蓋跨目錄搬移規劃文件與驗證步驟）
- **Model 選擇與並行委派契約**：[`references/delegation-and-parallel.md`](references/delegation-and-parallel.md)（涵蓋 `xhigh` 風險、同 tier 失敗重試與升級策略）
- **使用 Claude Workflow 加速（STAGE 0a, 2, 3）**：[`references/workflow-parallel.md`](references/workflow-parallel.md)
- **執行模式（Quick 快速通道與 Batch 批次模式）**：[`references/execution-modes.md`](references/execution-modes.md)
- **所有可用指令清單與跳入特定 Stage**：[`references/command-cheatsheet.md`](references/command-cheatsheet.md)
