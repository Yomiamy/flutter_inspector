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

> **Claude Workflow 編排（可選加速層）。** 本流程內**特定的並行、唯讀或路徑不重疊、且該段落內部不需要問使用者**的環節，可改用 Claude `Workflow` 工具（JS 腳本 fan-out 多 subagent）執行，取代逐個 `Task(...)` 串接。適用點只有三處：**STAGE 0a 雙線 context 收集**、**STAGE 2 同批獨立任務**、**STAGE 3 多 angle 對抗式審查**（各章節有專節說明）。
>
> **硬性邊界（違反即破壞流程，絕不可越界）：**
> - **絕不**把整條 orchestrator 包成單一 Workflow 腳本——Workflow 背景執行、跑完才回，中途無法暫停問人，會直接摧毀本流程 7 個人在迴圈中的暫停確認點。
> - Workflow 只用於**單一段落內部**的 fan-out，**暫停點永遠由主指揮（主對話）掌控**，落在任何 Workflow 呼叫的外面。一個 Workflow 呼叫 = 一段不可中斷的並行，跑完回到主對話才暫停。
> - **前置條件：** 使用者需明確 opt-in 多 agent 編排（說「ultracode」、「用 workflow」、「多 agent」或類似）。未 opt-in 時，這三處一律退回原本的 `Task(...)` / 序列作法，功能完全相同，只是不 fan-out。
> - state 檔、model 策略、委派規則**完全不變**——Workflow 只換「並行執行的載體」，不換流程語意。

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
    │    （prefix/slug 規則沿用 ticket-id-dev-prep，    │
    │     見「分支與 Worktree 建立」章節）              │
    │  ⏸ 暫停：展示 Issue 標題/內容 + 分支/worktree 名稱│
    │          等使用者確認或修改                       │
    │  → 委派執行 gh issue create                     │
    │  → brancher 依 ticket-id-dev-prep 規則建立       │
    │    worktree + branch（見下方章節），主對話 cd     │
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
    │     ｜設計判斷/跨層→最強（見 Model 策略章節）    │
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
    各 stage 的 model 由對應 agent 檔的 frontmatter 綁定
    （.claude/agents/*.md，用別名不綁版本 ID），本文件只寫
    角色名與推論等級名。**effort 不在 frontmatter 裡**——
    `a6fcd29` 已移除逐 agent 的 effort 綁定，改為預設繼承
    session 目前的 effort；要維持 stage 間差異化，派發時
    須明確帶 effort 參數。詳見下方「Model 與委派策略」章節。
    主對話（總指揮）本身不換 model；切換發生在委派出去的
    子進程——MCP 委派（STAGE 2 逐任務動態分級）與 STAGE 2 驗收
    委派的 verifier agent。

    ──────────────────────────────────────────────────
    STAGE 5：回覆 PR Review（獨立入口，由你手動觸發）
    ──────────────────────────────────────────────────
    觸發方式：你說「PR #42 有新的 review 意見」
    🔴 第一步（不可跳過）：推進狀態至 STAGE 5
       - 既有工作區已存在 state 檔：wf-state.sh advance <state_file> 5 --confirmed
       - 新對話／獨立進入：wf-state.sh init --mode jump --stage 5 --branch <branch> --set pr=<PR>
       ↑ 未執行此步就派發 responder = 流程違規（將遭 Hook 攔截）
    → 呼叫 responder agent 處理每條意見
    → 處理完畢 → 呼叫 reviewer agent 重新審查
    → 審查通過 → 呼叫 publisher agent 更新 PR 描述與留言
    → 呼叫 wf-state.sh stage-done 5 結束 STAGE 5
    → 完成後流程再次結束，Claude 停止等待。

    ──────────────────────────────────────────────────
    STAGE 6：清理 Worktree（獨立入口，由你手動觸發）
    ──────────────────────────────────────────────────
    觸發方式：PR **實際合併後**，你說「PR #42 合併了，清理 worktree」
    🔴 第一步（不可跳過）：推進狀態至 STAGE 6
       - 既有工作區已存在 state 檔：wf-state.sh advance <state_file> 6 --confirmed
       - 新對話／獨立進入：wf-state.sh init --mode jump --stage 6 --branch <branch>
    → 【文件同步】先呼叫 gen-sync-docs-by-branchs skill，
      以當前處理的分支為目標，將該分支的實際變更回寫到
      docs 下的發想／結構說明文件（brainstorm、architecture 等）
    → 【提交同步結果】同步完成後呼叫 gen-commit skill 將
      文件變更 commit 進 git（避免同步結果在清理 worktree 時遺失）
    → 呼叫 worktree-close-cleanup skill 移除 STAGE 1 建立的 worktree
    → 只移除 worktree 本身，**對應 branch 一律保留、不刪除**
      （worktree-close-cleanup 的既有規則，不因併入此流程而改變）
    → 呼叫 wf-state.sh stage-done 6（或標記 done）
    → 不自動觸發：workflow 不會偵測 PR 合併狀態並自動清理，
      需你明確告知已合併才執行，避免在 PR 還可能需要修改時
      誤刪工作區。
    → 完成後流程再次結束，Claude 停止等待。
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

**不應該暫停的情況：** 分支建立、任務間自動切換、STAGE 2 內部失敗 retry、STAGE 3 審查失敗退回 STAGE 2、測試執行、並行單元間的協調。這些全部自動處理（失敗 retry 與退回路徑見「並行執行契約」章節）。

### 暫停粒度（`pause_level`）

上表是 `strict`（預設）的行為。使用者可在流程啟動時選擇較鬆的粒度——`wf-state.sh init --pause-level <L>`，或流程中途 `wf-state.sh set <檔> pause_level=<L>`：

| level | Stage 關卡 | STAGE 2 任務間 | 適用 |
|:---|:---|:---|:---|
| `strict`（預設） | 全停（上表七項） | **每個任務都停** | 不熟的功能、要盯著看 |
| `balanced` | 只停 `0b` 計畫確認 / `2` 實作整體完成 / `4` PR 發布前 | **不停** | 計畫已看過，想一路跑到 PR |
| `autonomous` | 全不停 | 不停 | 批次佇列、純機械性改動 |

**判定的唯一來源是腳本的 `should_pause()`**，你不需要自己判斷該不該停——照常在每個暫停點呼叫 `stage-done` / `task-done`，看它回傳的訊息：印「等待使用者確認」就停下來問，印「自動推進 / 自動繼續下個任務」就直接繼續。

🔴 **`pause_level` 只關掉「等使用者點頭」，不關掉任何守衛**：stage 轉移表、任務數校驗（`completed_tasks` vs `total_tasks`）、schema 校驗一律照常生效。欄位缺失或值異常一律退回 `strict`——壞掉的方向偏向多停一次，不偏向少停一次。

⚠️ **`autonomous` 會讓 `gh pr create` 不經你過目就執行**（STAGE 4 暫停點被關掉）。發 PR 是對外動作，除非使用者明確要求無人值守，否則優先建議 `balanced`。

**主動中斷（非暫停）：** context > 150k 時依 Token Budget Gate 主動保存並切 session，這不是暫停點，是保護性中斷。

**暫停點的程式強制（棘輪）：** 每個暫停點對應一次 `wf-state.sh stage-done`（或 STAGE 2 的 `task-done`），把 state 標為等待確認；使用者確認後才跑 `advance <next> --confirmed`（或任務間的 `confirm`）推進。未確認就 `advance` 會被腳本直接拒絕——暫停點不再只靠本文件的自律（見 `references/state-machine.md` 的「狀態機腳本」）。

---

## 分支與 Worktree 建立（STAGE 1 統一規則）

STAGE 1 建立分支與工作區時，**不論從哪個入口進來**，最後一步一律沿用 `ticket-id-dev-prep` skill 的 prefix/slug/worktree 規則，避免命名邏輯在兩個 skill 裡各寫一套。

### 兩種入口，同一套收斂邏輯

| 入口 | 觸發方式 | 前置動作 | 到達 STAGE 1 時已有什麼 |
|------|---------|---------|------------------------|
| **正常路徑**（多數情況） | 「幫我做 X 功能」 | 已跑完 STAGE 0a/0b，`gen-gh-issue` 已產出五區段 Issue body | 結構化 Issue body，尚無 Issue 編號 |
| **issue-id 路徑** | 使用者提供既有 issue id（例如「開發 issue #42」「處理 #54」） | 跳過 STAGE 0a/0b（規格/計畫已內含於既有 issue，不重新規劃） | 只有 issue id，Issue 內容需解析 |

兩種入口在 STAGE 1 收斂為同一套步驟：

1. **取得 Issue 內容**：
   - 正常路徑：`gen-gh-issue` 產出的五區段 body 直接作為 issue brief 來源，`brancher` 呼叫 `gh issue create` 建立新 Issue。
   - issue-id 路徑：`brancher` 先用 `gh issue view <id>` 取得既有 Issue 內容，依 `ticket-id-dev-prep` 的「已解析 Brief 規則」濃縮為 `zh-tw` 實作 brief（不重新調查，issue 內容本身就是真實來源）。
2. **決定 branch prefix + slug**（沿用 `ticket-id-dev-prep` 的「Slug 規則」與「Branch 與 Worktree 規則」）：
   - prefix 依 issue 意圖選擇：`fix/YYYYMM`（bug/regression）、`feature/YYYYMM`（新功能）、`chore/YYYYMM`（refactor/維護）。
   - slug：2–6 個英文字的 kebab-case，具體且與實作相關，避免 `handle`/`update`/`fix-issue` 這類填充詞。
   - branch 名稱：`<prefix>/<ISSUE-ID>-<slug>`，其中 `<prefix>` 已含 `YYYYMM`（例：`fix/202607/54-console-clear-not-wiping`）。
   - worktree 目錄：`.claude/worktrees/<repo-name>-<ISSUE-ID>-<slug>`，建在當前 repo 內的 `.claude/worktrees` 目錄下，除非使用者要求其他位置。
3. **建立 worktree + branch**：優先使用 `ticket-id-dev-prep` 內附的 `scripts/prepare_issue_dev_workspace.sh`（若存在於當前專案）；否則走手動回退流程：
   ```bash
   git fetch origin main --prune
   git worktree add -b "<branch-name>" "<worktree-path>" "origin/main"
   ```
   base branch 預設 `origin/main`，除非使用者明確要求其他 base。若目標 branch 或 worktree 路徑已存在，停止並回報，不默默重用或覆蓋。
4. **最小設定檢查**：`cd` 進新 worktree 後執行 `git branch --show-current` 與 `git status --short` 驗證，並 `flutter pub get`（依 `ticket-id-dev-prep` 的「設定完成規則」，若專案有本地限定設定檔如 `.env`、簽章檔，同步進新 worktree）。
5. **🔴 帶入 STAGE 0a/0b 產出的規劃文件**（正常路徑必做）：功能規格與實作計畫是在**原 repo 目錄**產出的未 commit 檔案，新 worktree 從 `origin/main` 拉出來時**不會有它們**。若不搬，state 檔記的 `spec`/`plan` 路徑切進 worktree 後指向不存在的檔，STAGE 2 的 implementer 讀不到計畫。
   ```bash
   # 於原 repo 執行；<repo-root> 為原 repo 路徑，<worktree-path> 為步驟 3 建立的目錄
   mkdir -p "<worktree-path>/docs/features" "<worktree-path>/docs/plans"
   cp "<repo-root>/<spec 路徑>" "<worktree-path>/<spec 路徑>"
   cp "<repo-root>/<plan 路徑>" "<worktree-path>/<plan 路徑>"
   ```
   - 用**複製**不用 commit + cherry-pick：規劃文件在原 repo 尚未 commit，複製過去後在 worktree 中呼叫 `gen-commit` 將文件 commit，不需在 base branch 上多留一個 commit。
   - 複製後**驗證兩個檔案都存在於新 worktree**，缺任一個就停下回報，並於確認存在後執行 `gen-commit`，不要帶著未 commit 的狀態進 STAGE 2。
   - 路徑維持 repo 相對路徑不變（例 `docs/plans/2026-05-03-cart.md`），所以 state 檔的 `spec`/`plan` 欄位**不需改寫**，切目錄後自然指向新 worktree 內的同名檔。
   - **原 repo 的那兩份等 commit 進 worktree 後才刪，別提早刪**：`cp` 完到 `gen-commit` 成功之間，原 repo 那份是唯一未銷毀的備份（worktree 建立失敗或使用者中途喊停時的後路），此窗口內刪除等於自斷退路。但 `gen-commit` 一旦成功，規劃文件已進 feature branch 的 git 歷史，原 repo 那份就成了無人追蹤的孤兒殘留——每跑一次 workflow 就多兩份，累積污染原 repo 的 `git status`。因此**驗證 worktree 內 commit 確實存在後（`git -C "<worktree-path>" log --oneline -1 -- "<spec 路徑>" "<plan 路徑>"` 有輸出），回原 repo 刪掉那兩份**：`rm -f "<repo-root>/<spec 路徑>" "<repo-root>/<plan 路徑>"`。commit 未確認成功前一律不刪。
   - issue-id 路徑（跳過 STAGE 0a/0b）沒有這兩份文件，本步驟略過。
6. **主對話切換工作目錄**：後續 STAGE 2–4 的所有 Bash 指令與檔案操作都在新 worktree 路徑下執行，state 檔（見「狀態追蹤」小節與 `references/state-machine.md`）也寫在新 worktree 內的 `.claude/workflow-state/`，與主 repo 分開、互不干擾。

### 與 STAGE 2 並行任務用的 `isolation: 'worktree'` 的區別

「用 Claude Workflow 執行並行」章節提到的 `agent(..., {isolation: 'worktree'})` 是**子 agent 層級**的臨時隔離（跑完自動清除，不留存），只用來避免 STAGE 2 並行任務互踩工作區；這裡的 STAGE 1 worktree 是**整個 workflow 的長駐工作區**，直到 PR 合併都持續存在，兩者不是同一回事，不要混用。

---

## 執行方式

### 啟動完整流程
```
使用者：幫我做 <需求描述>

你：好，開始執行開發流程。（effort 依「推論等級表」明確帶入，見上方風險註記）
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

### 從特定階段繼續
```
使用者：從審查繼續 / 繼續發布 / 重新規劃

你：根據當前狀態跳入對應 stage，其餘流程照常自動執行。
```

### 從既有 issue id 啟動（跳過 STAGE 0a/0b）
```
使用者：開發 issue #54

你：好，直接進 STAGE 1。（effort 依「推論等級表」明確帶入，見上方風險註記）
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
此路徑跳過 STAGE 0a/0b（規格與計畫）——issue 內容本身就是實作依據，不重新規劃。若 issue 內容過於模糊而無法產生可靠的實作 brief，依 `ticket-id-dev-prep` 的安全規則停下向使用者確認，不臆測需求。

---

## Quick 模式（小修正快速通道）

**觸發**：`/gen-dev-workflow quick <描述或 #issue>`，或使用者說「快速修正 <描述>」。

**適用範圍**：預期 diff 小的修正——約 ≤3 檔、無架構變動、無新依賴、不需要規劃文件。超出就走完整流程。

```text
quick <描述或 #issue>
  │
  ▼
① 建 branch（不建 worktree，直接在原 repo checkout）
   - 有 #issue → gh issue view 解析 brief，branch 名 <prefix>/YYYYMM/<ID>-<slug>
   - 只有描述 → 不開 issue，branch 名 <prefix>/YYYYMM/<slug>
   - prefix/slug 規則沿用 ticket-id-dev-prep
  ▼
② 主對話直接實作（不委派 implementer/MCP——小修正本來就在「不委派」硬規則內）
   - 不拆任務、不逐任務暫停；模糊需求仍問（≤2 個問題）
   - 改完跑相關測試（不重跑整套）
  ▼
③ Task("reviewer", "快掃 <branch> diff，單 lens：correctness")
   - 保住「不讓同源 model 自審」原則；發現問題 → 主對話修正後重掃
  ▼
④ 呼叫 gen-commit skill 執行 commit → 用 gen-pr skill 產 PR 草稿
  ▼
⏸ 唯一暫停點：展示 PR 草稿 → 使用者確認 → 發布，流程結束
```

**規則：**
- state 檔照寫：`wf-state.sh init --mode quick --branch <branch>` 建 `<branch-slug>.json`（存原 repo `.claude/workflow-state/`）——中斷後「繼續」照常續接，PR MERGED 照常自動刪檔。quick 不套用 stage 轉移表，但 schema 校驗與暫停點棘輪照常生效（唯一暫停點：PR 草稿確認前 `stage-done <檔> <目前-stage>`，確認後 `confirm` 再發布）。
- 不建 worktree ⇒ 同一 repo **同時只能跑一個 quick**（需要多並行就走完整流程的 worktree 隔離）。
- 中途發現超出小修正範圍（多檔設計判斷、新依賴、要動架構）→ 停下告知，`wf-state.sh upgrade <檔>`（單向 quick→sequence，stage 落在 2）升級轉入完整流程。升級後**必須立即**建立對應的 worktree（沿用 ticket-id-dev-prep 規則），將 Root 中未 commit 的變更帶入新工作區，用 `wf-state.sh promote` 將狀態 JSON 移至新工作區，並 `cd` 進入該工作區以確保物理隔離。
- Token Budget Gate 照常適用（`> 150k` 切 session 規則不變；`100–150k` 的強制 MCP 委派不適用於 Quick 的直接實作步驟，Quick 模式本來就不委派 implementer）。

---

## 批次模式（多個獨立 workflow 依序執行）

**觸發**：`/gen-dev-workflow batch <項目1> <項目2> ...`，或使用者說「依序做完這幾項」。

**與 STAGE 2 多任務的區別**（最常見的誤解，先釐清）：

| | STAGE 2 的 T1/T2/T3 | 批次模式的項目 1/2/3 |
|:---|:---|:---|
| 來源 | **同一份**實作計畫拆出的子任務 | **各自獨立**的需求 / issue |
| worktree | 共用一個 | **各自一個** |
| branch / PR | 共用一個，最後合成一個 PR | **各自一個 branch、各自一個 PR** |
| 控制粒度 | `pause_level` | 批次佇列 |

使用者說「一次做多個任務」時，**先確認是哪一種**——若他要的是各自獨立的 PR，那是批次模式，`pause_level` 解決不了。

### 🔴 核心限制：Claude 無法自行清空 context

批次的每一項都要**全新 context** 才不會累積爆掉，但清 context 是 session 層級操作，**只有使用者能做**。所以批次模式不是「全自動」，而是**自動接續 + 使用者按兩下鍵盤**：

```text
/gen-dev-workflow batch §P4 §P6 #42
  │
  ▼
wf-state.sh batch-init "§P4..." "§P6..." "#42" --pause-level balanced
  → 產生 .batch-<id>.json（存原 repo .claude/workflow-state/）
  ▼
wf-state.sh batch-next → 取得第 1 項
  ▼
跑完整 sequence 流程（0a→4）：各自 issue / worktree / branch / PR
  ├─ 用批次檔記的 pause_level 建該項的 state 檔
  └─ cd 進該項的 worktree 執行
  ▼
PR 開好 → wf-state.sh batch-done --pr <url> --branch <branch>
  ▼
⏸ 輸出交接提示，流程在此停止：
   「§P4 完成 ✦ PR: <url>
     批次剩餘 2 項（§P6、#42）。
     請 /clear 後輸入「繼續批次」，會自動接下一項。」
  ▼
使用者 /clear + 輸入「繼續批次」
  ▼
新 session：wf-state.sh batch-next → 取得第 2 項 → 重複上述
  ▼
batch-next 回傳 DONE → 輸出總結（各項 status / PR 連結），刪除批次檔
```

**規則：**

- **批次檔永遠留在原 repo** 的 `.claude/workflow-state/`，不隨 worktree 移動——它是跨 workflow 的，不屬於任何單一 branch。
- **`cd` 紀律**：每項跑完必須 `cd` 回原 repo 再收尾，否則下一項的 `batch-next` 會在錯誤的工作目錄找不到批次檔。
- **建議搭配 `--pause-level balanced`**：批次的意義是減少打斷，每項若還停五次就失去意義。但**不建議 `autonomous`**——那會讓三個 PR 都不經過目就發出去。
- **失敗處理**：某項失敗（STAGE 3 審查連續退回、tier 升級後仍失敗）→ `batch-fail --note "<原因>"`，游標照常前進到下一項。**一項失敗不中止整個批次**——各項獨立，沒有理由讓後面的陪葬。最終總結會列出失敗項讓使用者決定要不要重跑。
- **中止**：使用者說「停止批次」→ `batch-abort`。只刪批次檔，**已建立的 branch / PR / worktree 一律保留**（沿用「branch 永不自動刪除」的既有紀律）。
- **`batch-next` 回傳 DONE 後**才刪批次檔，並輸出總結表（項目 / status / PR 連結 / 失敗原因）。

**「繼續批次」的定位流程**（新 session 進來時）：

```
→ .claude/workflow-state/.batch-*.json
   ├─ 0 個 → 告知「找不到進行中的批次」，不自行猜測
   ├─ 1 個 → 讀取，batch-next 取下一項，繼續
   └─ ≥2 個 → 列出讓使用者選（腳本本身也會 die 要求明示）
```

> ⚠️ 批次檔與「本 session 的 state 檔以外，一律不碰」不衝突——批次檔是**使用者明確建立的佇列**，不是別的流程的 workflow state。但同樣的紀律適用：**不因為看到某個批次檔就自行接續它**，要使用者說「繼續批次」才動。

---

## 狀態追蹤

state 檔的所有建立、讀取、更新一律透過 `scripts/wf-state.sh`（**絕不手寫或手改 JSON**）——schema 校驗、stage 轉移合法性、暫停點棘輪三道 guard 都在腳本裡強制。

進度回報行前綴帶流程識別：pending 階段帶 `<wf-id>`，已建 branch 後帶 branch slug（例 `[feature-202605-42-cart] [2/5] 實作中...`）。

🔴 **完整的指令對照表、state 檔命名與生命週期、續接時的「先定位」邏輯、以及「本 session 的 state 檔以外一律不碰」紀律，見 [`references/state-machine.md`](references/state-machine.md)。** 涉及任何 state 操作（init / promote / advance / stage-done / task-done / batch-* / 刪檔判斷）前先讀該檔。

---

## Token Budget Gate（context 用量控管）

這是長流程（6 stages + 每任務暫停）的存活機制。**每個 stage 切換前、以及 STAGE 2 每個任務完成後**，評估主對話 context 用量並依下表行動：

| Context 用量 | 行為 |
|---|---|
| < 60k | 正常流程，不做任何事 |
| 60–100k | ⚠️ 提示使用者「context 已 <用量>，建議精簡」。委派 agent 時要求只回報摘要，不回貼完整 diff / 檔案內容 |
| 100–150k | ⚠️ 完整流程且 MCP 可用時：implementer / publisher 強制走 MCP 委派（不自行讀大檔），主對話只保留高層判斷。**MCP 不可用時走 Fallback 或按下方 `> 150k` 規則切 session，不得因此卡住等待 MCP 恢復**。Quick 模式本無 implementer 委派（見「Quick 模式」①②），此行不適用於其直接實作步驟 |
| > 150k | ⛔ **強制 checkpoint，主動切 session** — 走下方「context 超標切 session 閉環」 |

### context 超標切 session 閉環

這是本 skill 相對其他 workflow 的關鍵優勢：**已有 per-branch state 檔，所以 Token Gate 撞牆時不會丟失進度**。

`> 150k` 觸發時，**不是只丟一句「建議切 session」**，而是執行完整交接：

```
1. 完成當前正在進行的最小單元（如 STAGE 2 的當前任務），不要切在半途
2. 寫入本 workflow 的 state 檔：`wf-state.sh set <檔> interrupted_by=context_budget`
   ├─ 已建 branch → <branch-slug>.json（記錄 stage / mode / spec / plan / branch / completed_tasks）
   └─ 尚無 branch（STAGE 0a/0b）→ .pending-<wf-id>.json（務必含 workflow_id，否則新 session 認不回）
3. 若有未 commit 的變更 → 先 commit（避免 session 切換後遺失）。
   若當前任務真的收不了尾（緩衝內做不完，被迫半途切）→ 打 WIP commit，message **必須帶交接筆記**：
   做到哪、下一步打算做什麼、為什麼選這個作法——代碼會自己活在磁碟上，思路不寫下來就真的丟了
4. 明確告知使用者，並把識別碼一起給出去（讓使用者知道續接的是哪個流程）：
   「[<wf-id 或 branch-slug>] context 已達 <用量>，為避免品質下降已保存進度至 STAGE <N>。
     請開新 session 後輸入『繼續』或 /gen-dev-workflow，會自動從 STAGE <N> 接續。」
5. 停止，不再繼續任何 stage
```

> **批次模式下的 Token Gate**：批次的每一項本來就靠使用者 `/clear` 換全新 context，所以正常情況不該在單項內撞到 150k。若真的撞到（單項過大），照上述閉環處理**該項自己的 state 檔**即可——批次檔不動、游標不前進，使用者續接後會接回同一項的 STAGE N，而不是跳到下一項。**絕不因為 context 超標就 `batch-done`**，那會把做到一半的項目標記成完成。

續接時（新 session 讀到 `"interrupted_by": "context_budget"`）：
```
→ 定位本 workflow 的 state 檔（已建 branch 靠當前 branch；尚無 branch 靠使用者帶回的 <wf-id>，
   或在只有單一 pending 檔時直接認領）
→ 開場白改為：「[<wf-id 或 branch-slug>] 偵測到上次因 context 超標而保存（STAGE <N>），現在 context 乾淨，直接續接。」
→ 不問「繼續還是開新流程」（因為這不是使用者主動離開，是系統保護性中斷，意圖明確）
→ 直接從 state 記錄的 stage 接續
```

**為什麼這是閉環：** Token Gate 偵測危險 → state 持久化保存全部進度 → 切 session 清空 context → 續接時 state 還原 → 不需重講 spec/plan/branch。沒有 state 的 workflow 在 150k 那一行只能撞牆，本 skill 在這裡反而最強。

---

## Model 與委派策略

Model 別名綁在各 agent 檔的 frontmatter（`.claude/agents/*.md`），本文件只寫**角色名**與**推論等級名**——這是降低 model 換代維護成本的核心，換代時只動 agent 檔一行（甚至因為用別名而完全免改）。

> **effort 不在 frontmatter 裡。** `a6fcd29`（chore(agents): remove effort overrides from subagent frontmatter）已移除逐 agent 的 `effort:` 綁定，改為子 agent **預設繼承主對話 session 目前的 effort**。這代表若派發時不主動帶 `effort` 參數，下表描述的「STAGE 2 機械任務便宜、STAGE 3 審查最強」這套 stage 間差異化**不會自動發生**——所有 stage 會用同一個 session effort。要維持本表的設計意圖，派發時必須**顯式帶入 effort**（見下方綁定原則）。

### 推論等級表（等級 → 綁定，全文唯一定義處）

| 等級 | model（frontmatter 綁定，未變） | effort（呼叫時明確帶入，取代已移除的 frontmatter 綁定） | 綁定的 agent |
|------|-----------------|-------------|-------------|
| 最強推論 | `model: opus` | `effort: xhigh` | planner、reviewer、verifier |
| 標準 | `model: sonnet` | `effort: max` | implementer |
| 輕量 | `model: sonnet` | `effort: high` | brancher、responder、publisher |
| 快/便宜 | 委派後端內部 fast model（不在 Claude 側綁定） | — | STAGE 2 機械性任務 |

**綁定原則：**
- model 一律用**別名**（`opus`/`sonnet`），不綁版本 ID——CLI 自動解析到當代 model。這部分仍綁 frontmatter，不受 effort 變動影響。
- effort **派發時必須明確帶入**：`Task("<agent>", ..., effort: "<本表對應值>")`。不帶等同放棄差異化、落回 session 預設值——這不是可省略的細節，是本表能否生效的唯一開關。
- Workflow `agent()` 呼叫：`agentType: '<agent 名>'` 仍沿用 frontmatter 的 model 綁定；effort 另用 `opts.effort` 依本表帶入（frontmatter 已無 effort 可沿用，省略等於落回 session 預設）。
- 要調整某角色的等級 → model 改該 agent 檔一行；effort 改本表一行，兩處呼叫端（Task 派發與 Workflow `agent()` 範例）跟著本表走，不散落各處硬編碼。

> 🔴 **已知風險（實測案例，未完全排除）：`effort: 'xhigh'` 在 thinking 未開啟時，於 Opus 4.8 上曾實際遇到 `400 output_config.effort 'xhigh' is not supported when thinking is disabled on this model`。**
> Claude Code 的 `Task`/`Agent`/Workflow `agent()` 呼叫是否會在帶 `effort: 'xhigh'`（或 `max`）時自動連帶開啟 thinking，**目前未經驗證**——若沒有，本表對 planner/reviewer/verifier（`xhigh`）與 implementer（`max`）的派發範例都可能在實際執行時 400。錯誤訊息本身指出安全退路：`effort: 'high'` 以下不受此限。
> 在此風險被驗證排除之前：若某次派發真的撞到這個 400，先把該次呼叫的 effort 降到 `high` 復原可用性，並回來這裡更新本表——**不要**默默把全表降級成 `high`（那會抹掉 STAGE 2/3 原本要的差異化），也不要無視這條風險繼續往更多派發點複製 `xhigh`/`max`。

### Stage 層級的基準分配

| Stage | Agent | 推論等級 | MCP 委派 | 不委派的原因 |
|-------|-------|-----------|------------|------------|
| 0a/0b 規劃 | planner | 最強推論 | — | 設計與計畫拆解是最高槓桿推論，錯了後面全錯 |
| 1 建立 Issue + Worktree | gen-gh-issue skill + brancher | 輕量 | ✦ gh issue create/view, git worktree add, flutter pub get | Issue body 由 gen-gh-issue 產（五區段 zh-tw，或 issue-id 路徑由 brancher 解析既有 issue），brancher 依 ticket-id-dev-prep 規則建立 worktree + branch，皆純 IO |
| 2 實作 | implementer | 標準（逐任務再分級，**見下方分級**） | ✦ 代碼+測試+commit（驗收委派 verifier：最強推論）| — |
| 3 審查 | reviewer | 最強推論 | — | 根因判斷需最強推論，且不該讓產出代碼的同源 model 自審 |
| 4 發布 | publisher（內部用 gen-pr skill） | 輕量 | ✦ Diff 分析 → PR 草稿（Claude 校對）| PR 描述由 gen-pr 產（Summary + 修正問題/修正方式），publisher 負責 push + gh pr create；重活已委派，且發布前有暫停點人肉把關 |
| 5 回覆 PR Review | responder（→ reviewer → publisher） | responder: 輕量；reviewer: 最強推論；publisher: 輕量 | — | responder 逐條意見判斷用輕量即可；中間 reviewer 是交叉驗證的把關點，吃重推論不降級 |
| 6 清理 Worktree | gen-sync-docs-by-branchs → gen-commit → worktree-close-cleanup skill | —（skill 於主對話執行） | — | 先同步文件再 commit，確保 docs 反映分支最終狀態；之後由主對話親自執行 `git worktree remove`（不委派 MCP），事後驗證 `git worktree list` / `git branch --list` |

### STAGE 2 implementer 內部的 model 分級

implementer 不該對所有任務一律用同一 model。讀取實作計畫後，**逐任務依複雜度分級**（對齊 `subagent-driven-development` 的 Model Selection）：

| 任務複雜度信號 | 委派等級 | 範例 |
|---|---|---|
| 觸及 1–2 檔、規格完整、機械性 | 快/便宜 | 新增一個 DTO 欄位、補一個 util function |
| 觸及多檔、需整合協調 | 標準 | 跨 service 串接、改既有流程 |
| 需設計判斷或廣泛 codebase 理解 | 最強推論 | 重構狀態機、新增跨層架構 |

planner 在實作計畫中**應為每個任務標註複雜度等級**，implementer 直接據此分派；未標註時 implementer 自行依上表判定。

### STAGE 2 驗收的 model（與實作 model 分離）

驗收（spec compliance → code quality 兩階段）**不沿用主對話當前 model**，而是**委派 verifier agent** 執行——其 frontmatter 綁定 `model: opus`（effort 需依推論等級表明確帶 `xhigh`，見上方「effort 不在 frontmatter 裡」），opus 取不到時由 CLI fallback 鏈自動落到可用的最強 model。

這麼設計的原因與 STAGE 3 相同——**產出代碼的委派後端可能用便宜/快 model，驗收刻意用最強推論交叉檢查**，不讓同源 model 自審，維持「驗收等級 ≥ 實作等級」的把關強度。

> 落地方式：`Task("verifier", ..., effort: "xhigh")` 或 Workflow 的 `agent('驗收任務...', {agentType: 'verifier', effort: 'xhigh', ...})` 執行（見「用 Claude Workflow 執行並行」章節的 verify 階段）。這是 STAGE 2 唯一會脫離「主對話 model」的環節；`effort: 'xhigh'` 不可省略，省略會落回 session 當前 effort。

### 不委派的硬規則

以下情況即使 MCP 委派可用也**不委派**（短文直生反而更省一次 context 來回）：
- commit message 生成（實作 model 依 diff 直生）
- 單一檔案 < 50 行的小修正
- STAGE 3 審查報告（reviewer 親自判斷，不可委派。註：可選的「多 angle 對抗式審查」用 Claude Workflow 的 verifier 平行找 bug 作為輸入，reviewer 仍親自收斂判斷並產出報告，兩者不衝突——見「用 Claude Workflow 執行並行」章節）
- **對外動作一律自己執行**：`gh pr create`、`git push` 不委派子進程動手，且須先通過對應暫停點

---

## 並行執行契約

並行只在兩處發生：**STAGE 0a 的 context 收集（雙線）** 與 **STAGE 2 的獨立任務並行**。

宣告並行的地方都必須遵守以下契約——光標 🟢 不算數，沒有契約的並行會在衝突時靜默壞掉。

### 何時可並行（判斷條件）

```
                  待處理工作
                       │
          ┌────────────┴────────────┐
          │ ≥2 個工作單元，且彼此    │
          │ 無資料依賴、寫入路徑     │
          │ 互不重疊？               │
          └────────────┬────────────┘
              是 ↓            ↓ 否
        ┌───────────┐   ┌──────────┐
        │ 🟢 並行    │   │ 🔴 序列   │
        └───────────┘   └──────────┘
```

### 並行三規則（缺一不可）

1. **明確 scope**：每個並行單元派發時給定**明確的寫入檔案清單**。STAGE 0a 的兩條是唯讀（只收集，不寫），天然安全；STAGE 2 的並行任務由 planner 在計畫中標好各自的檔案 scope。
2. **共享資源指定唯一 owner**：`pubspec.yaml`、DI 註冊、generated files 等共享檔案，只能指定**一個**並行單元修改。若多個任務都需動到同一共享檔 → 不可並行，退回序列。
3. **結果聚合與失敗短路**（這是契約核心）：

| 情境 | 行為 |
|---|---|
| 全部並行單元成功 | 收斂所有結果 → 統一在暫停點展示 → 問使用者確認 |
| 部分失敗，失敗單元與成功單元**無依賴** | 不中止其他單元（讓它們跑完）→ 聚合時明確標出哪些成功哪些失敗 → 失敗者進入 retry（見下方退回路徑） |
| 部分失敗，且有其他單元**依賴失敗單元的產出** | 立即短路：停止依賴鏈下游，已完成的保留，回報使用者「X 失敗，已暫停依賴它的 Y、Z」 |
| context 在並行中途超標 | 等當前所有並行單元跑完（不切在半途）→ 才執行 Token Gate 的切 session 閉環 |

### 退回路徑（失敗 retry 迴圈）

並行單元（或單一任務）失敗時，**不可無限重試**。
針對實作/邏輯錯誤，採用「同 tier 重派失敗 2 次 → 升一級 tier 再試 1 次」的漸進升級策略（硬性限制最多升級一次）：

```text
失敗單元 → 分析原因
  ├─ context 不足  → 補 context，重派同 model（最多 1 次）
  ├─ 任務過大      → 拆成更小單元，重新並行/序列
  ├─ 計畫本身有誤  → 退回 planner（STAGE 0b），不在 STAGE 2 硬修
  └─ 邏輯/實作失敗（重試與升級機制）：
       1. 同 tier (當下 model) 重派，最多失敗 2 次。
       2. 失敗 2 次後，判斷是否已為最高 tier (Opus, xHigh effort)：
          - 若是 → 停止，回報使用者，等決策（不自動繼續）。
          - 若否 → 將該任務升級一級 tier（例：快/便宜 → 標準，或標準 → 最強），再試 1 次。
       3. 升級後若仍失敗 → 停止，回報使用者，等決策（不自動繼續）。
```

> **Tier Upgrade 紀錄：** 當觸發 tier 升級時，必須在進度回報行中明確註記（例如：`[任務 N 升級至 標準 model]`），讓使用者知悉該任務正動用更高成本嘗試解決。

**與 STAGE 3 退回的關係：** STAGE 2 內部失敗在 STAGE 2 內 retry；STAGE 3 審查不通過才退回 STAGE 2 整體重做。兩者是不同層級的迴圈，不可混用。

---

## 用 Claude Workflow 執行並行（可選加速層）

**僅在使用者已 opt-in 多 agent 編排時啟用**（見開頭「Claude Workflow 編排」總則）。未 opt-in → 三處全部退回原本的 `Task(...)` / 序列作法。

共通鐵則（與「並行三規則」一致，違反即退回序列）：
- 一個 `Workflow` 呼叫 = **一段不可中斷的 fan-out**，跑完才回到主對話。**暫停點永遠在 Workflow 呼叫之外**，由主指揮掌控。
- Workflow 回傳結構化結果後，主指揮負責**聚合、套用 model 策略、寫 state 檔、在既有暫停點展示**。Workflow 內部不碰 state 檔、不問使用者。
- 用 `pipeline()` 為預設；只有「下一步需要前一步全部結果」時才用 `parallel()` barrier。
- 共享檔（`pubspec.yaml`、DI 註冊、generated files）只能有唯一 owner；多任務搶同一檔 → 不可並行，退回序列。

### 適用點 1：STAGE 0a 雙線 context 收集

兩條唯讀調查（A. 專案 context 讀檔/git log｜B. 相似功能代碼調查），無依賴、不寫檔 → 天然安全的 `parallel()` barrier，收斂後才交給 planner 撰寫規格。

```js
// meta 省略；agentType 用 Explore（唯讀搜尋）但強制指定 model 與 effort 覆蓋
const [projCtx, similarCode] = await parallel([
  () => agent('收集專案 context：讀 README / pubspec / 近期 git log，回報架構與慣例', {agentType: 'Explore', model: 'sonnet', effort: 'high', schema: CTX_SCHEMA}),
  () => agent('調查與「<需求>」相似的既有實作，回報可參考的檔案與模式', {agentType: 'Explore', model: 'sonnet', effort: 'high', schema: CTX_SCHEMA}),
])
// 回到主對話：planner 收斂 projCtx + similarCode → 撰寫 docs/features/...md → 暫停確認（不在 Workflow 內）
```

### 適用點 2：STAGE 2 同批獨立任務

planner 已在計畫中標好各任務的**寫入檔案 scope** 與**複雜度等級**。同一批內「寫入路徑不重疊」的任務 → `pipeline()` 並行，**每個任務沿用原本的逐任務 model 分級**（`opts.model` 帶入計畫標註的等級）；**effort 需另外依推論等級表帶入**（`opts.model` 只管 model，不會連帶設定 effort）。

```js
// batch = 當前批次中路徑不重疊的任務；model/effort 來自計畫的複雜度標註（等級 → 綁定見「推論等級表」）
// 驗收固定走 verifier agent + effort: 'xhigh'（frontmatter 只綁 model，effort 不隨實作任務浮動，需顯式帶）
const results = await pipeline(
  batch,
  task => agent(task.prompt, {label: task.id, model: task.model, effort: task.effort, isolation: 'worktree', schema: TASK_SCHEMA}),
  (impl, task) => agent(`驗收任務 ${task.id}：跑測試、檢查 diff`, {label: `verify:${task.id}`, agentType: 'verifier', effort: 'xhigh', schema: VERIFY_SCHEMA}),
)
// 回到主對話：聚合 results → 寫 state（completed_tasks）→ 在「每批完成」暫停點展示 → 問使用者確認下一批
```

> 邊界：**批與批之間的暫停由主指揮控制**，不可把多批塞進同一個 Workflow 連續跑完（那會跳過暫停點）。並行任務改檔時用 `isolation: 'worktree'` 避免互踩工作區。

### 適用點 3：STAGE 3 多 angle 對抗式審查

**reviewer 仍是主導者、最終判斷者**（不違反「審查報告 reviewer 親自判斷」）。Workflow 的 verifier 只是平行找 bug 的助手：每個 verifier 帶**不同 lens**（correctness / security / 回歸風險 / 測試覆蓋 / 過度工程），對抗式地嘗試挑出問題，reviewer 收斂所有 verdict 後親自寫審查報告。

```js
const LENSES = ['correctness', 'security', '回歸風險', '測試覆蓋']
// 每個 lens 都是審查的一部分，effort 對齊 STAGE 3 的最強推論——不是任意選填。
const findings = (await parallel([
  ...LENSES.map(lens => () =>
    agent(`以 ${lens} 視角審查 <branch> 的 diff，盡力挑出真實問題`, {label: `review:${lens}`, effort: 'xhigh', schema: FINDING_SCHEMA})),
  // 第五 lens：找「不該存在的東西」。verifier 子進程看不到 ponytail hook，判準必須明文內嵌。
  () => agent(`以「過度工程/可簡化」視角審查 <branch> 的 diff 對照已確認的 plan：挑出計畫沒要求卻新增的抽象（單一實作的 interface、單一產品的 factory、永不變的 config、留給未來的 scaffolding、可用既有 helper/stdlib 取代的自製輪子）。每條 finding 必附刪除方案（刪哪些行、刪後 diff 是否更小、既有測試是否仍過）。絕不把信任邊界輸入驗證、防資料遺失、security、a11y 列為可簡化項。`,
    {label: 'review:過度工程', effort: 'xhigh', schema: FINDING_SCHEMA}),
])).filter(Boolean).flatMap(r => r.findings)
// 回到主對話：reviewer 親自收斂 findings、去重、判定真偽 → 寫審查報告 → 暫停展示（不委派）
```

> 不變式：審查報告由 reviewer（最強推論）親自產出，**不委派**。多 angle 只是提高召回率的輸入，不取代 reviewer 的最終判斷。退回 STAGE 2 的條件與層級不變。
>
> 「過度工程/可簡化」lens 的 finding 屬獨立類別：僅「plan 未要求的新抽象」或「刪除即嚴格更小 diff 且測試仍過」兩種情況可列 Important 並觸發退回 STAGE 2；其餘列為非阻擋建議。與 correctness/security 衝突時後者勝出。（reviewer 收斂判準詳見 `reviewer.md`。）

---

## Quick Commands

| Command | Stage | Action |
|---------|-------|--------|
### 一、啟動型（決定 mode）

| Command | Mode | Action |
|---------|------|--------|
| `幫我做 <描述>` ／ `/gen-dev-workflow` | `sequence` | 完整流程 0a→4（**預設**）：產 spec+plan、建 worktree、拆任務、verifier 驗收、多 lens 審查 |
| `開發 issue #<id>` ／ `處理 #<id>` | `sequence` | 同上，但跳過 0a/0b（規格已在 issue 內） |
| `/gen-dev-workflow quick <描述或 #issue>` | `quick` | 小修正快速通道：單暫停點、不建 worktree、不產規劃文件。限 ≤3 檔（見「Quick 模式」章節） |
| `/gen-dev-workflow batch <項目1> <項目2> ...` | — | 批次佇列：多項**各自** worktree/branch/PR 依序執行（見「批次模式」章節） |

### 二、續接／管理型

| Command | Action |
|---------|--------|
| `繼續` ／ `繼續上次` | 接續本 session 或當前 branch 的未完成流程 |
| `繼續批次` | `/clear` 後於新 session 接續批次的下一項 |
| `停止批次` | 中止批次（只刪佇列檔，branch/PR/worktree 保留） |
| `PR #<id> 合併了，清理 worktree` | STAGE 6：同步文件 → commit → 移除 worktree（branch 保留） |

### 三、跳入型（`mode: jump`）

| Command | Stage | Action |
|---------|-------|--------|
| `/gen-dev-workflow spec <description>` | 0a | 撰寫功能規格 |
| `/gen-dev-workflow plan <spec-path>` | 0b | 產出實作計畫 |
| `/gen-dev-workflow branch <issue>` | 1 | 建立 Issue + Worktree |
| `/gen-dev-workflow implement <plan-path>` | 2 | 執行實作 |
| `/gen-dev-workflow code-review <branch>` | 3 | 執行代碼審查 |
| `/gen-dev-workflow publish <branch>` | 4 | 建立 PR |
| `/gen-dev-workflow review #<PR>` | 5 | 處理 PR review 意見 |
| `/gen-dev-workflow cleanup <branch>` | 6 | PR 合併後清理 worktree（branch 保留）|

### 四、選項：`--pause-level`（決定停幾次）

**與 mode 正交**——mode 決定「有哪些階段」，`pause_level` 決定「這些階段跑完要不要問使用者」。任何**啟動型**指令都可在最後加 `--pause-level strict|balanced|autonomous`（省略 → `strict`）：

```bash
幫我做 §P4 快速複製 Diagnostic Snippet --pause-level balanced
開發 issue #42 --pause-level balanced
/gen-dev-workflow batch "§P4 ..." "§P6 ..." --pause-level balanced
```

| level | Stage 關卡 | 任務間 | 停幾次 |
|---|---|---|:---:|
| `strict`（預設） | 全停 | 每個任務都停 | 2＋N |
| `balanced` | 只停 `0b` 計畫／`2` 實作整體／`4` PR 前 | 不停 | 3 |
| `autonomous` | 全不停 | 不停 | 0 |

**等價的自然語言**（不想打選項時，下列說法一律解析為對應 level）：

| 使用者說 | 解析為 |
|---|---|
| 「中途不要問我」「不要停」「一路跑完」 | `balanced` |
| 「完全不要問」「全自動」「無人值守」 | `autonomous`（⚠️ 須先警示，見下） |
| 「每步都讓我確認」「盯緊一點」 | `strict` |

**流程中途改變粒度**：使用者說「接下來不要再問了」→ `wf-state.sh set <檔> pause_level=balanced`，即刻生效於後續暫停點。

🔴 **選 `autonomous` 前必須先警示一次**：「這會讓 `gh pr create` 不經你過目直接執行，確定嗎？」——獲明確同意才寫入。這是唯一在設定階段就要確認的 level，因為它關掉的是對外動作的最後一道關卡。

⚠️ **`quick` + `balanced` 無作用**：quick 不拆任務（無 task 迴圈可關）、stage 是自由標籤（不匹配 `0b`/`2`/`4`），腳本會明示短路回 `strict`（`wf-state.sh:146-148`）。只有 `autonomous` 對 quick 有實效——關掉它唯一的 PR 暫停點。使用者若對 quick 指定 `balanced`，**直接告知無差別**，不要假裝有效果。

### 組合速查

| 需求 | 指令 |
|---|---|
| 改個字串、≤3 檔 | `/gen-dev-workflow quick <描述>` |
| 新功能，想全程盯著 | `幫我做 <描述>`（什麼都不加） |
| 新功能，計畫看過就放手 | `幫我做 <描述> --pause-level balanced` |
| 多個獨立需求、各自 PR | `/gen-dev-workflow batch "<A>" "<B>" --pause-level balanced` |
| `/gen-dev-workflow cleanup <branch>` | 6 | PR 合併後清理 worktree（branch 保留）|

---

## 跳入特定階段

所有跳入指令都以 `mode: "jump"` 寫入狀態檔。以下每條「呼叫 X agent」都須依「推論等級表」明確帶 `effort` 參數（見該表旁的已知風險註記），本節在每條後方標註對應等級。

```
# 重新規劃功能規格（STAGE 0a）
/gen-dev-workflow spec <需求描述>
→ 寫入狀態檔 { stage: "0a", mode: "jump" }
→ 呼叫 planner agent 產出功能規格（effort: xhigh，最強推論）

# 重新產出實作計畫（STAGE 0b）
/gen-dev-workflow plan <spec 路徑>
→ 寫入狀態檔 { stage: "0b", mode: "jump", spec: "<spec 路徑>" }
→ 呼叫 planner agent 依規格產出實作計畫（effort: xhigh，最強推論）

# 只需要建 Issue + Worktree（STAGE 1）
/gen-dev-workflow branch <ISSUE-NUMBER>
→ 寫入狀態檔 { stage: 1, mode: "jump", issue: <ISSUE-NUMBER> }
→ 若需新建 Issue：先呼叫 gen-gh-issue skill 產出 Issue body（五區段 zh-tw）
→ 若 issue 已存在：brancher 依 ticket-id-dev-prep 規則解析既有 issue 內容為 brief
→ 呼叫 brancher agent（依 ticket-id-dev-prep 規則建立 worktree + branch，
  主對話 cd 進新 worktree；effort: high，輕量）

# 繼續實作（STAGE 2）
/gen-dev-workflow implement <plan 路徑>
→ 寫入狀態檔 { stage: 2, mode: "jump", plan: "<plan 路徑>" }
→ 呼叫 implementer agent（effort: max，標準；STAGE 2 逐任務再依複雜度分級）

# 只需要審查（STAGE 3）
/gen-dev-workflow code-review <branch-name>
→ 寫入狀態檔 { stage: 3, mode: "jump", branch: "<branch-name>" }
→ 呼叫 reviewer agent（effort: xhigh，最強推論）

# 只需要發 PR（STAGE 4）
/gen-dev-workflow publish <branch-name>
→ 寫入狀態檔 { stage: 4, mode: "jump", branch: "<branch-name>" }
→ 呼叫 publisher agent（內部用 gen-pr skill 產 PR 描述，再 push + gh pr create；effort: high，輕量）

# 處理 PR review 意見（STAGE 5）
/gen-dev-workflow review #<PR>
→ 推進/寫入狀態檔：
  - 既有工作區：wf-state.sh advance <state_file> 5 --confirmed
  - 新對話 jump：wf-state.sh init --mode jump --stage 5 --branch <branch-name> --set pr=<PR>
→ 呼叫 responder agent 處理所有 review 意見（effort: high，輕量）
→ 處理完畢後呼叫 reviewer agent 重新審查（effort: xhigh，最強推論）
→ 審查通過後呼叫 publisher agent 更新 PR 描述與留言（effort: high，輕量）
→ 呼叫 wf-state.sh stage-done 5 結束 STAGE 5

# PR 合併後清理 worktree（STAGE 6）
/gen-dev-workflow cleanup <branch-name>
→ 推進/寫入狀態檔：
  - 既有工作區：wf-state.sh advance <state_file> 6 --confirmed
  - 新對話 jump：wf-state.sh init --mode jump --stage 6 --branch <branch-name>
→ 呼叫 gen-sync-docs-by-branchs skill，以 <branch-name> 為目標同步文件
→ 同步完成後呼叫 gen-commit skill 將文件變更 commit（避免清理 worktree 時遺失）
→ 呼叫 worktree-close-cleanup skill 移除該 branch 對應的 worktree
→ 只移除 worktree，branch 本身保留不刪除（純 IO，無 model/effort 可調）
→ 呼叫 wf-state.sh stage-done 6（或標記 done）
```
