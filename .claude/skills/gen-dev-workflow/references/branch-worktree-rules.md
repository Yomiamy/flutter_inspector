# 分支與 Worktree 建立（STAGE 1 統一規則）

STAGE 1 建立分支與工作區時，**不論從哪個入口進來**，最後一步一律沿用 `ticket-id-dev-prep` skill 的 prefix/slug/worktree 規則，避免命名邏輯在兩個 skill 裡各寫一套。

## 兩種入口，同一套收斂邏輯

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
6. **主對話切換工作目錄**：後續 STAGE 2–4 的所有 Bash 指令與檔案操作都在新 worktree 路徑下執行，state 檔（見 `references/state-machine.md`）也寫在新 worktree 內的 `.claude/workflow-state/`，與主 repo 分開、互不干擾。

## 與 STAGE 2 並行任務用的 `isolation: 'worktree'` 的區別

`references/workflow-parallel.md` 提到的 `agent(..., {isolation: 'worktree'})` 是**子 agent 層級**的臨時隔離（跑完自動清除，不留存），只用來避免 STAGE 2 並行任務互踩工作區；這裡的 STAGE 1 worktree 是**整個 workflow 的長駐工作區**，直到 PR 合併都持續存在，兩者不是同一回事，不要混用。
