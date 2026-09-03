# gen-dev-workflow 全階段分析報告

> **📝 更新紀錄 (Changelog)**：
> * **2026-09-04**：補上三處文件從未涵蓋的既有機制，並更新兩項因此失效的判斷。(1) 新增「Hook 強制層」章節——四個已註冊 hook（`wf-guard-stage-check`、`wf-guard-delegate-cwd` pre/post、`cbm-reindex-on-pr`）此前在本文件 0 次提及，其中兩個直接強制本 workflow 自身的規則；(2) 新增 batch 批次模式（此前僅 quick 模式有專節）；(3) 新增「Claude Workflow 編排」可選加速層。連帶修正：「委派後端依賴」缺點中「工作目錄靠 prompt 約束，屬文件層自律而非程式強制」一句已被 `wf-guard-delegate-cwd` 推翻，改為「pre 端已程式強制」；「最危險的假設」補上 hook 層作為第二道非自律防線。新增流程總覽圖連結。
> * **2026-08-12**：PR review 回應階段的一致性修正（PR #126）。四處敘述本身自相矛盾，非新增功能：(1) STAGE 2 驗收責任人在 `implementer.md`、SKILL.md、本文件三處定義不一，統一為「委派 verifier 做兩階段驗收、implementer 只複核」；(2) STAGE 6 清理執行模型在本文件表格、mermaid 圖 E6/F6、SKILL.md 摘要表之間矛盾，統一為「主對話執行、不委派」；(3) `publisher.md` 唯讀派發同時宣稱「不得跨出目錄」又說明會讀全域 CLAUDE.md，改為誠實描述限制；(4) `brancher.md` 重試對帳規則原寫「找到既有資源就復用」，與 `ticket-id-dev-prep`「已存在則停止回報」衝突，收緊為「僅復用能證明屬於本次嘗試的資源」。
> * **2026-08-10**：**委派後端由 `agy -p` headless 改為 `gemini-mcp-tool`（MCP）**。底層後端不變（仍是 antigravity-cli），換掉的是傳輸層——`agy -p` 不吃 stdin、權限卡死，委派實際一律落到 fallback；MCP 路徑實測可寫檔、可跑 shell、可 `git commit`。同步更新各 stage 委派欄、Model 策略、缺點表「agy 依賴」項，新增 MCP 路徑的三條委派紀律與已知限制。
> * **2026-08-06**：同步 SKILL.md 變更——STAGE 6 新增「文件同步」前置步驟（gen-sync-docs-by-branchs → gen-commit），確保 worktree 清理前 docs 已反映分支最終狀態。更新 STAGE 6 表格、委派規則、優缺點分析。
> * **2026-07-30**：同步審查 SKILL.md（含 `acf4f70` 新增的 STAGE 1 規劃文件搬移步驟）。STAGE 1 新增「帶入規劃文件」步驟、補記 Bug 1.6、更新總覽與優缺點分析。
> * **2026-07-21**：建立初版（從 `docs/features/` 移至 `docs/architecture/`）。

## 總覽

> 📊 **視覺化總覽**：[`2026-09-04-gen-dev-workflow-flow.html`](2026-09-04-gen-dev-workflow-flow.html)（同目錄，瀏覽器開啟）——一張圖涵蓋主路徑、sub-agent 的 model/effort、MCP 委派點與 hook 攔檢層。本文件是文字分析，該圖是流程總覽，兩者互補。

`gen-dev-workflow` 是一個**全自動開發流程編排器**，從使用者說「幫我做 X 功能」到 PR 建立，共 6 個 stage（0a → 0b → 1 → 2 → 3 → 4），外加兩個獨立入口的 STAGE 5（回覆 PR review）與 STAGE 6（PR 合併後清理 worktree），以及小修正用的 **quick 模式**（單暫停點快速通道，不建 worktree）。核心機制是 **Claude 做總指揮 + `gemini-mcp-tool`（MCP）做委派執行**。自 STAGE 1 起，整條流程搬進一個獨立 worktree 執行——worktree 才是真正的隔離邊界。

> **📌 委派後端的傳輸層變更（2026-08-10）**：後端一直是 antigravity-cli，但**傳輸層由 `agy -p` headless 改為 MCP 工具 `mcp__gemini-cli__ask-gemini`**。原因：`agy -p` 不吃 stdin、權限會卡死（見 [`brainstorm §2.3`](../brainstorm/2026-08-25-workflow-brainstorm.md)），委派實際一律落到 fallback，「委派」名存實亡。MCP 路徑經實測可寫檔、可改既有檔、可跑 shell 與 `git commit`，是同一後端唯一能真正委派的通道。
>
> **MCP 路徑的三條紀律**（因 MCP 無法指定 cwd 而必要）：
> 1. **工作目錄寫死在 prompt**——不寫絕對路徑，子進程可能在主 repo 而非 worktree 動手。
> 2. **跨出工作目錄先問**——派發 prompt 明令：需存取／修改該目錄外的檔案時停止回報，不自行動手。
> 3. **回報不等於事實**——子進程宣稱「已 commit」須由主對話親自 `git log` / `git status` 驗證。
>
> ⚠️ **已知限制**：MCP 呼叫無法帶 `--print-timeout`，長任務無逾時控制，需靠拆小任務規避。

Model 別名**綁在各 agent 檔 frontmatter**（`.claude/agents/*.md`，用 `opus`/`sonnet` 別名），而 **effort 參數已從 frontmatter 中全數移除**，改為在**派發任務時顯式帶入**。SKILL.md 定義了**推論等級表**（對應的 model 與 effort 參數），以此維持不同 stage 之間的差異化配置。

---

## 各階段詳細分析

### STAGE 0a：功能規格（What & Why）

| 項目 | 內容 |
|------|------|
| **Agent** | planner |
| **Model** | 最強推論（planner frontmatter：`model: opus`；派發時帶入 `effort: xhigh`） |
| **委派** | 無委派，Claude 親自執行 |
| **並行** | 🟢 並行 2 條線：A. 專案 context 收集（讀檔 / git log）B. 相似功能代碼調查 |
| **產出** | `docs/features/YYYY-MM-DD-<feature>.md`（使用者故事、驗收條件、範圍邊界） |
| **暫停點** | ⏸ 展示規格 → 等使用者確認 |

**執行工作：**
1. 接收使用者需求描述
2. 並行啟動兩個研究任務（唯讀，不寫檔）
3. 收斂研究結果，撰寫功能規格文件
4. 暫停等待確認

---

### STAGE 0b：實作計畫（How）

| 項目 | 內容 |
|------|------|
| **Agent** | planner |
| **Model** | 最強推論（planner frontmatter：`model: opus`；派發時帶入 `effort: xhigh`） |
| **委派** | 無委派 |
| **並行** | 無 |
| **產出** | `docs/plans/YYYY-MM-DD-<feature>.md`（資料結構、檔案異動、任務拆分 + 複雜度標註） |
| **暫停點** | ⏸ 展示計畫 → 等使用者確認 |

**執行工作：**
1. 讀取 STAGE 0a 確認後的功能規格
2. 分析 codebase 結構
3. 拆分任務、標註複雜度等級（供 STAGE 2 model 選擇用）
4. 撰寫實作計畫文件
5. 暫停等待確認

---

### STAGE 1：建立 Issue + Worktree

| 項目 | 內容 |
|------|------|
| **Agent** | gen-gh-issue skill + brancher |
| **Model** | 輕量（brancher frontmatter：`model: sonnet`；派發時帶入 `effort: high`）——純 IO，且建立前有暫停點人肉把關 |
| **委派** | ✦ MCP 執行 `gh issue create/view` + `git worktree add` + `flutter pub get`（`gh issue create` 須先過暫停點） |
| **並行** | 無 |
| **產出** | GitHub Issue + Git 分支 + **獨立 worktree** |
| **暫停點** | ⏸ 展示 Issue 標題/內容 + 分支/worktree 名稱 → 等使用者確認或修改 |

**執行工作：**
1. 取得 Issue 內容（正常路徑用 gen-gh-issue 產五區段 body；issue-id 路徑用 `gh issue view <id>` 解析既有 issue）
2. 依 `ticket-id-dev-prep` 規則決定 branch prefix + slug，草擬分支/worktree 名稱
3. 暫停讓使用者確認/修改
4. 確認後由 brancher 建立 **worktree + branch**（`git worktree add -b <branch> <worktree-path> origin/main`），主對話 `cd` 進新 worktree 繼續後續所有 stage

**Worktree 命名與落地：** worktree 目錄為 `.claude/worktrees/<repo-name>-<ISSUE-ID>-<slug>`，建在當前 repo 內的 `.claude/worktrees/` 下，base 預設 `origin/main`。branch 名稱 `<prefix>/<ISSUE-ID>-<slug>`（prefix 含 `YYYYMM`）。若目標 branch 或 worktree 路徑已存在則停止回報，不默默重用或覆蓋。這個 worktree 是**整個 workflow 的長駐工作區**；主流程（STAGE 1–4）全程只用不刪，連 PR 合併都不會自動清除——要等使用者手動觸發 STAGE 6 才移除（刻意不自動清，避免 PR 合併後仍需修改時誤刪工作區）。

**🔴 帶入 STAGE 0a/0b 產出的規劃文件（正常路徑必做）：** 功能規格與實作計畫是在原 repo 目錄產出的未 commit 檔案，新 worktree 從 `origin/main` 拉出來時不會有它們。建好 worktree 後、`cd` 進去之前，用 `cp` 將 spec 與 plan 檔複製到新 worktree 的同名路徑，並驗證兩檔都存在。用複製不用 commit + cherry-pick（規劃文件由 STAGE 2 的 commit 一併帶進 branch）；原 repo 的那兩份留著不刪；issue-id 路徑略過本步驟。

**與 STAGE 2 臨時 worktree 的區別：** STAGE 1 的 worktree 是整個 workflow 的長駐工作區；STAGE 2 並行任務用的 `isolation: 'worktree'` 只是子 agent 層級的臨時隔離（跑完自動清除、不留存），僅避免並行任務互踩工作區，兩者不是同一回事。

---

### STAGE 2：實作（核心 Stage）

| 項目 | 內容 |
|------|------|
| **Agent** | implementer |
| **Model** | 實作動態分級（見下表）｜驗收走 verifier agent（最強推論） |
| **委派** | ✦ MCP 負責代碼 + 測試 + commit；驗收委派 verifier agent（frontmatter：`model: opus`；且必須顯式帶入 `effort: xhigh`） |
| **並行** | 🟢 條件式並行（≥2 獨立任務且寫入路徑不重疊） |
| **產出** | 實作代碼 + 測試 + commits |
| **暫停點** | ⏸ 每個任務/每批並行完成後展示變更 + 測試結果 → 等確認 |

> **⚠️ implementer 只是協調者（Orchestrator Mode）：** `implementer` agent frontmatter 標題即為 `# Implementer (Orchestrator Mode)`，設計上是「工頭」角色——**本身不親自寫代碼**，而是把每個任務的「TDD 寫測試 → 實作 → 語意化 commit」透過 `mcp__gemini-cli__ask-gemini` 委派出去，自己只負責委派 verifier agent 做兩階段驗收（spec compliance → code quality）並複核其結論。因此上表「Model：實作動態分級」指的是**委派後端的 model**，不是 implementer 自己跑的推論等級；implementer 在 orchestrator 模式下幾乎不吃推論成本，Token 都花在委派側與 verifier 驗收。
>
> **唯一例外——MCP 不可用時的 Fallback：** implementer 退回 `subagent-driven-development` skill **親自逐任務實作**（仍守 TDD → 實作 → commit 順序）。此時它就不再只是協調者，而是實際執行者，實作推論成本改由 implementer 自身承擔。這條 Fallback 是 STAGE 2「協調者假設」失效的唯一情境，判讀成本/效能時需區分兩種模式。
>
> **📌 2026-08-10 之前，這條「例外」其實才是常態：** `agy -p` headless 不可用，委派一律落到 fallback——所謂的 orchestrator 模式在舊路徑下形同虛設。改走 MCP 後，協調者假設才第一次真正成立。

**Model 動態分級（STAGE 2 內部，僅指「委派後端寫代碼」的 model）：**

| 任務複雜度 | 委派等級 | 範例 |
|-----------|-----------|------|
| 觸及 1–2 檔、規格完整、機械性 | 快/便宜（委派後端內部 fast model） | 新增 DTO 欄位、補 util function |
| 觸及多檔、需整合協調 | 標準 | 跨 service 串接、改既有流程 |
| 需設計判斷或廣泛 codebase 理解 | 最強推論 | 重構狀態機、新增跨層架構 |

> **驗收與實作分離**：上表是「委派後端寫代碼」用的浮動等級；**驗收固定委派 verifier agent**（frontmatter：`model: opus`；且必須顯式帶入 `effort: xhigh`），不隨實作任務浮動。刻意讓驗收等級 ≥ 實作等級，避免產代碼的便宜 model 自審（與 STAGE 3 同源交叉檢查的邏輯一致）。

**執行工作：**
1. 解析實作計畫，判斷並行/序列模式
2. 逐任務（或並行批次）透過 MCP 分派
3. 委派 verifier agent（最強推論）做兩階段驗收：spec compliance → code quality
4. 每個任務完成後暫停展示結果
5. 失敗時進入 retry 迴圈（最多 2 次重派）

**並行契約（三規則）：**
1. 每個並行單元有明確寫入檔案清單
2. 共享資源（pubspec.yaml、DI 註冊等）只能有一個 owner
3. 結果聚合 + 失敗短路機制

---

### STAGE 3：審查

| 項目 | 內容 |
|------|------|
| **Agent** | reviewer |
| **Model** | 最強推論（reviewer frontmatter：`model: opus`；派發時帶入 `effort: xhigh`）——根因判斷 |
| **委派** | **不委派**（審查不可外包） |
| **並行** | 無 |
| **產出** | 審查報告 |
| **暫停點** | ⏸ 展示報告 → 通過則進 STAGE 4，不通過則退回 STAGE 2 |

**執行工作：**
1. reviewer agent 親自審查所有變更
2. 產出審查報告
3. 不通過 → 退回 STAGE 2 修正 → 再回 STAGE 3（迴圈）

**設計考量：** 審查用最強推論是為了避免「自己審自己」（實作走標準或更便宜等級，reviewer 刻意用不同源的最強推論交叉驗證）。

---

### STAGE 4：發布

| 項目 | 內容 |
|------|------|
| **Agent** | publisher |
| **Model** | 輕量（publisher frontmatter：`model: sonnet`；派發時帶入 `effort: high`）——重活已委派，發布前有暫停點人肉把關 |
| **委派** | ✦ MCP 分析 Diff → 產 PR 草稿（唯讀）；Claude 校對；`gh pr create` 不委派 |
| **並行** | 無 |
| **產出** | GitHub PR |
| **暫停點** | ⏸ 展示 PR 草稿 → 等使用者確認發布 |

**執行工作：**
1. 委派分析 branch diff，生成 PR 描述草稿
2. Claude 校對草稿品質
3. 暫停讓使用者確認
4. 確認後發布 PR

---

### STAGE 5：回覆 PR Review（獨立入口）

| 項目 | 內容 |
|------|------|
| **Agent** | responder → reviewer → publisher |
| **Model** | 輕量（responder，帶 `effort: high`）→ 最強推論（reviewer，帶 `effort: xhigh`）→ 輕量（publisher，帶 `effort: high`） |
| **委派** | 無委派 |
| **並行** | 無 |
| **觸發** | 使用者說「PR #42 有新的 review 意見」 |

**執行工作：**
1. responder 逐條處理 PR review 意見
2. reviewer 重新審查修改
3. publisher 更新 PR

---

### STAGE 6：清理 Worktree（獨立入口）

| 項目 | 內容 |
|------|------|
| **Agent** | gen-sync-docs-by-branchs → gen-commit → worktree-close-cleanup skill |
| **Model** | —（skill 於主對話執行，無獨立綁定） |
| **委派** | 不委派——主對話親自執行 `git worktree remove`，事後驗證 `git worktree list` / `git branch --list` |
| **並行** | 無 |
| **產出** | docs 同步更新 + commit → 移除 STAGE 1 建立的 worktree（**對應 branch 一律保留、不刪除**） |
| **觸發** | PR **實際合併後**，使用者說「PR #42 合併了，清理 worktree」 |

**執行工作：**
1. 呼叫 gen-sync-docs-by-branchs skill，以當前處理的分支為目標，將該分支的實際變更回寫到 docs 下的發想／結構說明文件（brainstorm、architecture 等）
2. 同步完成後呼叫 gen-commit skill 將文件變更 commit 進 git（避免同步結果在清理 worktree 時遺失）
3. 呼叫 worktree-close-cleanup skill 移除 STAGE 1 建立的 worktree
4. 只移除 worktree 本身，對應 branch 保留不刪除（沿用 worktree-close-cleanup 既有規則）
5. 完成後流程結束

**設計考量：**
- **先 sync 再 commit 再清理**的順序是必要的——worktree 一旦 `remove`，裡面未 commit 的文件變更就永久遺失。gen-sync-docs-by-branchs 本身不 commit（見其鐵律），所以中間必須顯式呼叫 gen-commit 銜接。
- 不自動觸發——workflow 不偵測 PR 合併狀態並自動清理，需使用者明確告知已合併才執行，避免 PR 還可能需要修改時誤刪工作區。

---

### Quick 模式：小修正快速通道（獨立入口）

| 項目 | 內容 |
|------|------|
| **觸發** | `/gen-dev-workflow quick <描述或 #issue>`、「快速修正 <描述>」 |
| **適用** | 預期 diff 小（約 ≤3 檔）、無架構變動、無新依賴、不需規劃文件 |
| **流程** | 建 branch（不建 worktree）→ 主對話直接實作（不委派 implementer/MCP）→ reviewer 單 lens 快掃 → gen-pr 產草稿 → 發布 |
| **暫停點** | 只有一個：PR 草稿確認前 |
| **State** | 照寫 `<branch-slug>.json`（`mode: "quick"`），續接與 PR MERGED 自動刪檔複用既有機制 |

**設計考量：**
- 砍掉所有儀式（spec/plan 文件、issue 強制、worktree、逐任務暫停），唯一保留的品質閘門是 **reviewer 交叉審查**——「不讓同源 model 自審」是整條 workflow 不可砍的不變式。
- 不建 worktree ⇒ 同一 repo 同時只能跑一個 quick；需要多並行走完整流程。
- 中途發現超出小修正範圍（多檔設計判斷、新依賴、動架構）→ 停下告知並執行 `wf-state.sh upgrade` 轉入完整流程。**升級後必須立即建立對應的 git worktree，複製 Root 未 commit 變更並 promote 狀態 JSON，最後 cd 進入該工作區**，以防打破物理隔離的鐵律。

---

### Batch 模式：多需求依序執行（佇列，非 mode）

| 項目 | 內容 |
|------|------|
| **觸發** | `/gen-dev-workflow batch <項目1> <項目2> ...`、「依序做完這幾項」、「繼續批次」 |
| **本質** | **佇列類型，不是 mode**——批次的每一項各自跑完整的 `sequence` 流程（各自 worktree / branch / PR） |
| **狀態** | `.batch-<id>.json`（存原 repo 的 `.claude/workflow-state/`），與各項自己的 state 檔分離 |
| **指令** | `batch-init` → `batch-next` → `batch-done` / `batch-fail` → `batch-abort` |
| **關鍵限制** | **每項之間需使用者 `/clear` 換新 context**，再說「繼續批次」接下一項 |

**設計要點：**

- **`pause_level` 與批次佇列是正交的兩個控制粒度**——前者決定「每個 stage 跑完要不要問」，後者決定「有幾項要跑」。`batch-init` 可帶 `--pause-level balanced` 一次設定全批。
- **一項失敗不中止整個批次**：某項失敗（STAGE 3 連續退回、tier 升級後仍失敗）→ `batch-fail --note "<原因>"`，游標照常前進。各項獨立，沒有理由讓後面的陪葬；最終總結列出失敗項讓使用者決定要不要重跑。
- **`cd` 紀律**：每項跑完必須 `cd` 回原 repo 再收尾，否則下一項的 `batch-next` 會在錯誤的工作目錄找不到批次檔。這是批次模式特有的踩雷點。
- **中止**：`batch-abort` 只刪批次檔，**已建立的 branch / PR / worktree 一律保留**（沿用「branch 永不自動刪除」的既有紀律）。
- `batch-next` 回傳 `DONE` 後才刪批次檔，並輸出總結表（項目 / status / PR 連結 / 失敗原因）。

> **為何需要 `/clear`**：批次的價值在於「一次交代多個需求」，但每項跑完整流程都會累積大量 context。不 clear 就接著跑第二項，等於把 Token Budget Gate 的問題乘上項數。這是刻意的人工介入點，不是缺陷。

---

## Claude Workflow 編排（可選加速層）

流程中**特定的並行、唯讀或路徑不重疊、且該段落內部不需要問使用者**的環節，可改用 Claude `Workflow` 工具（JS 腳本 fan-out 多 subagent）執行，取代逐個 `Task(...)` 串接。

**適用點只有三處**：STAGE 0a 雙線 context 收集、STAGE 2 同批獨立任務、STAGE 3 多 angle 對抗式審查。

| 邊界 | 規則 |
|---|---|
| **前置條件** | 使用者需明確 opt-in（說「ultracode」「用 workflow」「多 agent」或類似）。未 opt-in → 三處一律退回原本的 `Task(...)` / 序列作法，功能完全相同，只是不 fan-out |
| **絕對禁止** | **不可把整條 orchestrator 包成單一 Workflow 腳本**——Workflow 背景執行、跑完才回，中途無法暫停問人，會直接摧毀本流程的所有暫停確認點 |
| **暫停點歸屬** | Workflow 只用於**單一段落內部**的 fan-out，暫停點永遠由主對話掌控、落在任何 Workflow 呼叫的外面。一個 Workflow 呼叫 = 一段不可中斷的並行 |
| **不變的部分** | state 檔、model 策略、委派規則完全不變——Workflow 只換「並行執行的載體」，不換流程語意 |

> STAGE 3 的多 angle 對抗式審查是這裡唯一會影響品質判斷的適用點：平行 verifier 只負責**找 bug 作為輸入**，reviewer 仍親自收斂判斷並產出報告——與「STAGE 3 審查報告不可委派」的硬規則不衝突。

---

## Model 與委派策略總覽

Model 別名綁在各 agent 檔的 frontmatter（`.claude/agents/*.md`），而 **effort 參數則在任務派發時顯式帶入**。

### 推論等級表（等級 → 綁定）：

| 等級 | model（frontmatter 綁定，未變） | effort（呼叫時明確帶入） | 綁定的 agent |
|------|-----------------|-------------|-------------|
| 最強推論 | `model: opus` | `effort: xhigh` | planner、reviewer、verifier |
| 標準 | `model: sonnet` | `effort: max` | implementer |
| 輕量 | `model: sonnet` | `effort: high` | brancher、responder、publisher |
| 快/便宜 | 委派後端內部 fast model（不在 Claude 側綁定） | — | STAGE 2 機械性任務 |

### 綁定原則：
- model 一律用**別名**（`opus`/`sonnet`），不綁版本 ID——CLI 自動解析到當代 model。這部分仍由 frontmatter 管理。
- effort **派發時必須明確帶入**：`Task("<agent>", ..., effort: "<本表對應值>")`。若不帶參數，子 agent 將預設繼承主對話 session 目前的 effort，這會導致 stage 間的差異化失效。
- Workflow `agent()` 呼叫：`agentType: '<agent 名>'` 仍沿用 frontmatter 的 model 綁定；effort 另用 `opts.effort` 依本表帶入。

> 🔴 **已知風險：`effort: 'xhigh'` 導致 400 錯誤**
> 曾有實測案例顯示，當 thinking 未開啟時，於 Opus 4.8 上呼叫 `effort: 'xhigh'` 可能會觸發 `400 output_config.effort 'xhigh' is not supported when thinking is disabled on this model`。若派發時遇到此錯誤，應暫時將該次呼叫的 effort 降為 `high` 以恢復可用性，切勿默默將全表降級。

```mermaid
graph LR
    subgraph "推論等級分配"
        A["STAGE 0a/0b<br/>最強推論"] --> B["STAGE 1<br/>輕量"]
        B --> C["STAGE 2<br/>動態分級"]
        C --> D["STAGE 3<br/>最強推論"]
        D --> E["STAGE 4<br/>輕量"]
    end

    subgraph "獨立入口"
        E6["STAGE 6 清理 Worktree<br/>主對話執行"]
    end

    subgraph "MCP 委派"
        B2["STAGE 1 ✦"] 
        C2["STAGE 2 ✦"]
        E2["STAGE 4 ✦"]
    end

    subgraph "不委派"
        A2["STAGE 0a/0b"]
        D2["STAGE 3"]
        F2["< 50 行小修"]
        G2["commit message"]
    end

    subgraph "Hook 強制層（非自律）"
        H1["wf-guard-delegate-cwd<br/>pre: exit 2 阻擋"]
        H2["wf-guard-stage-check<br/>未進 5 派 responder → 攔"]
        H3["cbm-reindex-on-pr<br/>PostToolUse(Bash)"]
    end

    B2 -.被攔檢.-> H1
    C2 -.被攔檢.-> H1
    E2 -.被攔檢.-> H1
```

### STAGE 6 委派規則
- STAGE 6 開始時先跑 gen-sync-docs-by-branchs（以當前分支為目標同步文件）→ gen-commit（將同步結果 commit），之後由主對話親自執行 `git worktree remove`（不委派 MCP，純 IO，只移除 worktree、不刪 branch）。文件同步確保 docs 在 worktree 被清理前已反映分支的最終狀態

### 不委派的硬規則
- commit message（直接依 diff 生成，省一次 context 來回）
- 單一檔案 < 50 行的小修正
- STAGE 3 審查報告（reviewer 親自判斷）

---

## Hook 強制層（程式化防線，非 LLM 自律）

除了 `wf-state.sh` 的狀態機棘輪之外，本流程還有第二道**不依賴 LLM 自律**的防線：註冊於 `.claude/settings.local.json` 的 hook。它們由 harness 在工具呼叫前後執行，LLM 無法繞過或「忘記呼叫」。

> **掛載位置是本地設定（`settings.local.json`），不進版控**——換機器或重裝需重新掛載，這本身是個殘餘風險。

| Hook | 事件 / matcher | 行為 | 阻擋力 |
|---|---|---|---|
| `wf-guard-stage-check.sh` | `PreToolUse` / `Agent` | 偵測派發 `responder` agent 時，若 state 檔的 stage 不是 5 → 阻擋 | 🔴 **exit 2 阻擋** |
| `wf-guard-delegate-cwd.sh pre` | `PreToolUse` / `mcp__gemini-cli__ask-gemini` | 檢查派發 prompt 是否含目標 worktree 絕對路徑，缺失／不符 → 阻擋；放行時順手存下主 repo 與其他 worktree 的 git status 快照 | 🔴 **exit 2 阻擋** |
| `wf-guard-delegate-cwd.sh post` | `PostToolUse` / `mcp__gemini-cli__ask-gemini` | 讀 pre 端快照做 before/after 差集，偵測目標 worktree 以外的實際寫入與新增 commit | 🟡 **只告警**（動作已完成，回捲無意義） |
| `cbm-reindex-on-pr.sh` | `PostToolUse` / `Bash` | 以 shlex tokenize 判斷是否為 `gh pr create` / `git push` / `git pull`，是則背景重建 codebase-memory 索引 | — （不阻擋） |

**設計要點：**

- **`exit 2` 是唯一有阻擋力的離開碼**——`PreToolUse` 的 `exit 1` 屬 non-blocking error，動作照跑。兩個 guard hook 的原始碼都留有這條註解（`wf-guard-delegate-cwd.sh:290` 標為「BUG-1 教訓」），是踩過坑後的修正。
- **這補上了 MCP 委派紀律第 1 條的程式強制**。「工作目錄寫死在 prompt」原本只是寫給另一個 LLM 看的道德勸說（Guide），`wf-guard-delegate-cwd` 的 pre 端把它變成確定性檢查（Sensor）——缺絕對路徑就進不去。
- **偵測範圍有邊界**：post 端建立在 `git status` 之上，只涵蓋主 repo 與已知 git worktree。寫入非 git 目錄（其他專案、家目錄普通檔案）偵測不到——涵蓋那些需要 fs-level 觀察，成本遠超本問題嚴重度，屬另案。
- **False positive 防護**：兩個 guard 都有多層放行條件（非目標工具、無 state 檔、branch 對不上、stage 不符、不在 worktree 中、路徑命中白名單），任一命中即 `exit 0`。設計上偏向「寧可漏擋也不誤擋」。
- `cbm-reindex-on-pr.sh` 用 token 化而非正則比對，所以 `git commit -m "add push button"` 的 subcommand 是 `commit`，引號內的 push 不會誤觸發。

> **⚠️ 與委派通道的耦合**：兩個 delegate guard 的 matcher 寫死 `mcp__gemini-cli__ask-gemini`。若日後再換委派傳輸層（如同 2026-08-10 從 `agy -p` 換到 MCP），**這兩個 hook 會靜默失效**——不報錯，只是不再攔截。同理 `cbm-reindex-on-pr.sh` 掛在 `Bash` 上，若 GitHub 操作改走 MCP 工具，索引就不再更新。換通道時必須同步檢查 hook matcher。

---

## 狀態持久化與 Token Budget Gate

### 狀態檔：每個 workflow 一個檔（存於各自 worktree，檔名用 branch）

state 不是單一檔，而是 `.claude/workflow-state/` 目錄下**每個 workflow 一個檔**：

```
<worktree-path>/.claude/workflow-state/<branch-slug>.json   ← 已建 worktree 的 workflow（STAGE 1 之後，存於新 worktree 內）
.claude/workflow-state/.pending-<wf-id>.json                ← 尚無 worktree 時的暫存（STAGE 0a / 0b，存於原 repo）
```

STAGE 1 之後的 state 檔存在**各自 worktree 內部**，不再是主 repo 的同一目錄——連檔名撞名的可能性都不存在。

- 每個 stage 完成後寫入對應 workflow 的檔
- 支援 `sequence`（完整流程）和 `jump`（跳入特定 stage）兩種模式
- 記錄 `interrupted_by` 欄位追蹤中斷原因
- 記錄 `workflow_id`（`wf-<epoch>-<rand4>`）作為 pending 階段的唯一識別

### 多 workflow 並行（隔離設計）

**隔離 key 分兩段：STAGE 0a/0b 靠 workflow-id、STAGE 1 之後靠獨立 worktree。** 同一 repo 可同時跑多個獨立 workflow（多終端 / 多 session）。自 STAGE 1 起每個 workflow 都在自己的 worktree 目錄裡，state 檔天然分開存放於各自 worktree 的 `.claude/workflow-state/`，彼此零衝突——不需要鎖、不需要中央索引。worktree 是比 branch 更徹底的隔離：工作目錄本身就分開，不是靠同一目錄切 branch。

唯一邊界是「兩個流程都還在 STAGE 0a/0b（尚無 worktree，仍在原 repo 目錄）」這個短暫窗口。此時多個並行 workflow 共用同一個原 repo 的 `.claude/workflow-state/`，branch 推導不出唯一檔，改靠 **workflow-id 持久化**識別：

| 機制 | 解決的問題 |
|------|-----------|
| `workflow_id` 寫進 `.pending-<wf-id>.json` 內容 | session 中斷後，pending 檔不再是無主孤兒，可被精準認領 |
| 進度行帶 `[<wf-id>]` / `[<branch-slug>]` 前綴 | 多個並行流程的輸出一眼可辨 |
| 狀態定位「先認 wf-id、再認 branch」 | 不再用 `git branch --show-current` 誤撿別人的 pending 檔 |
| `git worktree list` 跨工作區掃描 | 解決 Cross-Worktree State Blindness，重開 session 在 Root 時仍可尋獲子 worktree 中的狀態 JSON |

### Token Budget Gate

| Context 用量 | 行為 |
|---|---|
| < 60k | 正常流程 |
| 60–100k | ⚠️ 提示精簡，委派 agent 只回摘要 |
| 100–150k | ⚠️ 強制走委派路徑，主對話只保留高層判斷 |
| > 150k | ⛔ 強制 checkpoint，主動切 session |

**閉環機制：** 超標時完成當前最小單元 → 寫入 state → commit 未存變更 → 告知使用者 → 新 session 自動續接。

---

## 優缺點分析

### ✅ 優點

| 面向 | 優點 | 說明 |
|------|------|------|
| **架構完整性** | 端到端覆蓋 | 從需求到 PR 全流程自動化，6 個 stage 涵蓋 SDLC 核心環節 |
| **成本優化** | Model 動態分級 | 不是所有任務都用 Opus，機械性工作用便宜 model，真正降成本 |
| **品質保障** | 雙層交叉檢查 | 兩道防線都刻意避免「自己審自己」：(1) STAGE 2 驗收委派獨立 verifier agent（最強推論），與寫代碼的委派後端（可能是便宜 model）不同源；(2) STAGE 3 reviewer 用最強推論，與 implementer 不同源。驗收等級刻意 ≥ 實作等級，確保把關強度。quick 模式砍掉所有儀式時也保留這道閘門 |
| **換代維護** | Policy over models | model 綁在 agent frontmatter（別名），effort 則在呼叫時顯式帶入。當 model 換代時，由於使用了別名，frontmatter 免改；調整某角色 effort 等級只需更改派發參數即可。 |
| **韌性** | Token Budget Gate 閉環 | 長流程不會因 context 爆炸而丟失進度，state 持久化是真正的救生圈 |
| **可恢復性** | per-worktree state 檔 | session 中斷後可續接，`interrupted_by` 區分主動離開 vs 系統保護 |
| **多流程並行** | worktree 隔離 + workflow-id | 同 repo 可同時跑多個 workflow，STAGE 1 起各自在專屬 worktree 內達成零鎖並行（工作目錄本身分開，比純切 branch 更徹底）；STAGE 0a/0b pending 階段靠 workflow-id 持久化補上唯一缺口 |
| **並行效率** | 條件式並行 + 三規則契約 | 不盲目並行，有明確的衝突偵測和失敗處理策略 |
| **人在迴路** | 關鍵暫停點 | 規格、計畫、分支、每個任務、審查、PR 都有確認點，不會脫韁 |
| **靈活入口** | Quick Commands + jump mode + quick 模式 | 可以從任意 stage 切入，不強迫跑完整流程；小修正有專屬單暫停點快速通道 |
| **退回機制** | STAGE 3 → STAGE 2 迴圈 | 審查不通過不是死路，有明確的退回路徑 |
| **失敗處理** | 分級 retry + 人工兜底 | 重試有上限（2 次），超過就停下來問人，不無限迴圈 |

### ❌ 缺點

| 面向 | 缺點 | 嚴重度 | 說明 |
|------|------|--------|------|
| **過度工程** | ~~小功能走全流程太重~~ | ✅ 已解決 | quick 模式已補上逃生艙：小修正走「branch → 直改 → reviewer 快掃 → PR」單暫停點通道。殘餘風險：「是否屬於小修正」的判斷仍靠 LLM 自律，quick 被拿來跑大功能時只有「中途升級轉完整流程」這條軟性防線 |
| **暫停點過多** | ~~Human-in-the-loop 頻率太高~~ | ✅ 已解決 | `pause_level` 已於 2026-08-06（`9bce068`）落地，暫停頻率成為可選粒度：`strict`（預設，維持原本 6 個固定暫停點 + STAGE 2 逐任務）／`balanced`（只停 `0b` 計畫確認、`2` 實作整體完成、`4` PR 發布前，STAGE 2 逐任務暫停全關）／`autonomous`（全不停）。判定收斂於 `wf-state.sh:141` `should_pause()` 單一來源，`stage-done`/`task-done` 兩處呼叫；欄位缺失或值異常一律退回 `strict`，壞掉的方向偏向多停一次。詳見 SKILL.md:197-211。**殘餘風險**：`autonomous` 會讓 `gh pr create` 不經過目就執行，故 SKILL.md:211 明列除非使用者要求無人值守，否則優先建議 `balanced` |
| **委派後端依賴** | ~~外部 CLI 是單點故障~~ 傳輸層已換，依賴本身仍在 | 🟡 中（原 🟡 中，性質改變） | 2026-08-10 傳輸層由 `agy -p` headless 改為 MCP（`mcp__gemini-cli__ask-gemini`），**解決的是「委派根本跑不動」**——舊路徑因 stdin/權限問題實際一律落到 fallback，orchestrator 模式形同虛設。**未解決的**：後端仍是單一外部依賴（MCP server 掛掉照樣退 fallback），且新路徑帶來兩個舊路徑沒有的缺口——(1) MCP 無法指定 cwd；**此項已於 `wf-guard-delegate-cwd` 落地後大幅收斂**：pre 端檢查 prompt 含目標 worktree 絕對路徑、缺失即 `exit 2` 阻擋，已從文件層自律升級為程式強制，殘餘的是 post 端只告警不回捲、且偵測範圍限於 git worktree（見「Hook 強制層」）；(2) 無 `--print-timeout` 對應機制，長任務卡住只能人為中斷，這條**仍是純粹的文件層規避**（靠拆小任務） |
| **Model 假設** | 綁定 Anthropic 模型族 | 🟢 低 | 已大幅收斂：版本 ID 全數移除，model/effort 綁在 agent frontmatter（別名），SKILL.md 只寫推論等級名——同代升級與跨代換代都免改。殘餘綁定：`opus`/`sonnet` 別名與 effort 參數仍是 Claude Code 專有，若換到非 Anthropic 生態，需重寫的只剩每個 agent 檔的兩行 frontmatter，等級語意（最強推論/標準/輕量）可原樣搬移 |
| **狀態檔脆弱** | ~~JSON 手動管理無校驗~~ | ✅ 已解決 | `scripts/wf-state.sh` 成為 state 檔唯一存取入口：schema 校驗（含 `schema_version` 欄位）+ 原子寫入（tmp → jq 驗證 → mv），壞資料進不了磁碟、寫入半途中斷不留半套 state；`get` 讀取即校驗，腐壞檔立即失敗而非靜默續接 |
| **並行複雜度** | 契約規則難以程式化驗證 | 🟡 中 | 「寫入路徑不重疊」「共享資源指定唯一 owner」靠 planner 在計畫中標好——但 planner 本身是 LLM，標錯怎麼辦？沒有靜態檢查機制 |
| **Context 估算** | Token 用量無法精確測量 | 🟡 中 | Token Budget Gate 依賴「評估主對話 context 用量」，但 LLM 無法精確知道自己的 context 用了多少 token。60k / 100k / 150k 的閾值在實務上只能靠啟發式猜測 |
| **缺乏回滾** | 沒有 undo/rollback 機制 | 🟡 中 | STAGE 2 如果 implementer 寫了爛 code 且已 commit，STAGE 3 退回 STAGE 2 只是「重做」，不會自動 `git revert`。壞 commit 會留在歷史中 |
| **STAGE 5/6 脫節** | 獨立入口與主流程不連貫 | 🟡 低 | STAGE 5、6 都是「獨立入口」。STAGE 5 串聯 responder → reviewer → publisher，邏輯與主流程部分重疊卻又獨立，若修改引入新 bug 沒有機制退回 STAGE 2；STAGE 6 雖已新增文件同步（gen-sync-docs-by-branchs → gen-commit）避免 docs 過期，但仍脫離主流程，靠使用者手動觸發、不自動偵測 PR 合併狀態，誤觸發（PR 未真正合併就清理）無自動防護，只靠使用者自律 |
| **文件 vs 執行** | Skill 是文件，不是程式 | 🟡 中（原 🔴 高） | 可程式化的 guard 已從文件搬進 `scripts/wf-state.sh`：(1) state machine 實作——sequence 模式非法 stage 轉移直接 exit 1（合法路徑 0a→0b→1→2→3→4、3→2、4→done 寫死在轉移表；quick/jump 不套用轉移表，quick 升級走單向 `upgrade` 指令）；(2) 暫停點棘輪——`stage-done`/`task-done` 後未帶 `--confirmed` 的 `advance` 一律拒絕，跳過暫停點從「無聲遺忘」變成必須蓄意加旗標的可稽核動作；(3) `set` 白名單禁改 `stage`/確認旗標，防繞過。**殘餘風險**：LLM 仍可能根本不呼叫腳本（只能靠 SKILL.md 明文禁止手寫 JSON），context 用量估算依然無法程式化 |
| **Hook 層脆弱** | 掛載點不進版控、matcher 與通道耦合 | 🟡 中 | Hook 是目前唯一不依賴 LLM 自律的防線，但自身有三個缺口：(1) 掛載於 `.claude/settings.local.json`，**本地設定不進版控**——換機器、重裝或新 clone 都不會有，且失效時無聲無息；(2) 兩個 delegate guard 的 matcher 寫死 `mcp__gemini-cli__ask-gemini`、reindex 寫死 `Bash`，**換委派傳輸層或把 GitHub 操作改走 MCP 都會讓對應 hook 靜默失效**（2026-08-10 已換過一次通道，這是真實而非假想的風險）；(3) false positive 防護以「無 state 檔即放行」為條件，等於「不寫 state 反而繞過 guard」——為避免誤擋而接受的代價 |
| **錯誤傳播** | 早期 stage 錯誤會放大 | 🟡 中 | 如果 STAGE 0a 的功能規格就有偏差，使用者確認了（可能沒仔細看），後面所有 stage 都在錯誤基礎上工作。flow 沒有後期發現早期問題的回溯機制 |
| **STAGE 1 斷裂** | ~~`promote` 後 `stage-done 1` 恆遭拒（Bug 1.6）~~ | ✅ 已解決 | 2026-07-30 已透過修改 SKILL.md 工作流指示 (Workaround) 解決。正常 sequence 流程如今會依序執行 `advance 0b` 與 `advance 1`，強行推進 stage 來滿足 guard 的要求，而不去改動 `promote` 共用底層腳本。詳見 [`docs/brainstorm/2026-08-25-workflow-brainstorm.md`](../brainstorm/2026-08-25-workflow-brainstorm.md) §6。 |
| **狀態機漏洞** | ~~缺少任務完成與 STAGE 5 閉環校驗~~ | ✅ 已解決 | 2026-07-21 已在 `wf-state.sh` 補齊 `completed_tasks` 數量是否與 `total_tasks` 吻合的檢查，並於 STAGE 5 轉移表加上 `reviewer -> responder` 退回規則，防堵漏洞。（註：該校驗初版誤在頂層 `case` 分支用 `local`，一觸發即 `set -e` crash，已由「腳本脆弱性」列的 Bug 1.5 修正。） |
| **腳本脆弱性** | ~~`wf-state.sh` 隱含多個 Bash Bug~~ | ✅ 已解決 | 2026-07-21 修復了 5 個 Bash 執行階段漏洞：參數不足導致 `shift 2` crash、無 `=` 的 `set` 參數致 JSON 損毀、負數被錯誤轉為字串、原子寫入失敗時殘留暫存檔，以及 `advance` 任務校驗誤用函式外 `local` 致 `set -e` crash（Bug 1.5，曾堵死 STAGE 2→3 主流程，屬「狀態機漏洞」修復引入的回歸）。 |
| **垃圾回收缺失**| ~~廢棄 Pending 檔無人清理~~ | ✅ 已解決 | 2026-07-21 於 `wf-state.sh` 實作 `prune` 指令，可安全清理遺留超過 7 天的孤兒 `.pending-<wf-id>.json`。 |

## 🐧 Linus 式總結

> 「這個 workflow 設計的核心問題是：它試圖用 markdown 文件模擬一個 state machine，然後『希望』LLM 會遵守所有規則。這就像寫一份『請不要碰野指針』的安全規範給 C 語言實習生，然後期待程式永遠不會 Segment Fault 一樣荒謬。幸好，作為最後防線的 Shell 腳本（`wf-state.sh`）已經被加固，擋下了絕大多數的越權行為。」

**最值得保留的設計：** Token Budget Gate 閉環 + per-worktree state 檔的中斷續接。這是解決 LLM context 爆炸這個**真實問題**的務實方案。多 workflow 並行更是把「並行衝突」這個特殊情況用數據結構直接消滅——STAGE 1 起各流程各佔一個獨立 worktree，工作目錄本身分開，連 state 檔撞名都不可能，而不是加鎖去處理它——好品味。

**已修掉的問題：** (1) 缺少輕量模式——quick 模式已補上（單暫停點、不建 worktree、branch → 直改 → reviewer 快掃 → PR），10 行 fix 不再跑 6 個 stage。(2) 參數配置收斂——model 別名收斂於 frontmatter 綁定，effort 配置則收斂於推論等級表；雖呼叫時需明確指明 effort，但透過統一定義降低了 model 換代的維護稅。(3) **跨工作區盲區與 Quick 升級逃逸**——已在 SKILL.md 規範中強制利用 `git worktree list` 跨區掃描以及升級時強制建置工作區來修補。(4) **腳本底層漏洞**——2026-07-21 已修復 `wf-state.sh` 的 5 個 Bash 執行階段 bug（含暫存檔洩漏、參數檢查缺失，以及完成度校驗誤用函式外 `local` 致 `set -e` crash 的回歸）與 3 個設計縫隙（缺少完成度校驗、STAGE 5 退回路徑、以及 prune GC），徹底鞏固防線。(5) **STAGE 1 規劃文件搬移**——2026-07-29 新增步驟將 STAGE 0a/0b 產出的未 commit spec/plan 檔複製進新 worktree，避免 state 檔的路徑懸空。

**已採用之修復與背景（Bug 1.6 STAGE 1 斷裂）：** 此問題（`promote` 不推進 `stage` 導致 sequence 模式下 `stage-done 1` 遭拒）曾被視為高優先級待修項目。基於「Never break userspace」的實用主義哲學，最終選擇**修改 SKILL.md（Workaround）**，要求 AI 在 promote 後主動跑 `advance 0b --confirmed` → `advance 1 --confirmed` 來推動轉移表，而非去改動服務於多條路徑的 `promote` 底層腳本。這保證了 100% 安全且零回歸風險。曾被列為殘餘缺陷的暫停點密度（正常路徑 6 個固定暫停點、STAGE 2 逐任務線性膨脹）已由 `pause_level` 解決——2026-08-06（`9bce068`）落地，使用者可於 `init` 時或流程中途選擇 `strict`／`balanced`／`autonomous` 三級確認粒度。

**最危險的假設（更新後）：** 原本是「markdown 指令 = 程式碼保證」；guard 進了 `wf-state.sh` 且腳本 bug 也修復之後，假設縮小為「LLM 會記得呼叫腳本」。

而 hook 層（見「Hook 強制層」）補上了**第二道不依賴自律的防線**——這是關鍵差異：`wf-state.sh` 要 LLM 主動呼叫才有用，hook 則由 harness 在工具呼叫前後強制執行，**LLM 不能選擇不觸發**。`wf-guard-stage-check` 擋掉「沒推進到 STAGE 5 就派 responder」，`wf-guard-delegate-cwd` 擋掉「派發 prompt 沒寫工作目錄」，兩者都不需要 LLM 配合。

**殘餘的自律面：** (1) 不呼叫 `wf-state.sh` 就沒有 state 檔，而兩個 guard hook 都以「找不到 state 檔即放行」為 false positive 防護——**不寫 state 反而繞過了 guard**，這是設計上為避免誤擋而接受的代價；(2) hook 掛在不進版控的 `settings.local.json`，換機器即失效；(3) hook matcher 寫死委派通道名稱，換傳輸層會靜默失效；(4) context 用量估算依然無程式解。
