# gen-dev-workflow 流程優化、多 Agent 框架比對與架構演進總整文件

> **📝 合併紀錄**：
> 本文件整併了 `2026-07-17` 與 `2026-07-30` 的腦力激盪記錄。依據時間軸與完成度，前半部記錄歷史遺留 Bug、流程漏洞的分析與修復；後半部基於系統穩固的基礎，進行開源多 Agent 框架的深度比對，並提出 2.0 架構的具體優化提案。
>
> **2026-08-15 新增第三部分**：**知名開發者的實務工作流比對**（Huntley 的 Ralph、
> HumanLayer 的 ACE-FCA、Harper Reed 三件式、Hashimoto 的 16-session、Kent Beck 的
> Augmented Coding、Böckeler 的 Harness Engineering、Vincent 的 Superpowers，
> 以及 Steinberger 的**反方立場**）。與第二部分的差別：那邊比的是學術框架，這邊比的是
> **具名工程師跑在真實專案上的手工流程**。結論分成「已經有的／真正可學的／刻意不學的」三類，
> 高價值新洞察只有一項：**context 主動維持 40-60%，而非撞到 150k 才剎車**。
>
> **2026-08-16 三輪查證完成**：第一輪 8 項（§2）、第二輪 13 項（§3.5）、第三輪 19 項（§3.6），
> **32 項候選全數查證完畢、零淘汰**。合計 **11 項判定 REVISES（修正既有結論）**，
> 最重要的三條：機制 6 的理由歸因錯誤（應為同分佈熟悉度而非能力不足）、
> Gap 2.6 的 hook 用了無效的 `exit 1`（偵測得到卻攔不住）、
> 稽核對象應是系統側錄的軌跡而非 agent 自述。
>
> **2026-08-16 補記**：(B) 真正可學的 4 項已補上逐項的「現況 → 差距 → 判斷」推導與
> **建議動工順序**（審查槓桿階層 → context 主動巡航 → Guide→Sensor → anti-slop，
> 見 §3(B) 末表）。同時修正 §2.1 Ralph 的標籤（原標「可學」與 §3(C)「刻意不學」自相矛盾，
> 已改為「佐證」並補完整推導）。**四項截至此日全部仍是提案，未動程式碼。**
>
> **🔴 2026-08-10 重大變更：委派傳輸層由 `agy -p` headless 改為 `gemini-mcp-tool`（MCP）。**
> 底層後端不變（`gemini-mcp-tool` 內部就是 antigravity-cli），換掉的是**傳輸層**。
> 這直接推翻了本文件兩處的既有結論——**§2.3 痛點三**（agy 強耦合與退出碼遮蔽）與
> **§3 提案 4 `wf-exec.sh`**（原被定性為「為一條已不走的路徑寫轉接層」）。
> 委派不是死路，是傳輸層壞掉；換掉之後 orchestrator 模式才第一次真正成立。
> 詳見各節的 2026-08-10 校正註記。
>
> **2026-08-06 補記**：SKILL.md STAGE 6（清理 Worktree）新增「文件同步」前置步驟——執行清理前先呼叫 gen-sync-docs-by-branchs（以當前分支為目標同步文件）→ gen-commit（將同步結果 commit），確保 worktree 移除前 docs 已反映分支最終狀態。此為已落地的流程變更。
>
> **⚠️ 2026-08-06 狀態校正（重要）**：本文件 §5 的 5 項 teamwork-preview 借鏡提案，
> **實查確認全數已落地**（多數走 Claude `Workflow` 工具，而非提案設想的實作形式），
> 文件此前仍將其列為「待實施藍圖」。實際剩餘待辦僅 §3 的 4 支基礎腳本，
> 其中提案 4（`wf-exec.sh`）的前提存疑。**逐項實查證據見文末「📊 落地現況」表**，
> 各節內文亦已加上校正註記。閱讀本文件時請以該表為狀態依據，勿直接採信各節原標。

---

## ✅ 已修正項目（已確認的程式碼缺陷）

> 本區塊只收「**已實查確認、命中真實程式碼**」的缺陷，與各節的「提案／可學項目」分開。
> 提案類請見 §3 的 (B) 真正可學與其動工順序表；本區塊是**曾經壞掉的東西**。
> 目前列管 1 項，已全數修復——BUG-1 於 2026-08-17 修正並實測驗證。

### BUG-1 · Gap 2.6 的 hook 用了無效的 exit code（發現於 2026-08-16）

| 欄位 | 內容 |
|:---|:---|
| **狀態** | ✅ **已修**（2026-08-17，兩處均改為 `sys.exit(2)` 並實測驗證） |
| **檔案** | `.claude/hooks/wf-guard-stage-check.sh` 第 **111**、**126** 行 |
| **所在分支** | `main`（檔案就在當前分支，可直接讀原始碼核對） |
| **原現況** | 兩處阻擋路徑均為 `sys.exit(1)` |
| **修法** | 改為 `sys.exit(2)`（兩處），並各補一行註解說明 `PreToolUse` 的 exit code 語意 |
| **effort** | 極低 |
| **嚴重度** | 🔴 高——這是**目前唯一命中真實程式碼**的缺陷 |

**問題描述**：

這支 hook 是 **Gap 2.6 的解法**，掛在 `PreToolUse`，用途是偵測「stage 還停在 `4` 就想派發 responder」並擋下該次派發。

但依 Claude Code 官方 hooks 文件，`PreToolUse` **只有 `exit 2` 具阻擋力**；其餘退出碼屬 non-blocking error——會在 transcript 印一行錯誤，然後**動作照跑**。

所以這支 hook 的實際行為是：

| 環節 | 狀態 |
|:---|:---:|
| 被呼叫 | ✅ |
| 偵測到違規 | ✅ |
| 印出錯誤訊息與修復指令 | ✅ |
| **實際擋下派發** | ❌ **沒有** |

**它偵測得到，但攔不住。** 文件此前把 Gap 2.6 標為「已修」，實際上該防護當時是**破的**（已於 2026-08-17 修正）。

**驗收方式**：修改後需驗證 stderr 訊息仍會回饋給模型（exit 2 的 stderr 是回饋管道，不能因改動而遺失）。

> **✅ 2026-08-17 實測結果**（四情境，於 `main` 實跑該 hook）：
>
> | 情境 | 期望 | 實測 |
> |:---|:---:|:---:|
> | `stage:"4"` 派發 responder | 阻擋 | ✅ `exit 2` + stderr 完整輸出修復指令 |
> | `stage:"5"` 派發 responder | 放行 | ✅ `exit 0` |
> | state 檔損毀（非合法 JSON） | 阻擋 | ✅ `exit 2` + stderr 錯誤訊息 |
> | 派發非 responder（如 reviewer） | 放行 | ✅ `exit 0` |
>
> stderr 回饋管道確認未因改動遺失，防誤殺保護（無 state 檔／非 responder）亦維持原行為。
>
> 📌 **測試時踩到的坑，記錄供後人**：此 hook 以 `os.getcwd()` 與 **當前 git branch 名**
> 定位 state 檔（檔名須為 `<branch-slug>.json`），**不讀 payload 裡的 `cwd` 欄位**。
> 首次測試用 temp dir + 任意檔名，四個情境全部 `exit 0`，一度誤判「改了也沒用」——
> 實際是測試無效而非修復無效。要測這支 hook，state 檔必須放在
> **當前工作目錄可上溯到的 `.claude/workflow-state/`**、且檔名對上當前 branch。

**為什麼這件事重要（不只是一個 typo）**：

這正是本文件反覆論證的 **Guide vs Sensor**（§2.6 Böckeler）**應驗在自己身上**——

- **Sensor**：動手後的確定性攔截，無法繞過
- **Guide**：引導，可以被忽略

我們**以為**寫了 hook 就取得了 Sensor，但用錯 exit code，它就退化成「**只會印錯誤訊息的 Guide**」。**形式對了，效力沒有。**

而且這條是 §3.5 R3 先從官方文件**推導出**「exit 1 掛成 hook 會失效」，第三輪實查原始碼時**真的在自己的 code 裡撞到**——推論與實證對上了。

> 📌 **延伸檢查建議**：既然 exit code 的語意被誤解過一次，動工時應一併確認
> `wf-state.sh` 的非法轉移 `exit 1` 是否也在某處被當作 hook 掛載。
> 若它只被當一般 CLI 呼叫、由 skill prompt 自行判讀退出碼，那是**機率性**的
> （模型可以無視 exit code 繼續走）——詳見 §3.5 R3。

---

## 🟢 第一部分：歷史基準修復與流程漏洞填補 (2026-07-17 ~ 2026-07-30)

## 0. 完成度總覽（Bug 1.x / Gap 2.1–2.5 核對於 2026-07-21 · Gap 2.6 增補於 2026-08-07）

> 狀態依 [`docs/architecture/2026-08-12-gen-dev-workflow-analysis.md`](../architecture/2026-08-12-gen-dev-workflow-analysis.md) 核對標注。✅ 已修 ｜ 🟡 部分 ｜ ⬜ 待修。（原引用 `docs/features/2026-07-18-...`，該檔已隨文件搬遷／改名不存在。）
>
> **🔍 實查校正 (2026-08-06)**：本註記原寫「`wf-state.sh` 不在本 repo，無法直接讀原始碼，
> 故以該份 analysis 為權威來源」——**此前提已不成立**。該腳本就在本 repo 的
> `.claude/skills/gen-dev-workflow/scripts/wf-state.sh`，**可也應直接讀原始碼核對**，
> 不需再以二手 analysis 文件為權威來源。後續核對本表請以腳本本身為準。

| 項目 | 狀態 | 依據 |
|------|:---:|------|
| **Bug 1.1** `shift 2` crash under `set -e` | ✅ 已修 | 於 2026-07-21 修復，增加參數個數檢查 |
| **Bug 1.2** `set` 無 `=` 致 JSON 損毀 | ✅ 已修 | 於 2026-07-21 修復，拒絕非法格式 |
| **Bug 1.3** `jq_val` 負數被錯轉字串 | ✅ 已修 | 於 2026-07-21 修復，正則精確比對數值 |
| **Bug 1.4** 原子寫入失敗殘留暫存檔 | ✅ 已修 | 於 2026-07-21 修復，加上 fallback 清理機制 |
| **Bug 1.5** `advance` 校驗用 `local` 於函式外致 crash | ✅ 已修 | 於 2026-07-21 修復，移除多餘 `local` 宣告（Gap 2.3 修復引入的回歸） |
| **Gap 2.1** Cross-Worktree State Blindness | ✅ 已修 | analysis 總結：SKILL.md 已強制 `git worktree list` 跨區掃描 |
| **Gap 2.2** Quick→Sequence 升級隔離逃逸 | ✅ 已修 | analysis 總結：`upgrade` 後強制建 worktree + promote 狀態 |
| **Gap 2.3** 缺任務完成校驗（`completed_tasks`） | ✅ 已修 | 於 2026-07-21 修復，`advance` 增加任務數量校驗 |
| **Gap 2.4** STAGE 5 缺 `reviewer→responder` 退回 | ✅ 已修 | 於 2026-07-21 修復，新增閉環轉移路徑 |
| **Gap 2.5** 廢棄 `.pending-*.json` 無 `prune` GC | ✅ 已修 | 於 2026-07-21 修復，新增 `prune` 指令 |
| **Gap 2.6** 獨立入口（STAGE 5/6）完全繞過狀態機 | ✅ 已修（2026-08-14 落地 + 2026-08-17 修正 hook exit code） | 於 2026-08-14 以方案 A + C 修復：`SKILL.md:146` 首步硬性化、`.claude/hooks/wf-guard-stage-check.sh` 於 `PreToolUse` 攔截 responder 派發、`wf-state.sh:98` 補齊 `4->5` 等轉移路徑（見 §4 Gap 2.6） |

> **已落地的地基**（analysis 確認，非本 brainstorm 提出的待辦）：`wf-state.sh` 已成 state 檔唯一入口——狀態機轉移表（非法轉移 `exit 1`）、暫停點棘輪（無 `--confirmed` 拒絕 `advance`）、`set` 白名單、schema 校驗 + 原子寫入皆已實作。
>
> **結論**：5 個 Bash Bug 及 Gap 2.1–2.5 均已修復（包含 SKILL.md 層面的 2 項與 `wf-state.sh` 腳本層面的 8 項），腳本脆弱性與狀態機**內部**漏洞已解決。其中 Bug 1.5 是 Gap 2.3 修復方案照抄片段時把 `local` 帶進頂層 `case` 分支所造成的回歸，於本次一併抓出並修正。
>
> **⚠️ 2026-08-07 補記（問題已於 2026-08-14 修復，本段保留為設計啟示）**：上述「已徹底解決」的結論**僅在腳本被呼叫的前提下成立**。Gap 2.6 揭露了守衛架構的結構性盲點——獨立入口（STAGE 5/6）可全程不碰 `wf-state.sh`，使所有內部校驗無從觸發。這不是既有修復的回歸，而是先前分析未涵蓋的層級：**對策必須落在入口攔截（hook），繼續往腳本內部堆校驗無效**。
>
> **📌 2026-08-14 結案**：該判斷成立，已依此落地 hook 攔截層（`.claude/hooks/wf-guard-stage-check.sh`），Gap 2.6 已修復。**但此結論的適用範圍不限於 Gap 2.6**——「守衛需要被呼叫才生效」是結構性盲點，同型弱點仍存在於**委派的工作目錄約束**（MCP 無法指定 cwd，只能靠 prompt 寫絕對路徑），詳見 [`docs/architecture/2026-08-21-wf-state-harness-guardrail.md`](../architecture/2026-08-21-wf-state-harness-guardrail.md) §「同構的第二個弱點」。
>
> **📌 2026-08-21 追加結案（issue #134 / PR #135 已合併）**：該同型弱點亦已落地 hook 層對策 `.claude/hooks/wf-guard-delegate-cwd.sh`——`pre` 端（PreToolUse）檢查派發 prompt 是否含目標 worktree 絕對路徑，缺失即 `exit 2` 阻擋；`post` 端（PostToolUse）以 `git status` before/after 差集偵測越界寫入與越界 commit，**只告警不阻斷**並寫入稽核紀錄。與 Gap 2.6 的差別在於：Gap 2.6 可事前阻斷，本項因 MCP 介面無 cwd 參數而**預防在物理上不可得**，確定性偵測即為天花板。

---

## 1. 總結與設計哲學批評 (Linus-Style Critique)

> 「這個工作流設計的核心品味漏洞在於：它試圖用一堆 Markdown 文字去『說服』LLM 遵守狀態轉移。這就跟寫一份『請不要碰野指針』的安全規範給 C 語言實習生，然後指望程式永遠不會 Segment Fault 一樣荒謬。更糟的是，用來作為防護欄的 Shell 腳本（`wf-state.sh`）本身寫得漏洞百出，在 `set -e` 的環境下一碰就碎。」

### 🟢 展現好品味的設計 (Good Taste)
* **Token Budget Gate 的閉環設計**：這解決了長流程下 LLM 的 Context 容易爆炸的**真實問題**。在 >150k 時強制寫入 checkpoints、WIP commit 並交接給新 session 的作法，是極其實用且具彈性的。
* **基於 Worktree 的多流程並行隔離**：透過 `git worktree` 將不同分支的開發徹底隔離在獨立的工作區中。這從**資料結構**與**目錄實體**上直接消滅了並行衝突的可能，而不是試圖用複雜的鎖（Lock）去修補它。這正是簡化資料結構以消除特殊情況的典範。

### 🔴 湊合與糟糕的設計 (Bad Taste)
* **過度工程的「人肉暫停點」**：完整流程中包含了至少 6 個固定暫停點，在 STAGE 2 中甚至每完成一個任務就要暫停一次。這把原本應該自動化運行的編排器，變成了需要人類不斷點擊確認的「高頻打擾器」。
* **防禦性程式碼的缺失**：`wf-state.sh` 雖被立為唯一狀態入口，但其參數解析脆弱，未對變數型別與參數個數進行防禦性檢查。

---

## 2. 當前瓶頸與限制分析

### 2.1. 人在迴口（Human-in-the-loop）頻率過高
* **現象**：STAGE 2 實作階段會根據任務清單逐一分派並暫停。當任務量多（例如 5-10 個小任務）時，頻繁的暫停展示變更與確認，嚴重打斷了開發的流暢性。
* **瓶頸**：LLM 雖然能自動寫代碼，但頻繁的人工確認要求使用者的注意力維持在低效的等待狀態。

### 2.2. 跨工作區狀態盲區 (Cross-Worktree State Blindspot)
* **現象**：自 STAGE 1 起，狀態 JSON 會被 promote 並搬移到各 Worktree 的 `.claude/workflow-state/` 中，而 Root 倉庫對應的 JSON 會被刪除。
* **瓶頸**：當使用者在 Root 倉庫重新啟動 Claude session 並嘗試呼叫 `continue` 時，根目錄的 Agent 由於對 Worktree 目錄毫無感知，會判定「找不到任何活動中的工作流」。

### 2.3. 外部 `agy` CLI 強相依 — 🔄 已改善（2026-08-10 換傳輸層）
* **現象**：流程的核心委派動作（如 brancher、implementer、publisher）完全依賴外部 `agy` 命令。
* **限制**：若 `agy` 未正確配置在 PATH，退回 Fallback 模式後的行為描述含糊。且由於 Fallback 模式無法有效委派，整條流程的優勢將不復存在。

> **🔍 2026-08-10 校正**：本節的問題比原本描述的**更嚴重**——實際上 `agy` 就算在 PATH 裡
> （實查 `/Users/yomiry/.local/bin/agy`，v1.1.11），**`agy -p` headless 路徑仍不可用**：
> 不吃 stdin、權限會卡死。也就是說委派**一直**落在 fallback，「流程優勢不復存在」不是假設情境，
> 是常態。
>
> **已採取的對策**：傳輸層改走 MCP 工具 `mcp__gemini-cli__ask-gemini`（後端仍是 antigravity-cli）。
> 實測驗證通過：可寫新檔、可改既有檔、可跑 shell、可 `git commit`（commit hash 與磁碟狀態
> 均經第三方驗證，非採信子進程回報）。
>
> **殘餘限制**（換傳輸層解決不了的）：
> 1. **仍是單一外部依賴**——MCP server 掛掉照樣退 fallback，只是失效點從 CLI 移到 MCP。
> 2. **無法指定 cwd**——工作目錄只能靠 prompt 寫絕對路徑約束，屬文件層自律，非程式強制。
>    這與 Gap 2.6 是同一類結構性弱點：**約束寫在 prompt 裡 = 沒有強制力**。
> 3. **無 `--print-timeout` 對應物**——長任務無逾時控制，卡住只能人為中斷。
> 4. **退出碼遮蔽問題換了形式但沒消失**——MCP 回傳的是文字，沒有 exit code 概念；
>    子進程宣稱「測試通過」同樣不可採信，仍須主對話親自跑測試驗證。

---

## 3. `wf-state.sh` 中的 Bash Bug 細節與具體修復方案

以下是目前 `wf-state.sh` 腳本中存在的四個 Bash Bug 及其具體修復方案：

### Bug 1.1: `shift 2` Crash under `set -e` — ✅ 已修
* **問題根源**：由於腳本設定了 `set -euo pipefail`，當執行 `advance`、`init`、`promote` 等指令時，如果使用者漏傳了選填或必填參數（例如少傳了 `<next>`，僅執行 `wf-state.sh advance config.json`），`$#` 數量小於 2，此時執行 `shift 2` 會返回退出狀態碼 `1`。這會觸發 `set -e` 導致腳本直接異常退出（Crash），而無法輸出優雅的 Usage 說明。
* **受影響程式碼片段 (`wf-state.sh` Line 221)**：
  ```bash
  f="$(resolve "$1")"; next="$2"; shift 2
  ```
* **具體修復方案**：
  ```bash
  f="$(resolve "$1")"
  if [ $# -ge 2 ]; then
    next="$2"
    shift 2
  else
    die "advance 指令需要提供目標階段 (next)，用法：wf-state.sh advance <檔> <next> [--confirmed]"
  fi
  ```
  *(同理，針對 `init`、`promote` 與 `upgrade` 中所有包含 `shift 2` 的參數解析迴圈，皆須在 `shift 2` 前檢查剩餘參數個數)*

### Bug 1.2: Silent Key-Value Corruptions in `set` Command — ✅ 已修
* **問題根源**：在 `set` 命令中，腳本將 args 拆分為 `k` 與 `v`。然而，如果傳入的參數不含 `=`（例如 `wf-state.sh set config.json interrupted_by`），`k="${kv%%=*}"` 與 `v="${kv#*=}"` 會同時解析為鍵名 `"interrupted_by"`。這會導致腳本靜默寫入 `"interrupted_by": "interrupted_by"` 至 JSON 中，造成資料損毀。
* **受影響程式碼片段 (`wf-state.sh` Line 94-95)**：
  ```bash
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
  ```
* **具體修復方案**：
  ```bash
  for kv in "$@"; do
    if [[ "$kv" != *=* ]]; then
      die "參數格式錯誤：'$kv'。必須為 k=v 格式"
    fi
    k="${kv%%=*}"; v="${kv#*=}"
  ```

### Bug 1.3: `jq_val` String Coercion for Negative Numbers — ✅ 已修
* **問題根源**：在型別判定函式 `jq_val()` 中，判定模式 `''|*[!0-9]*|0*` 用於攔截並強製轉化為 JSON 字串。然而，負數（如 `-42`）因為包含負號 `-`，會匹配到 `*[!0-9]*`。這會使負數被錯誤地強製轉換為 JSON 字串 `"-42"` 而非 raw 數值。
* **受影響程式碼片段 (`wf-state.sh` Line 73-80)**：
  ```bash
  jq_val() {
    case "$1" in
      null|true|false) echo "$1" ;;
      0) echo "0" ;;
      ''|*[!0-9]*|0*) jq -n --arg v "$1" '$v' ;;
      *) echo "$1" ;;
    esac
  }
  ```
* **具體修復方案**：
  使用 Bash Regex 進行精準判斷，只將非合法數值、布林與 null 的內容轉化為字串：
  ```bash
  jq_val() {
    if [[ "$1" =~ ^-?[1-9][0-9]*$ || "$1" == "0" || "$1" == "-0" ]]; then
      echo "$1"
    elif [[ "$1" == "true" || "$1" == "false" || "$1" == "null" ]]; then
      echo "$1"
    else
      jq -n --arg v "$1" '$v'
    fi
  }
  ```

### Bug 1.4: Leftover Temp Files on Rename Failure — ✅ 已修
* **問題根源**：在 `atomic_write()` 中，雖然有在 subshell 中做 validate 校驗，但如果最後的 `mv "$tmp" "$f"` 搬移操作失敗（例如磁碟空間滿了、或者目標目錄的權限被更改為唯讀），因為 `set -e`，腳本會立即中斷退出，但已經建立的暫存檔 `.wf-tmp.XXXXXX` 將會永遠遺留在目錄中。
* **受影響程式碼片段 (`wf-state.sh` Line 62-69)**：
  ```bash
  atomic_write() {
    local f="$1" tmp
    mkdir -p "$(dirname "$f")"
    tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
    jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
    ( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }
    mv "$tmp" "$f"
  }
  ```
* **具體修復方案**：
  ```bash
  atomic_write() {
    local f="$1" tmp
    mkdir -p "$(dirname "$f")"
    tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
    jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
    ( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }
    mv "$tmp" "$f" || { rm -f "$tmp"; die "搬移暫存檔失敗，清理暫存檔 $tmp"; }
  }
  ```

---

## 4. 邏輯缺陷與流程漏洞分析 (Logical & Process Gaps)

### Gap 2.1: Cross-Worktree State Blindness (CRITICAL) — ✅ 已修
* **漏洞描述**：當 Sequence 流程推進到 STAGE 1 時，狀態 JSON 被移入工作區，Root 對話便失去了對該狀態的感知。一旦重開 session，用戶在 Root 執行 `continue` 將無法接續進度。
* **解決方案**：
  修改 `SKILL.md` 中續接（continue）狀態定位邏輯。當前目錄找不到狀態時，強制調用 `git worktree list` 遍歷所有活動工作區路徑，並掃描這些工作區的 `.claude/workflow-state/*.json`。

### Gap 2.2: Quick-to-Sequence Upgrade Isolation Escape (CRITICAL) — ✅ 已修
* **漏洞描述**：Quick 模式運行於 Root 倉庫。當呼叫 `upgrade` 提升為 Sequence 流程時，腳本僅僅修改了狀態 JSON，卻沒有在實體層面建立 Git worktree，這導致升級後的 Sequence 流程直接在 Root 倉庫中運行，打破了工作區物理隔離的鐵律。
* **解決方案**：
  在 `SKILL.md` 的 `upgrade` 流程中，強制與建立 worktree 的指令綁定。在 `wf-state.sh upgrade` 執行成功後，必須立即為該分支建立 worktree，複製 Root 中未 commit 的變更至新工作區，並將狀態 JSON promote 到該工作區下，最後指引 Claude `cd` 進入該工作區。

### Gap 2.3: Missing Task Completion Verification — ✅ 已修
* **漏洞描述**：狀態機允許任意從 STAGE 2 推進（advance）至 STAGE 3，而沒有在程式碼層面檢查 `completed_tasks` 陣列是否完整包含 `1` 到 `total_tasks` 的所有任務編號。這使得 LLM 可能因為自律失效，跳過未實作的任務直接申請審查。
* **解決方案**：
  在 `wf-state.sh` 的 `advance` 指令解析中，當目標為 `3` 且模式為 `sequence` 時，增加校驗邏輯：
  ```bash
  if [ "$next" = "3" ] && [ "$mode" = "sequence" ]; then
    local total completed_count
    total="$(jq -r '.total_tasks' "$f")"
    completed_count="$(jq -r '.completed_tasks | length' "$f")"
    if [ "$total" != "null" ] && [ "$completed_count" -lt "$total" ]; then
      die "實作尚未全部完成（已完成 $completed_count / 共 $total 任務），拒絕推進至 STAGE 3"
    fi
  fi
  ```

### Gap 2.4: PR Review responder has no retry loop — ✅ 已修
* **漏洞描述**：在 STAGE 5 中，轉移路徑為 `responder -> reviewer -> publisher`。若 `reviewer` 審查不通過，狀態機沒有回到 `responder` 重新修改的閉環，容易導致流程卡死。
* **解決方案**：
  在 `legal_transition()` 中新增 `reviewer->responder` 的轉移規則：
  ```bash
  legal_transition() {
    case "$1->$2" in
      "0a->0b"|"0b->1"|"1->2"|"2->3"|"3->4"|"3->2"|"4->done"|"reviewer->responder"|"responder->reviewer"|"reviewer->publisher") return 0 ;;
      *) return 1 ;;
    esac
  }
  ```

### Gap 2.5: Orphaned Pending Files — ✅ 已修
* **漏洞描述**：若 Sequence 流程在 STAGE 0a/0b 階段（尚未 promote）被使用者廢棄，根倉庫的 `.pending-<wf-id>.json` 檔案將永遠殘留，缺乏垃圾回收機制。
* **解決方案**：
  在 `wf-state.sh` 中新增 `prune` 命令，允許使用者或系統定期清理建立時間大於 7 天的 `.pending-*.json` 檔案。

### Gap 2.6: 獨立入口（STAGE 5/6）完全繞過狀態機 — ✅ 已修（2026-08-14 方案 A + C 落地；hook exit code 缺陷已於 2026-08-17 修正，見 BUG-1）

* **漏洞描述**：既有守衛（棘輪、轉移表、任務數校驗）**只在 `wf-state.sh` 被呼叫時才生效**。STAGE 5/6 是不在 `0a→0b→1→2→3→4` 主鏈上的獨立入口，缺少前後階段的銜接慣性，LLM 容易在「處理 review 意見」的任務心智下直接派發 responder/reviewer，**全程不碰腳本**——此時沒有任何機制會察覺流程正在推進。

  這與 Gap 2.3 的失效模式**本質不同**，不可混為一談：
  * Gap 2.3 是「呼叫了 `advance` 但校驗不足」→ 補校驗即可堵住。
  * Gap 2.6 是「**根本沒呼叫腳本**」→ 再多校驗也不會被執行到。棘輪防的是「確認前推進」，防不了「繞過腳本推進」。

* **實例（2026-08-07）**：PR #121 / #123 的 STAGE 5 全程跑完（responder 處理 6 則 inline comments → reviewer 複審 → 額外補修同源問題），四個 commit 已推上遠端，但兩個 worktree 的 state 檔**始終停在 `stage: "4"`、`awaiting_confirmation: true`**，看起來像 STAGE 5 從未發生。同一 session 稍早的 STAGE 2→3 反而被腳本正確擋下（`實作尚未全部完成（已完成 0 / 共 6 任務）`）——差別只在於那次有呼叫 `advance`。

  **連帶損害**：STAGE 5 流程的第三步（publisher 更新 PR 描述）一併被遺漏，因為沒有 state 推進來提示還有後續步驟。若此時換 session 續接，新 session 會誤判 STAGE 5 尚未執行而重跑。

* **方案評估**（建議 A + C 併行，跳過 B）：

  **A. 文件層——獨立入口的首步硬性化**
  在 SKILL.md 的 STAGE 5/6 區塊開頭，把 state 推進寫成不可跳過的第一步而非隱含前提：
  ```
  STAGE 5：回覆 PR Review（獨立入口）
  🔴 第一步（不可跳過）：wf-state.sh advance <檔> 5 --confirmed
     ↑ 未執行此步就派發 responder = 流程違規
  → 呼叫 responder agent...
  ```
  成本最低，但**仍只是叮嚀**——本次違規時 SKILL.md 已寫明正確流程（含 `{ stage: 5, mode: "jump" }` 的寫入指示）卻仍被漏掉，證明純文件層不足以獨立成為對策。

  **B. 腳本層——`assert-stage` 子命令**：❌ **不採用**。
  新增 `wf-state.sh assert-stage <檔> 5`（stage 不符則 exit 1）雖比 A 強，但**與 A 共享同一個失效前提**（都要求 LLM 主動呼叫腳本）。多一個子命令卻換不到實質保障，不划算。

  **C. Hook 層——唯一真正的強制**
  以 `PreToolUse` hook 攔截 `Agent` 工具呼叫：偵測到派發 `responder`/`reviewer`/`publisher` 時，檢查當前 worktree 的 state 檔 stage 是否已推進至對應階段，未推進則**阻擋該次呼叫**並回傳提示。
  * **為何有效**：執行者是 harness 而非 LLM，這是唯一「想繞也繞不過」的層級。
  * **代價**：hook 邏輯需維護；且會誤擋「流程外單獨派發 reviewer 做零星審查」的正當用法——需評估是否加白名單，或退而採「警告但不阻擋」。此取捨需由使用者依實際使用習慣決定。

* **落地解決方案（2026-08-14 · 方案 A + C 併行）**：
  1. **方案 A（文件層硬性化）**：`SKILL.md` 的 STAGE 5/6 區塊開頭加粗標示 `🔴 第一步（不可跳過）：推進狀態至 STAGE 5/6`，並明確規範未推進即派發 responder 屬流程違規。
  2. **方案 C（Hook 層強制攔截）**：新增 `.claude/hooks/wf-guard-stage-check.sh`，在 `PreToolUse` 攔截 `Agent`（Claude）與 `invoke_subagent`（Antigravity）呼叫：
     - 若派發 `responder` 且當前 worktree 存在 active workflow state，檢查 `stage` 是否為 `5`；
     - 若未推進（如停在 `4`），Hook 以 exit code 阻擋派發，並在 stderr 輸出精確的修復指令（`wf-state.sh advance <state_file> 5 --confirmed`）；
     - **防誤殺保護**：若目錄下無 workflow 狀態檔（流程外單獨調用），Hook 直接 exit 0 放行。
  3. **轉移表補全**：`wf-state.sh:legal_transition()` 補上 `4->5`、`5->4`、`5->5`、`4->6`、`5->6`、`6->done` 等轉移路徑，確保 sequence 流程回覆 PR 時推進無阻。

* 🔴 **2026-08-16 實查更正（上述方案 C 的落地實作未達成設計意圖）**：
  `.claude/hooks/wf-guard-stage-check.sh:111,126` 用 `sys.exit(1)`，而官方 hooks 文件明載
  `PreToolUse` **只有 `exit 2` 具阻擋力**，exit 1 屬 non-blocking error、**動作照跑**。
  當時是「偵測得到違規但攔不住」——**Gap 2.6 的防護實際上是破的**。修法：改為 `sys.exit(2)`，**已於 2026-08-17 落地並實測驗證**。
  **已登記為文件開頭的 BUG-1**（✅ 2026-08-17 已修），完整推導見 §3.5 R7。

* **設計啟示**：本 Gap 揭露的是守衛架構的**結構性盲點**，而非單點疏失——「守衛需要被呼叫才生效」。任何未來新增的獨立入口（非主鏈階段）都會重現同一漏洞，因此對策應落在**入口攔截層**，而非繼續往 `wf-state.sh` 內部堆校驗。

---

## 5. 驗證方法 (Verification Methods)

### 5.1. 針對 Bash Bug 的單元測試方法
1. **驗證 Bug 1.1 修復**：
   執行 `./wf-state.sh advance config.json` (故意缺少 target stage)，預期腳本輸出正確的 usage 錯誤訊息，且退出碼為 1，不應 crash 退出。
2. **驗證 Bug 1.2 修復**：
   執行 `./wf-state.sh set config.json interrupted_by`，預期腳本拒絕修改並印出 "參數格式錯誤：'interrupted_by'。必須為 k=v 格式"。
3. **驗證 Bug 1.3 修復**：
   執行 `./wf-state.sh set config.json total_tasks=-5`，隨後執行 `wf-state.sh get config.json`，確認 `total_tasks` 在 JSON 中的值為 raw 數值 `-5`，而不是帶雙引號的 `"-5"`。
4. **驗證 Bug 1.4 修復**：
   建立一個唯讀權限的資料夾，將狀態 JSON 放入其中。執行 `./wf-state.sh set` 寫入該 JSON。由於搬移必會失敗，檢查該唯讀目錄下是否殘留有 `.wf-tmp.XXXXXX` 暫存檔，預期無任何殘留。

### 5.2. 針對流程漏洞的整合驗證
1. **驗證 Cross-Worktree 續接**：
   在新 session 的 Root 倉庫中呼叫 `continue`，確認腳本會輸出當前所有 worktree 中的 active workflows 列表。
2. **驗證 Quick 升級隔離性**：
   啟動一個 quick 流程，並執行 `upgrade`。驗證系統是否確實自動建立了對應的 git worktree，並且狀態 JSON 成功被 promote 至該 worktree 目錄下。


---

## 6. 後續發現的待修項目（2026-07-21 之後）

### Bug 1.6: `promote` 後 `stage-done <1>` 恆遭拒，STAGE 1 happy path 斷裂 — ✅ 已修

* **撞到的情境**：2026-07-25 用本流程實作 §P13（PR #100）時，STAGE 1 建好 worktree 後，照 SKILL.md 的指示跑 `promote` → 隨後 `stage-done <檔> 1`，被腳本直接拒絕：
  ```text
  wf-state: sequence 模式 stage-done 參數須等於目前 stage（目前：0a），改 stage 請用 advance
  ```
* **根因（已實查 `wf-state.sh` 原始碼與多次隔離重現確認）**：
  - `promote`（Line 144-163）只做兩件事：把 `.branch` 欄位填上、把檔案搬到新 worktree。**它不碰 `stage` 也不碰 `mode`**——所以 promote 完的檔案仍是 `{mode: "sequence", stage: "0a"}`。
  - 但 SKILL.md 的「狀態機腳本」表格指示 STAGE 1 建好 worktree 後執行 `stage-done <檔> 1`。
  - `stage-done`（Line 176-187）在 sequence 模式下強制 `<stage> 參數 == 目前 stage`（Line 182-184）。此時目前 stage 還是 `0a`，傳 `1` 必被拒。
  - 換句話說：**SKILL.md 記載的 STAGE 1 收尾流程，在 sequence 模式下必定失敗**。正常 sequence 從 0a 一路 `advance` 上來時，promote 發生在 STAGE 1，但 stage 欄位並沒有跟著 promote 一起前進到 `1`，兩者脫節。
* **我最初的誤判（記錄下來以免重蹈）**：當下我把 `&&` 鏈的中斷誤讀成「`promote` 把 state 檔吃掉了」，還推測是 `--dest` 指向不存在目錄 + EXIT trap 所致。**這個診斷是錯的**——事後隔離重現證明 `promote` 對不存在的 dest 目錄運作完全正常（`mkdir -p` + `claim_new` 會建好），檔案該寫的有寫、該刪的 pending 有刪。真正的失敗是後續 `stage-done 1` 被 sequence guard 擋下，中斷了我串起來的 `&&` 鏈，而我沒往下追就 fallback 到 `init --mode jump` 重建。**教訓：`&&` 鏈中斷要逐段定位是哪一段 exit 非零，不要看到 `get` 報 pending 路徑就腦補整條鏈的因果。**
* **⚠️ 一個被否決的錯誤修復方向（記錄下來以免重蹈）**：本文件初稿曾提議「讓 `promote` 一併 `.stage = "1"`」，並自稱「promote 不受轉移表約束，安全」。**這是錯的，經 PR #100 的 CodeRabbit review 抓出並實查確認**：`promote` 不只服務 sequence-from-0a，還服務 **quick→sequence 升級路徑**——SKILL.md L288 明載，`upgrade`（已把 stage 設為 `2`）之後也走 `promote` 把狀態搬進 worktree。若 `promote` 無條件寫死 `stage=1`，會把升級後的 `stage=2` 打回 `1`，讓一個已在實作階段的流程重跑 STAGE 1。原方案只看了一條路徑就下「安全」結論，是典型的以偏概全。
* **正確的修復方向（於 2026-07-30 已實作，限定作用範圍，不動 `promote` 的共用邏輯）**：
  **修復方案：修改 SKILL.md 的 sequence STAGE 1 收尾流程，不碰腳本 (Workaround)**。
  正常 sequence 從 0a 一路 `advance` 上來，promote 之後 stage 仍是 `0a`。收尾時不該用 `stage-done 1`（會撞 guard），而是先 `advance 0b --confirmed` → `advance 1 --confirmed` 走完既有轉移表，stage 到 `1` 後才 `stage-done 1`。這條路徑本來就沒有 0a→0b 的暫停語意，兩個 `--confirmed` 是形式上的多餘，用來強行滿足底層腳本的過關條件。

  > **💡 最後放棄寫進腳本的原因（Linus 哲學與實用主義評估）：**
  > 雖然技術上大可在腳本內新增一段 `if mode==sequence && stage==0a` 的專屬跳躍邏輯，但最終選擇在 AI 操作手冊（SKILL.md）以 Workaround 繞過，原因有二：
  > 1. **破壞與回歸測試風險過高**：`wf-state.sh` 的狀態機是整體流程心臟。動到核心腳本就必須對另外三種啟動模式（`quick`、`jump`、`upgrade`）做全面性的回歸測試 (Regression Test)，牽一髮而動全身，違背「Never break userspace」原則。
  > 2. **實用主義與成本考量**：現有底層狀態機的轉移表（0a->0b->1）邏輯嚴謹且正確，沒有必要為了省兩行指令而去破壞底層架構。修改 SKILL.md 讓 AI 遵守嚴格的腳本規則，成本極低、零副作用且絕對安全。
* **影響面**：只要是**正常 sequence 流程**（非 `--mode jump`）跑到 STAGE 1，都會撞到。本次因為 fallback 到 jump 模式而繞過，但 jump 模式喪失了 sequence 的轉移表保護——是繞過不是修好。
* **驗證方法**：
  ```bash
  P=$(wf-state.sh init)                                    # sequence, stage 0a
  wf-state.sh promote "$P" --branch feat/x --dest wt/.claude/workflow-state
  WT=wt/.claude/workflow-state/feat-x.json
  wf-state.sh advance "$WT" 0b --confirmed
  wf-state.sh advance "$WT" 1 --confirmed
  wf-state.sh stage-done "$WT" 1
  
  # Assertions
  # jq -r '.stage' "$WT" 應為 "1"
  # jq -r '.awaiting_confirmation' "$WT" 應為 "true"
  ```

---

## 7. STAGE 1 規劃文件搬移需求（2026-07-30 補記）

> 此項由 SKILL.md commit `acf4f70`（2026-07-29）新增，非 brainstorm 原始提案，補記於此供完整性。

### 問題

STAGE 0a/0b 產出的功能規格（`docs/features/...`）與實作計畫（`docs/plans/...`）是在**原 repo 目錄**中建立的未 commit 檔案。STAGE 1 建立的新 worktree 從 `origin/main` checkout 出來，**不會包含這些檔案**。若不搬移，state 檔記錄的 `spec`/`plan` 路徑切進 worktree 後指向不存在的檔，STAGE 2 的 implementer 讀不到計畫。

### 已落地的解決方案（SKILL.md「分支與 Worktree 建立」章節步驟 5）

> **✅ 2026-08-17 實查核對**：`main` 的 `.claude/skills/gen-dev-workflow/SKILL.md:247-257` 確有此步驟，
> 標題為「🔴 帶入 STAGE 0a/0b 產出的規劃文件（正常路徑必做）」。**本節「已落地」標記成立。**
> 核對時發現本節有兩處與實作不符，已於下方更正（原記載保留為刪節線供追溯）。

- STAGE 1 建好 worktree 後、`cd` 進去之前，先 `mkdir -p` 目標目錄，再用 `cp` 將原 repo 中的 spec 和 plan 檔案複製到新 worktree 的同名路徑下。
- 用**複製**不用 commit + cherry-pick：規劃文件在原 repo 尚未 commit，~~複製後由 STAGE 2 的實作 commit 一併帶進 branch~~ → **複製過去後在 worktree 中呼叫 `gen-commit` 將文件 commit**，不需在 base branch 上多留一個 commit。
- 複製後驗證兩檔案都存在於新 worktree，缺任一個就停下回報，**並於確認存在後執行 `gen-commit`，不要帶著未 commit 的狀態進 STAGE 2**。
- **路徑維持 repo 相對路徑不變**（例 `docs/plans/2026-05-03-cart.md`），所以 state 檔的 `spec`/`plan` 欄位**不需改寫**，切目錄後自然指向新 worktree 內的同名檔——這正好解掉本節「問題」段落擔心的路徑失效。
- 原 repo 的那兩份留著不刪：它們是規劃階段的產物，刪除等於在使用者還沒確認流程走完前銷毀資料。
- issue-id 路徑（跳過 STAGE 0a/0b）沒有這兩份文件，本步驟略過。

> **📌 兩處更正的意義**：commit 時機從「留到 STAGE 2 順便」收緊為「當場 commit」，
> 是刻意的——未 commit 的規劃文件跨越 stage 邊界，等於讓 STAGE 2 在一個髒工作區上開工。
> 這與本文件反覆論證的「別讓保證依賴後續步驟記得做」是同一條原則。

### 與 Bug 1.6 的交互作用

Bug 1.6 的 promote 斷裂**不影響此搬移步驟**——搬移是在 promote 之後、`stage-done` 之前的獨立動作。但若 Bug 1.6 導致 STAGE 1 收尾失敗而 fallback 到 jump 模式，jump 模式跳過 pending→promote 流程，可能也跳過此搬移步驟（jump 模式自 init 就直接建在 worktree 內，不經過「原 repo → 新 worktree」的搬移）。issue-id 路徑本身不受影響（無 spec/plan 檔可搬）。

---

## 🔵 第二部分：多 Agent 框架比對與 2.0 架構優化提案 (2026-07-30)

## 1. 開源多 Agent 框架深度比對矩陣與架構解析

為提升 `gen-dev-workflow` 的架構品味與多 Agent 協作能力，我們針對目前業界最具代表性的 4 個開源多 Agent 軟體開發框架進行深度解構：

1. **MetaGPT** (DeepWisdom)：基於 SOP (Standard Operating Procedure) 的結構化 Markdown 文件驅動框架。
2. **AutoGen** (Microsoft)：基於靈活對話式網絡 (Conversational Network) 與動態 GroupChat / Director 的多 Agent 框架。
3. **SWE-agent** (Princeton)：專為 GitHub Issue 自動修復設計的 ACI (Agent-Computer Interface) 工具驅動框架。
4. **ChatDev** (OpenBMB)：採用瀑布式/敏捷階段化 Chat Chain 與對立角色雙重校驗（Double-check）的模擬軟體公司框架。

### 1.1 完整多維度架構比對矩陣

| 比較維度 | MetaGPT | AutoGen (Microsoft) | SWE-agent (Princeton) | ChatDev (OpenBMB) | `gen-dev-workflow` (本專案) |
|:---|:---|:---|:---|:---|:---|
| **1. 任務分解 (Task Decomposition)** | 基於 SOP 範本（PRD, Architecture design, Tasks）一次性層級化分解。 | 動態對話中由 Admin / UserProxyAgent 或 LLM Director 隨機應變拆解。 | 依據 Issue 描述由 Single Agent 透過 ACI 進行一步步搜尋與定位。 | Chat Chain 階段化分解（Demand, Coding, Testing, Documentation）。 | 兩階段拆解：STAGE 0a/0b 規劃，STAGE 2 依 task 陣列單元推動。 |
| **2. 角色分工 (Role Specialization)** | 嚴格角色定義（PM, Architect, Engineer, QA），強型別輸出。 | 靈活 Prompt 角色（Assistant, UserProxy, Critic），基於對話輪詢。 | 單一全能 Agent (SweAgent)，無多角色切換，高度依賴 ACI 工具。 | 雙角色階段對話（CEO↔CPO, CTO↔Programmer, Reviewer↔Tester）。 | 專用角色 Agent（brancher, implementer, reviewer, publisher, responder）。 |
| **3. 狀態持久化 (State Persistence)** | 依賴結構化文件（`docs/`）與 Message History 序列化。 | 記憶體內部 Message History、可選 Save/Restore Session 狀態。 | 軌跡日誌 (.traj)，記錄每步 ACI 指令與環境 Feedback。 | Phase 狀態 JSON、Chat log 與實體程式碼產物。 | 雙重持久化：JSON 狀態檔 (`wf-state.sh`) + Git worktree / commit 快照。 |
| **4. 記憶體管理 (Memory Management)** | `Memory` 類別，發佈-訂閱 (Pub/Sub) 訊息總線 (Environment)。 | 對話長度限制、Context 壓縮或外掛 vector store / RAG 擴充。 | 自訂 ACI 觀察截斷與關鍵提示詞 Window 滾動機制。 | 階段結束後總結對話歷史，傳遞精簡Context至下一 Phase。 | Token Budget Gate（>150k 自動 checkpoint）與 Observation truncate。 |
| **5. 執行環境 (Execution Env)** | 本地 Python 環境或 Docker 容器。 | Docker 容器沙盒（`DockerCommandLineCodeExecutor`）確保安全。 | Docker 容器環境（SWE-bench 評測專用沙盒）。 | 本地 Python 虛擬環境。 | Git worktree 物理目錄隔離 + 本地 Shell / `agy` CLI 執行。 |
| **6. 品質與驗證 (Quality Verification)** | 自動化單元測試產製、程式碼審查文件 (Code Review SOP)。 | Human-in-the-loop 確認、對話終止條件（TERMINATE）、代碼執行測試。 | 執行專案既有 Test Suite、語法檢查與 Diff 比對驗證。 | Tester Agent 執行程式，過濾黑盒測試與白盒測試錯誤。 | 雙層審查：STAGE 3 code-review、STAGE 5 PR review，結合 test-worker。 |
| **7. 擴充性 (Extensibility)** | 自訂 Role / Action / SOP 範本，擴充性極高。 | 開放對話網絡架構，可任意自訂 Agent 轉移圖 (GroupChatManager)。 | 客製化 ACI 指令集 (.yaml 配置檔)，適合改進 Tooling。 | 自訂 Chat Chain 節點與角色 Prompt 字典檔。 | Bash 腳本 (`wf-state.sh`) + Markdown Skill (.agents/)，易於自訂擴充。 |
| **8. 容錯與恢復 (Fault Tolerance)** | 重新觸發失敗 Action，依賴 SOP 重試機制。 | 人工干預輸入、自動重試上限、Fallback 至其他 Agent。 | 軌跡重放 (Replay) 與錯誤恢復 ACI 命令。 | 多輪對話自動修正語法與執行錯誤。 | 本地快照 Tag (wf-checkpoint) 自動回滾，支援 `cmd_rollback.sh`。 |

---

### 1.2 開源框架的核心架構亮點與啟示

1. **MetaGPT 的啟示 — SOP 標準作業程序與強型別文件**
   - *亮點*：MetaGPT 成功證明了「人類 SOP 是約束 LLM 幻覺的最強武器」。將複雜軟體開發拆解為 PM 寫 PRD → 系統架構師寫 Data Structures & Interface Definitions → 工程師寫 Code 的線性流水線，極大地降低了語意模糊度。
   - *gen-dev-workflow 借鏡*：保留並強化 STAGE 0a (Issue Analysis) → STAGE 0b (Spec & Plan) → STAGE 2 (Task Execution) 的文件驅動流水線，並確保各階段產出（`docs/issues/specs/`）格式嚴格受到 Schema 檢驗。

2. **AutoGen 的啟示 — 彈性對話圖與動態暫停控制**
   - *亮點*：AutoGen 允許動態切換 Human-in-the-loop 模式（`ALWAYS` / `NEVER` / `TERMINATE_ONLY`）。在不需要人類干預時能全速運轉，遇到關鍵節點或異常時才主動轉交控制權。
   - *gen-dev-workflow 借鏡*：消除過往「每完成一個小 Task 就強制人工點擊確認」的打擾行為，引進 `pause_level`（`strict` / `balanced` / `autonomous`）動態暫停粒度。

3. **SWE-agent 的啟示 — ACI 簡化觀察與專用環境保護**
   - *亮點*：SWE-agent 發現 LLM 面對數千行 Terminal 輸出時極易流失注意力。其 ACI (Agent-Computer Interface) 機制只顯示關聯行數，並提供專用視窗滾動工具；同時所有破壞性改動均在獨立容器沙盒內進行。
   - *gen-dev-workflow 借鏡*：導入 Proposal 3 的 `wf-truncate.sh` 動態觀察截斷引擎，將過長 Build/Test 輸出優雅折疊；同時利用 Git worktree 與安全回滾保護 metadata。

4. **ChatDev 的啟示 — 雙角色對話校驗與階段化 Checkpoint**
   - *亮點*：ChatDev 在 Code Review 與 Testing 階段採用雙角色互相對抗校驗（Reviewer 與 Programmer 對話修正直到通過），並在階段交接時對 Context 進行歸納壓縮，避免歷史對話污染。
   - *gen-dev-workflow 借鏡*：在 STAGE 3 Reviewer 與 STAGE 5 Responder 之間建立明確的閉環狀態轉移表（`reviewer ↔ responder`），確保審查退回後可正確重試。

---

## 2. `gen-dev-workflow` 未解痛點與架構瓶頸深度分析

雖然 2026-07-21 的歷史修復穩固了地基，但在實戰對抗與極限壓力測試中，`gen-dev-workflow` 仍暴露出 5 大致命痛點：

### 2.1 痛點一：人在迴路（Human-in-the-loop）頻率過高致體驗崩潰
- **現象與瓶頸**：原流程在 STAGE 2 實作階段中，每完成一個小 Task 就會觸發 `awaiting_confirmation=true` 並強行暫停，要求使用者輸入 confirm 或點擊確認。若一個 Feature 拆解為 8 個 Task，使用者必須被被打斷 8 次，使自動化編排器退化為「高頻打擾器」。
- **根因分析**：`wf-state.sh` 腳本中 `stage-done` 與 `task-done` 寫死了暫停邏輯，缺乏動態調整暫停層級（Granularity）的配置欄位；同時 `apply_sets()` key 白名單拒絕外來 key 寫入，導致無法靈活切換自動化程度。

### 2.2 痛點二：跨 Session 狀態盲區（Multi-Session State Blindness）
- **現象與瓶頸**：當工作流推進至 STAGE 1 並促動（promote）狀態 JSON 至 Worktree 目錄（`.claude/workflow-state/`）後，Root 倉庫對應的 JSON 會被刪除。當使用者在 Root 倉庫重新開啟 Claude session 試圖執行 `continue` 續接時，系統會回報「找不到任何活動中的工作流」。
- **根因分析**：雖然 `SKILL.md` 規範了跨 Worktree 搜尋，但當 CLI 或入口腳本在 Root 執行時，缺乏全域掃描機制，且缺標準化的 Worktree 狀態檢索匯流排。

### 2.3 痛點三：外部 `agy` CLI 強耦合與退出碼遮蔽漏洞 — 🔄 已改善（2026-08-10 換傳輸層）
- **現象與瓶頸**：流程的核心子 Agent 委派動作高度依賴外部 `agy` CLI 命令。然而當 `agy` 執行內層指令失敗（例如 `flutter test` 返回非零退出碼 `1`）時，封裝腳本因未正確傳播內層退出碼，誤將狀態捕捉為 `0` (Success)，導致測試失敗卻被系統認定為成功的致命誤判。
- **根因分析**：舊版執行腳本在 `agy` 命令返回後未紀錄 `$?` 便進入警告與 fallback 區塊，吞掉了原始 Exception。

> **🔍 2026-08-10 校正**（與前半部 §2.3 為同一議題，此處為第二部分的重述）：
> 委派已改走 MCP（`mcp__gemini-cli__ask-gemini`），**不再經過 bash 子進程，沒有 `$?` 可傳播**——
> 「退出碼遮蔽」這個具體形狀消失了。
>
> 但**核心風險換了外衣仍在**：MCP 回傳純文字，一樣沒有成功/失敗的機器可判訊號，
> 子進程宣稱「測試通過」與舊版 exit 0 誤判**危害等價**。
> 對策不是轉接層（見 §3 提案 4 的不採用理由），而是**驗收紀律**：
> 主對話親自跑測試與 `git log` / `git status` 驗證，不採信回報文字。

### 2.4 痛點四：不安全的 Git 回滾與 Metadata 破壞風險
- **現象與瓶頸**：當審查退回或任務失敗觸發自動回滾（Rollback）時：
  1. 無法處理 `review` 階段退回標籤（未支援 `target_type="review"`）。
  2. 當分支名稱包含斜線（如 `feature/login`）時，因未轉換為橫槓 slug (`feature-login`)，導致 Checkpoint Tag 比對 100% 失敗。
  3. 任務失敗時，索引計算錯誤地取用 `completed_tasks[-1]`（即已完成的上個任務），導致回滾時誤刪已完成的合法工作成果。
  4. 執行 fallback `git clean -fd` 時，無差別清掉了 `.agents/` 目錄下的計畫與元資料。

### 2.5 痛點五：Observation 截斷算術溢位與暫存資源洩漏
- **現象與瓶頸**：原 truncation 腳本硬編碼假設 `MAX_LINES >= 80`（固定 `head -n 40` 與 `tail -n 40`）。當設定 `MAX_LINES=50` 傳入 60 行輸出時，算術評估算出 `-20 lines omitted`，不僅產生重複行，還輸出 83 行，完全失去截斷作用。此外，中斷執行時未清除 `/tmp` 暫存檔，造成檔案洩漏；`2>&1` 混流輸出則毀損了結構化 JSON 資訊。

---

## 3. 具體架構優化提案與技術實作規格

為徹底解決上述 5 大痛點，我們提出 4 項經實證測試（Empirical Stress Test）嚴格驗證通過的架構優化提案，並附上完整、可直接執行的 Bash 原始碼規格。

---

### 提案 1：動態暫停粒度與狀態機白名單擴展 (`pause_level`) — ✅ 已完成（2026-08-06 · `9bce068`）

> **落地位置**：`wf-state.sh:141` `should_pause()`（單一判定來源）、`:172` enum 校驗、
> `:269`/`:286` 兩個呼叫端；使用者介面見 SKILL.md:179「暫停粒度」與 :872「選項語法」。
> 三處刻意偏離原設計的說明見文末「落地現況」節。下方規格保留作決策紀錄。

#### 1. 設計規格
- **支援三段式枚舉 (`pause_level`)**：
  - `strict`（預設）：在**所有**階段關卡（Stage Gate）與 Task 完成時皆強制暫停 (`awaiting_confirmation=true`)。
  - `balanced`（建議）：僅在**主要架構關卡**（`0b` 規格確認, `2` 實作完成, `4` PR 準備發佈）暫停；中間過渡階段（`0a`, `1`, `3`）與 STAGE 2 內部的 Task 迴圈自動推進 (`awaiting_confirmation=false`)。
  - `autonomous`（極速/自動）：除非發生 Error 或顯式標記，否則所有階段與 Task 皆自動推進，不暫停等待。
- **白名單與防錯校驗**：
  - `apply_sets()` 擴充 key 白名單，包含 `pause_level`。
  - 嚴格校驗傳入值是否為 `strict|balanced|autonomous` 之一，非法值立即 `die` 中止，避免寫入無效狀態。
  - `stage-done` 與 `task-done` 當 `pause_level` 缺失或解析異常時，自動退回安全預設值 `strict`。

#### 2. 可執行 Bash 實作區塊（`wf-state.sh` 升級程式碼）

```bash
# 1. 擴充 apply_sets() key 白名單與嚴格 enum 校驗
apply_sets() {
  local json="$1"; shift
  local kv k v
  for kv in "$@"; do
    if [[ "$kv" != *=* ]]; then
      die "參數格式錯誤：'$kv'。必須為 k=v 格式"
    fi
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      spec|plan|branch|issue|pr|total_tasks|interrupted_by|pause_level)
        if [ "$k" = "pause_level" ]; then
          case "$v" in
            strict|balanced|autonomous) ;;
            *) die "不可設定無效的 pause_level 值：'${v}'（允許值：strict, balanced, autonomous）" ;;
          esac
        fi
        ;;
      *) die "不可透過 set 修改欄位：${k}（stage 用 advance、確認用 confirm）" ;;
    esac
    json="$(echo "$json" | jq --arg k "$k" --argjson v "$(jq_val "$v")" '.[$k] = $v')"
  done
  echo "$json"
}

# 2. stage-done 動態暫停邏輯
stage-done)
  f="$(resolve "$1")"; stage="$2"
  validate "$f"
  mode="$(jq -r '.mode' "$f")"; cur="$(jq -r '.stage' "$f")"
  if [ "$mode" = "sequence" ] && [ "$stage" != "$cur" ]; then
    die "sequence 模式 stage-done 參數須等於目前 stage（目前：${cur}），改 stage 請用 advance"
  fi
  pause_level="$(jq -r '.pause_level // "strict"' "$f")"
  case "$pause_level" in
    strict) awaiting=true ;;
    balanced)
      case "$stage" in
        0b|2|4) awaiting=true ;;
        *) awaiting=false ;;
      esac
      ;;
    autonomous) awaiting=false ;;
    *) awaiting=true ;; # 無效字串之安全備援
  esac
  jq --arg s "$stage" --argjson a "$awaiting" '.stage = $s | .awaiting_confirmation = $a' "$f" | atomic_write "$f"
  if [ "$awaiting" = "true" ]; then
    echo "stage $stage 完成 → 等待使用者確認（confirm 或 advance --confirmed 才能繼續）"
  else
    echo "stage $stage 完成 (pause_level: $pause_level) → 自動推進"
  fi
  ;;

# 3. task-done 動態暫停邏輯
task-done)
  f="$(resolve "$1")"; n="$2"
  validate "$f"
  mode="$(jq -r '.mode' "$f")"; cur="$(jq -r '.stage' "$f")"
  if [ "$mode" = "sequence" ] && [ "$cur" != "2" ]; then
    die "sequence 模式 task-done 僅能在 STAGE 2 執行（目前 stage：${cur}）"
  fi
  pause_level="$(jq -r '.pause_level // "strict"' "$f")"
  case "$pause_level" in
    strict) awaiting=true ;;
    balanced|autonomous) awaiting=false ;;
    *) awaiting=true ;; # 安全備援
  esac
  jq --argjson n "$n" --argjson a "$awaiting" \
    '.completed_tasks = ((.completed_tasks + [$n]) | unique) | .awaiting_confirmation = $a' \
    "$f" | atomic_write "$f"
  if [ "$awaiting" = "true" ]; then
    echo "任務 $n 完成 → 等待使用者確認"
  else
    echo "任務 $n 完成 (pause_level: $pause_level) → 自動繼續下個任務"
  fi
  ;;
```

---

### 提案 2：安全 Worktree 與 Review Tag 導向 Git 回滾引擎 (`cmd_rollback.sh`)

#### 1. 設計規格
- **支援多元 Target 型態**：
  - `task` [選填 `$3` task_num]：回滾至當前/失敗任務前之快照點。當未指定 `$3` 時，正確算出 `target_task = completed_count + 1`；若特定 task 標籤不存在，降級尋找 `completed_count` 標籤。
  - `review`：處理審查不通過回滾，尋找 `wf-checkpoint-${slug_branch}-review` 或降級尋找 `wf-checkpoint-${slug_branch}-stage-3`。
- **分支 Slug 規格化**：強制執行 `slug_branch=$(echo "$branch" | tr '/' '-')`，消滅分支名稱中斜線導致的 Tag 比對失效。
- **Metadata 目錄強效防護**：執行 fallback `git clean` 時，強制加上 `-e ".agents" -e ".agents/*"` 排除過濾，絕不傷害元資料。

#### 2. 可執行 Bash 腳本實作 (`cmd_rollback.sh`)

```bash
#!/usr/bin/env bash
# cmd_rollback.sh — 安全自動化 Git 回滾引擎

cmd_rollback() {
    local file="$1" target_type="${2:-task}" target_num="${3:-}"
    local branch slug_branch tag_name completed_count task_num
    
    if [ ! -f "$file" ]; then
        echo "Error: 狀態檔案 '$file' 不存在。" >&2
        return 1
    fi
    
    branch=$(jq -r '.branch // ""' "$file")
    if [ -z "$branch" ] || [ "$branch" = "null" ]; then
        echo "Error: 狀態檔案 '$file' 中未指定有效分支名稱。" >&2
        return 1
    fi
    
    # 規格化分支名稱斜線為橫槓 (例如: feature/login -> feature-login)
    slug_branch=$(echo "$branch" | tr '/' '-')
    
    if [ "$target_type" = "task" ]; then
        completed_count=$(jq -r '.completed_tasks | length // 0' "$file")
        # 未指定 target_num 時，正在執行的失敗任務索引為 completed_count + 1
        task_num="${target_num:-$((completed_count + 1))}"
        tag_name="wf-checkpoint-${slug_branch}-task-${task_num}"
        
        # Fallback 檢查：若該 Task Snapshot 不存在，退回上個已完成任務之快照 Tag
        if ! git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
            tag_name="wf-checkpoint-${slug_branch}-task-${completed_count}"
        fi
        
    elif [ "$target_type" = "review" ]; then
        tag_name="wf-checkpoint-${slug_branch}-review"
        if ! git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
            tag_name="wf-checkpoint-${slug_branch}-stage-3"
        fi
    else
        echo "Error: 未知的回滾 target_type '$target_type'（允許值：'task' 或 'review'）。" >&2
        return 1
    fi
    
    if git rev-parse --verify "$tag_name" >/dev/null 2>&1; then
        git reset --hard "$tag_name"
        echo "已成功自動回滾至快照點: $tag_name"
    else
        echo "未找到快照 Tag ($tag_name)，執行安全重設與受保護清理..."
        git checkout -- .
        # 保護 .agents 元資料目錄不被 git clean 清除
        git clean -fd -e ".agents" -e ".agents/*"
    fi
}

cmd_rollback "$1" "$2" "$3"
```

---

### 提案 3：動態 Observation 截斷與資源清理引擎 (`wf-truncate.sh`)

#### 1. 設計規格
- **動態 Head/Tail 算術**：
  - `HEAD_LINES = (MAX_LINES - 1) / 2`
  - `TAIL_LINES = MAX_LINES - 1 - HEAD_LINES`
  - `OMITTED_LINES = TOTAL_LINES - HEAD_LINES - TAIL_LINES`
  - 保證在任何 `MAX_LINES >= 1` 的情況下，輸出總行數精準等於 `MAX_LINES`，絕不產生負數省略行數或行數重複重疊。
- **POSIX Signal Trap 資源清理**：掛載 `trap 'rm -f "$TMP_OUT"' EXIT INT TERM`，保證無論正常結束、中斷或被 Kill，暫存檔必定自動清理。
- **標準流隔離**：僅截斷 Stdout 串流；Stderr 保持獨立輸出，維護 JSON 結構化解析品質。

#### 2. 可執行 Bash 腳本實作 (`wf-truncate.sh`)

```bash
#!/usr/bin/env bash
# wf-truncate.sh — 動態 Observation 觀察輸出截斷引擎

MAX_LINES=${MAX_LINES:-100}
if ! [[ "$MAX_LINES" =~ ^[0-9]+$ ]] || [ "$MAX_LINES" -lt 3 ]; then
    MAX_LINES=3
fi
TMP_OUT=$(mktemp)

# POSIX Trap 處理器：保證退出或接收訊號時必刪暫存檔
trap 'rm -f "$TMP_OUT"' EXIT INT TERM

# 執行內層指令並補獲 stdout
"$@" > "$TMP_OUT"
EXIT_CODE=$?

TOTAL_LINES=$(wc -l < "$TMP_OUT")
if [ "$TOTAL_LINES" -gt "$MAX_LINES" ]; then
    # 動態計算 Head 與 Tail 預算，嚴格遵守 MAX_LINES 上限
    HEAD_LINES=$(( (MAX_LINES - 1) / 2 ))
    TAIL_LINES=$(( MAX_LINES - 1 - HEAD_LINES ))
    OMITTED_LINES=$(( TOTAL_LINES - HEAD_LINES - TAIL_LINES ))
    
    head -n "$HEAD_LINES" "$TMP_OUT"
    echo -e "\n... [ Observation Collapsed: ${OMITTED_LINES} lines omitted by wf-truncate ] ...\n"
    tail -n "$TAIL_LINES" "$TMP_OUT"
else
    cat "$TMP_OUT"
fi

exit $EXIT_CODE
```

---

### 提案 4：退出碼保留之跨引擎執行層 (`wf-exec.sh`) — ❌ 不採用（2026-08-10 前提已變）

> **🔍 2026-08-10 校正**：本提案的前提是「委派走 `agy -p`，需要一層 bash 轉接保退出碼」。
> 2026-08-10 起委派改走 **MCP 工具呼叫**，**不再經過 bash 子進程**——
> 沒有 `$?` 可保留，`wf-exec.sh` 這個形狀已無對應物。
>
> 但**它要解決的問題沒有消失，只是換了形式**：MCP 回傳純文字，同樣沒有 exit code，
> 子進程宣稱「測試通過 / 已 commit」一樣不可採信。
> **對策不是寫轉接層，而是驗收紀律**——已寫進 `implementer.md` 的
> 「回報不等於事實」與 SKILL.md 委派紀律第 3 條：主對話親自跑
> `git log` / `git status` / 測試確認，不採信回報文字。
>
> 下方原規格保留作決策紀錄，**不列入待辦**。

#### 1. 設計規格
- **退出碼精準傳播**：捕獲 `agy` 或 Native 子指令執行後之回傳碼 `RC=$?`，並立即執行 `exit $RC`，杜絕任何測試/編譯失敗被遮蔽為成功 (Exit 0) 的漏洞。
- **主動式 Native Fallback 執行**：當環境未安裝 `agy` CLI 時，不再僅印出提示文字，而是透過 `bash -c "$PROMPT"` 主動執行可執行的 Shell 命令或測試指令，並如實回傳其退出碼。

#### 2. 可執行 Bash 腳本實作 (`wf-exec.sh`)

```bash
#!/usr/bin/env bash
# wf-exec.sh — 退出碼保留之跨引擎執行與 Fallback 轉接層

PROMPT="$1"
MODEL_TIER="${2:-standard}"

if [ -z "$PROMPT" ]; then
    echo "Usage: wf-exec.sh <prompt_or_cmd> [model_tier]" >&2
    exit 1
fi

if command -v agy >/dev/null 2>&1; then
    # 透過 agy CLI 委派執行命令
    printf '%s' "$PROMPT" | agy -p --print-timeout 2>/dev/null
    RC=$?
    # 必須精準返回 agy 執行之退出碼，保留錯誤狀態
    exit $RC
fi

# 當環境欠缺 agy CLI 時之 Fallback 備援路徑
echo "⚠️ agy CLI 未安裝，切換至 Native Subagent Fallback..." >&2
echo "[WF-EXEC FALLBACK] 透過 Native Runner 執行任務:"
echo "$PROMPT"

# 若 PROMPT 為可執行指令或腳本，直接以 bash -c 執行並傳播退出碼
if command -v "${PROMPT%% *}" >/dev/null 2>&1 || [ -x "$PROMPT" ]; then
    bash -c "$PROMPT"
    exit $?
else
    echo "Error: Prompt 既非可執行命令，亦無法由 agy CLI 解析。" >&2
    exit 127
fi
```

---

## 4. 實作藍圖、遷移策略與全方位驗證計畫

為確保上述架構升級順利落地且不破壞現有工程（Never break userspace），我們制定了 3 階段實作藍圖與 4 層驗證協定。

### 4.1 3 階段實作藍圖 (Implementation Roadmap)

```
[Phase 1: 基礎腳本實體升級]
  ├── 寫入 optimization_proposals.md 至工具集
  ├── 更新 wf-state.sh (包含 pause_level 白名單與 stage-done/task-done)
  └── 部署 cmd_rollback.sh, wf-truncate.sh, wf-exec.sh 獨立腳本
        │
        ▼
[Phase 2: SKILL.md 與對話狀態轉移綁定]
  ├── 升級 SKILL.md 之 advance / continue 指令範例
  ├── 在 STAGE 2 自動化循環中整合 wf-truncate.sh 與 wf-exec.sh
  └── 部署跨 Worktree 全域狀態掃描邏輯
        │
        ▼
[Phase 3: 多 Agent 協調與閉環驗證]
  ├── 進行跨 Session 復原與終端壓力測試
  ├── 執行 Challenger 實證測試套件 (empirical_stress_tests.py)
  └── 完成最終 Forensic Auditor 獨立稽核
```

1. **Phase 1 — 基礎腳本升級 (Foundation Layer)**：
   - 在 `.agents/skills/gen-dev-workflow/scripts/` 中部署與替換 `wf-state.sh`、`cmd_rollback.sh`、`wf-truncate.sh` 與 `wf-exec.sh`。
   - 確保所有 `.sh` 檔案具備可執行權限（`chmod +x`）。
2. **Phase 2 — Skill 與對話綁定 (Workflow Skill Integration)**：
   - 更新 `SKILL.md` 中關於 `init` 與 `set` 的說明，新增 `pause_level=balanced` 為預設建議值。
   - 將 `continue` 搜尋邏輯升級為強效 Worktree 掃描。
3. **Phase 3 — 多 Agent 閉環驗證與營運 (Validation & Operations)**：
   - 運行自動化壓力測試，確保在高併發、高打斷、極端字串與異常命令下系統依然保持韌性。

---

### 4.2 4 層驗證協定 (4-Tier Verification Protocol)

為達到最高品質標準，必須通過以下 4 層驗證：

```
+-------------------------------------------------------------------+
| Tier 1: Bash 單元與邊界測試 (Unit & Boundary Validation)            |
|   - 驗證 apply_sets() pause_level 白名單阻擋與合法設定               |
|   - 驗證 jq_val 負數解析與 shift 2 參數欠缺保護                       |
+-------------------------------------------------------------------+
                                │
                                ▼
+-------------------------------------------------------------------+
| Tier 2: Worktree 隔離與 Rollback 安全驗證 (Worktree & Rollback)     |
|   - 驗證 cmd_rollback feature/login 含斜線分支 slug 轉換             |
|   - 驗證 target_type="review" 及 target_num=completed_count+1       |
|   - 檢查 git clean 執行後 .agents/ 目錄完好無損                      |
+-------------------------------------------------------------------+
                                │
                                ▼
+-------------------------------------------------------------------+
| Tier 3: Truncation 動態算術驗證 (Observation Truncation Math)     |
|   - 驗證 MAX_LINES=50 於 60 行輸入時產出精準 50 行，無負數 omitted 行  |
|   - 觸發 SIGINT/SIGTERM 確認 /tmp 暫存檔自動刪除無殘留                |
+-------------------------------------------------------------------+
                                │
                                ▼
+-------------------------------------------------------------------+
| Tier 4: Exit Code 保留與 Fallback 驗證 (Exit Code Propagation)    |
|   - 故意執行失敗指令 (exit 1)，確認 wf-exec.sh 精準回傳退出碼 1       |
|   - 驗證 agy 缺失時 Native Fallback 正確轉接執行                     |
+-------------------------------------------------------------------+
```

#### 具體驗證指令與預期結果：

1. **Tier 1 (Bash 腳本邊界驗證)**：
   ```bash
   # 測試非法 pause_level 是否被阻擋
   ./wf-state.sh set config.json pause_level=invalid_value
   # 預期：輸出 "不可設定無效的 pause_level 值..." 且 exit code = 1
   ```

2. **Tier 2 (Rollback 安全與 Tag Slug 驗證)**：
   ```bash
   # 測試含斜線分支回滾與 .agents 防護
   ./cmd_rollback.sh config.json task
   # 預期：成功識別 feature-login 快照點，或執行 git clean -fd -e ".agents" -e ".agents/*"
   ```

3. **Tier 3 (Truncation 算術與 Trap 驗證)**：
   ```bash
   # 測試 MAX_LINES=50 輸入 60 行
   seq 1 60 | MAX_LINES=50 ./wf-truncate.sh cat
   # 預期：總輸出列印精準 50 行，包含折疊提示 "... [ Observation Collapsed: 11 lines omitted by wf-truncate ] ..."
   ```

4. **Tier 4 (Exit Code 傳播驗證)**：
   ```bash
   # 測試錯誤碼傳播
   ./wf-exec.sh "false"
   echo $?
   # 預期：輸出 1 (絕對不可為 0)
   ```

---

### 4.3 向後相容性與無痛遷移策略 (Backward Compatibility)

1. **零破壞保證 (Never Break Userspace)**：
   - 舊有狀態 JSON 若未包含 `pause_level` 欄位，`wf-state.sh` 透過 `jq -r '.pause_level // "strict"'` 安全退回至舊有 `strict` 行為，現有腳本完全無需修改即可運作。
2. **漸進式升級 (Progressive Adoption)**：
   - 新建立的 workflow 可在 `init` 或 `STAGE 0b` 完成後執行 `wf-state.sh set config.json pause_level=balanced`，即刻享受低打斷的流暢開發體驗。

---

## 5. 借鏡 teamwork-preview 的架構改善提案 (2026-07-31 補記)

> 此章節基於對 teamwork-preview 的逆向工程分析（詳見 [`docs/brainstorm/2026-07-31-teamwork-as-skill-architecture.md`](2026-07-31-teamwork-as-skill-architecture.md)），
> 從其多智能體協作引擎中萃取出可直接移植至 `gen-dev-workflow` 的 5 項具體改善方向。
> 每一項皆遵循「Never break userspace」原則，確保既有流程零破壞。

### 5.1 STAGE 0a 平行化勘查 (Parallel Context Survey) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**，但**載體與原提案不同**——
> 不是「主 Agent 逐個 `invoke_subagent`」，而是走 **Claude `Workflow` 工具的 `parallel()` fan-out**。
> 證據：`.claude/skills/gen-dev-workflow/SKILL.md:722-725` 已有雙線平行 `agent()` 呼叫
> （`收集專案 context：讀 README / pubspec / 近期 git log` + `調查與「<需求>」相似的既有實作`），
> 皆以 `agentType: 'Explore'`（唯讀搜尋）搭配 `model: 'sonnet'` / `effort: 'high'` 執行。
> 另 SKILL.md:21 明列此為 Workflow 三個適用點之一。
>
> **與原提案的三處差異**（皆為刻意調整，非未完成）：
> 1. **2 線而非 3 線**——原提案的 Explorer 1（讀 GitHub Issue）在實際流程中不屬 STAGE 0a
>    的平行範圍（issue 建立在 STAGE 1），故收斂為「專案 context」+「相似實作調查」兩線。
> 2. **不寫 `.agent-output/context/<issue-id>/survey-<n>.md`**——改由 Workflow 的 `schema`
>    直接回傳結構化結果給主指揮聚合，省掉中間檔案的讀寫往返。
> 3. **Model 用 `sonnet` 而非 `flash`**——Claude 側無 `flash` 別名，對應等級見 SKILL.md 的
>    「推論等級表」（唯讀勘查歸「輕量」級）。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
STAGE 0a（Issue 分析與 Context 收集）目前由單一 Agent 序列執行：讀 Issue → 搜程式碼 → 查文檔 → 檢查測試覆蓋。這些步驟彼此無相依，卻被迫排隊等待，浪費時間。

**teamwork-preview 怎麼做**：
Step 0 同時派發 3 個 Explorer（框架研究 / 本地程式碼 / 文檔歷史），各自獨立平行探索，完成後寫入獨立報告檔，Orchestrator 收齊後才進入下一階段。

**gen-dev-workflow 可借鏡的做法**：
```
STAGE 0a (改良後):
  主 Agent 同時 invoke 2~3 個 research subagent：
  ├── Explorer 1: 讀 GitHub Issue 詳情 + 關聯 Issue
  ├── Explorer 2: 搜尋 codebase 中相關程式碼路徑 (codebase-memory-mcp)
  └── Explorer 3: 檢查既有 docs/specs/test 覆蓋
  
  各 Explorer 寫入 .agent-output/context/<issue-id>/survey-<n>.md
  主 Agent 收齊後彙整為統一的 context 文件
```

**好處**：STAGE 0a 耗時從 `T1 + T2 + T3` 降為 `max(T1, T2, T3)`。且各 Explorer 使用 `flash` Model，成本極低。

**向後相容**：純粹是 SKILL.md 層面的流程改良，不動 `wf-state.sh` 狀態機。現有的 `context-collector` Skill 可作為 Explorer 的任務模板。

---

### 5.2 STAGE 2 Fresh Subagent Per Task (每任務全新子智能體) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**，且比原提案更進一步——
> 原提案是「逐 task 序列 spawn 全新 Worker」，實作走 **Workflow 的 `pipeline()` 並行**：
> 同一批內寫入路徑不重疊的任務同時派發，每個任務一個全新 subagent。
> 證據：`SKILL.md:739` 的
> `task => agent(task.prompt, {label: task.id, model: task.model, effort: task.effort, isolation: 'worktree', schema: TASK_SCHEMA})`
> ——`isolation: 'worktree'` 即「每任務獨立工作區、零歷史包袱」的 Fresh Worker 語意，
> 且比原提案多解決了「並行任務互相踩檔案」的問題。
>
> **與原提案的差異**：
> 1. **未新增 `execution_mode` 欄位**——原提案設想以 `inline` | `subagent` 切換新舊行為，
>    實作直接讓 Workflow 成為 STAGE 2 的可選加速層（SKILL.md:21 的「可選加速層」定位），
>    不需要在 `wf-state.sh` 增欄位。**這也是為什麼 `wf-state.sh` 的 key 白名單裡查無此欄位——
>    是設計決定，不是漏做。**
> 2. **驗收與實作 model 分離**——SKILL.md:631-637 額外規定驗收固定走 `verifier` agent
>    （`effort: 'xhigh'`），不讓同源 model 自審。這是原提案沒有的加碼。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
STAGE 2 在同一個 Session 中依序執行所有任務。到了 Task 5 或 Task 6 時，Context Window 已經被前面 4 個任務的實作細節（diff、測試輸出、commit message）塞滿，導致 Agent 注意力分散、品質下降、甚至觸發 Token Budget Gate 強制中斷。

**teamwork-preview 怎麼做**：
每個 Milestone 的 Worker 都是全新 spawn 的 subagent，零歷史包袱。Worker 只接收：Milestone 規格 + 相關檔案路徑 + 勘查摘要。完成後寫入交付物、commit、回報。

**gen-dev-workflow 可借鏡的做法**：
```
STAGE 2 (改良後):
  for each task in plan.tasks:
    1. 主 Agent 從 plan 提取 task 規格（含精確檔案路徑與測試指令）
    2. invoke_subagent(TypeName="self", Model=依複雜度選擇)
       Prompt 包含：
       - task 規格全文
       - 相關的 spec/plan 摘要（非全文）
       - 必須遵守的 TDD 步驟與 commit 規範
    3. Worker 完成 → commit → send_message 回報
    4. 主 Agent 驗證 commit 存在 → wf-state.sh task-done
    5. 下一個 task（全新 Worker，乾淨 Context）
```

**好處**：
- 每個 Task 的 Worker 享有完整的 Context Window 預算（~200k tokens），不受前序任務污染。
- 主 Agent 的 Context 極度輕量（只追蹤進度 + 檔案路徑），大幅降低觸發 Token Budget Gate 的機率。
- 自然支援 `pause_level=autonomous`，因為主 Agent 不需要「展示變更」給使用者看。

**與現有模式的關係**：這正是 `subagent-driven-development` Skill 已經在做的事。改善方向是讓 `gen-dev-workflow` 的 STAGE 2 正式整合 SDD 模式，而非兩套系統各自運作。

**向後相容**：在 `wf-state.sh` JSON 中新增 `execution_mode` 欄位（`inline` | `subagent`），預設 `inline` 保持舊行為。使用者可透過 `wf-state.sh set config.json execution_mode=subagent` 啟用新模式。

---

### 5.3 STAGE 3 對抗式 Challenger 驗證 (Adversarial Challenge Gate) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**，形式為
> 「STAGE 3 多 angle 對抗式審查」（`SKILL.md:747-749`，Workflow 三個適用點之三）。
> 對抗立場已寫進 agent 定義：`.claude/agents/verifier.md:11` —— 「立場是對抗式的——
> 預設實作有問題，盡力證明它錯」。
>
> **與原提案的兩處差異**（皆為刻意調整）：
> 1. **多 lens 平行，而非單一 Challenger 串接**——原提案是 Reviewer PASS 後再跑一個
>    Challenger；實作改為多個 verifier **各帶不同 lens**（correctness / security /
>    回歸風險 / 測試覆蓋 / 過度工程）平行找 bug。理由：對抗式驗證的價值在**視角多樣性**，
>    N 個相同提示的 Challenger 抓到的是同一類問題。
> 2. **verifier 是助手，reviewer 仍是最終判斷者**——不設 `CHALLENGE_PASS` / `CHALLENGE_FAIL`
>    這種獨立閘門，verifier 的 verdict 是輸入，reviewer 收斂後親自寫審查報告
>    （SKILL.md:644 明訂「審查報告 reviewer 親自判斷，不可委派」）。故
>    **`challenge_enabled` 旗標未實作也不需實作**——它是 Workflow 的可選加速層，
>    由主指揮視情況決定是否啟用，不是 state 檔的持久欄位。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
STAGE 3 目前只有單一 Reviewer 進行程式碼審查。Reviewer 的心態是「檢查程式碼是否符合規格」，但這無法發現：
- 規格本身沒考慮到的邊界情況
- 實作正確但架構方向有隱患的設計
- 看起來正常但在特定輸入下會爆炸的邏輯

**teamwork-preview 怎麼做**：
在 Reviewer 之後，額外派發 Challenger（對抗者）。Challenger 的角色定義完全不同：
- Reviewer 問：「這符合規格嗎？」→ 合規性檢查
- Challenger 問：「我怎樣才能讓這段程式碼失敗？」→ 破壞性測試思維

**gen-dev-workflow 可借鏡的做法**：
```
STAGE 3 (改良後):
  Step 1: Reviewer (現有流程，不變)
    → 檢查規格符合度、程式碼品質、測試覆蓋
    → PASS / FAIL
  
  Step 2: Challenger (新增，僅在 Reviewer PASS 後觸發)
    → invoke_subagent(TypeName="research", Model="flash")
    → Prompt: "你是一位對抗式測試專家。以下是剛通過審查的程式碼變更。
       你的唯一任務是找出它的致命缺陷：邊界錯誤、競態條件、
       未處理的例外、效能陷阱、或規格遺漏的場景。
       如果找不到致命缺陷，回覆 CHALLENGE_PASS。"
    → CHALLENGE_PASS → 進入 STAGE 4
    → CHALLENGE_FAIL → 回到 STAGE 2 修正（已有 3→2 轉移路徑）
```

**好處**：用極低成本（一個 `flash` subagent）增加一層獨立的破壞性思維驗證，顯著降低 PR 被退回的機率。

**向後相容**：在 `wf-state.sh` 狀態機中，STAGE 3 的內部子狀態由 SKILL.md 控制，不需修改轉移表。Challenger 是 STAGE 3 內部的選填步驟，可透過 `challenge_enabled=true|false` 控制。

---

### 5.4 動態 Model 分級 (Dynamic Model Tiering) — ✅ 已完成（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：本節此前列為待實施，**實際已落地**且比原提案完整——
> `SKILL.md:584-601` 已有正式的**推論等級表**，`SKILL.md:614` 有各 stage 的等級對照，
> `SKILL.md:619-637` 有 STAGE 2 implementer 內部的逐任務分級與「驗收 model 與實作 model 分離」規則。
>
> **與原提案的三處差異**：
> 1. **等級名而非 model 名**——文件只寫「最強推論 / 標準 / 輕量 / 快便宜」四個**角色等級**，
>    實際 model 別名綁在各 `.claude/agents/*.md` 的 frontmatter。這是刻意的：
>    **換代時只動 agent 檔一行**，不必回頭改流程文件（SKILL.md:584 明述此為降低維護成本的核心）。
>    原提案的 `flash` / `inherit` / `pro` 是 teamwork-preview 的 model 名，Claude 側不適用。
> 2. **effort 與 model 拆成兩個維度**——原提案只有 model 一維；實作額外把 `effort`
>    （`xhigh` / `max` / `high`）從 frontmatter 移出、改為派發時顯式帶入，
>    形成 model × effort 的二維分級。
> 3. **未使用 `model_hint` 欄位名**——plan 文件標的是「複雜度等級」，由 STAGE 2 對照
>    推論等級表換算，語意等價。
>
> ⚠️ **已知風險（SKILL.md:603 記載，未完全排除）**：`effort: 'xhigh'` 在 thinking 未開啟時，
> 於 Opus 4.8 上曾實際遇到 `400 output_config.effort 'xhigh' is not supported`。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
`gen-dev-workflow` 在所有階段、所有任務都使用相同的 Model。但實際上：
- 建立 boilerplate 檔案、跑格式化、簡單重命名 → 殺雞用牛刀
- 跨檔案架構整合、複雜邏輯實作 → 需要最強推理能力
- 程式碼審查 → 中等推理即可

**teamwork-preview 怎麼做**：
根據任務類型動態選擇 Model：Explorer 用 `flash`、Worker 依複雜度選 `flash` / `inherit` / `pro`、Reviewer 用 `flash`。

**gen-dev-workflow 可借鏡的做法**：

在 Plan 文件的每個 Task 中加入 `model_hint` 標註：

```markdown
## Task 3: 建立 WidgetInspectorOverlay UI 元件
- model_hint: pro  # 跨檔案整合，需要架構判斷
- files: lib/src/overlay.dart, lib/src/inspector_panel.dart
- ...

## Task 4: 新增 l10n 翻譯 key
- model_hint: flash  # 機械性插入，無需推理
- files: lib/l10n/app_en.arb, lib/l10n/app_zh.arb
- ...
```

STAGE 2 的主 Agent 讀取 `model_hint` 後，在 `invoke_subagent` 時傳入對應的 `Model` 參數。

| model_hint | 對應 Model | 適用場景 |
|:-----------|:-----------|:---------|
| `flash` | `flash` | 新增翻譯 key、建立空檔案、簡單 copy-paste 式任務 |
| `standard` | `inherit` | 一般功能實作、單檔修改、測試撰寫 |
| `pro` | `pro` | 跨檔案架構決策、複雜演算法、效能優化 |

**好處**：在不犧牲品質的前提下，預估可節省 40~60% 的 Token 成本（大多數 Plan 中有 30~50% 的任務是機械性操作）。

**向後相容**：`model_hint` 是 Plan 文件的選填欄位。未標註時預設 `standard`，完全不影響現有 Plan 格式。

---

### 5.5 結構化跨 Session Handoff 文件 (Structured Handoff Protocol) — ✅ 需求已覆蓋 · ❌ 不採用 `HANDOFF.md` 形式（2026-08-06 實查確認）

> **🔍 實查校正 (2026-08-06)**：全專案**查無 `HANDOFF.md`**，但本節要解決的問題
> **已由另一套機制覆蓋**：`SKILL.md:545-575` 的「context 超標切 session 閉環」。
> 該機制以 **per-branch state 檔 + `interrupted_by=context_budget` + 帶交接筆記的 WIP commit**
> 達成同一目的，且續接時自動辨識、不問使用者「繼續還是開新流程」。
>
> **為何不另建 `HANDOFF.md`（品味判斷）**：原提案的四個區塊，三個在既有 state 檔裡**已經有了**——
>
> | HANDOFF.md 區塊 | 既有覆蓋處 |
> |:---|:---|
> | 狀態快照（stage / mode / completed_tasks） | state JSON 的同名欄位，`wf-state.sh get` 直接讀 |
> | 已完成工作摘要（task → commit） | `completed_tasks` + git log |
> | 檔案路徑索引（state / worktree / spec / plan） | state JSON 的 `spec` / `plan` / `branch` 欄位 |
> | **關鍵決策記錄** | **WIP commit message 的交接筆記**（SKILL.md:561：「做到哪、下一步打算做什麼、為什麼選這個作法」） |
>
> 另開一份 `HANDOFF.md` 等於把同一份狀態寫成兩份，兩份必然漂移——
> 而漂移的交接文件比沒有交接文件更危險（新 session 會信任它）。
> 唯一原本沒有的「關鍵決策記錄」已收進 WIP commit message，
> 理由是**決策與產生它的那次 commit 綁在一起才不會失聯**，比獨立檔案更不容易腐爛。
>
> **結論**：本節**不列入待辦**。若未來 state JSON 的欄位確實不夠用，正確做法是**擴充 state schema**
> （單一事實來源），而非新增第二份文件。

**現況痛點**（以下為 2026-07-31 提案當時的分析，保留作決策紀錄）：
當 Token Budget Gate 觸發（>150k）時，`gen-dev-workflow` 會執行 WIP commit 並「交接給新 Session」。但交接內容是 ad-hoc 的——新 Session 的 Agent 需要從 `wf-state.sh get` 的 JSON、git log、和散落的 spec/plan 檔案中自行拼湊出「目前進度到哪了」。這個拼湊過程本身就消耗大量 Context，且容易遺漏關鍵決策記錄。

**teamwork-preview 怎麼做**：
Orchestrator 維護一份持續更新的 `progress.md`，記錄：已完成的 Milestone、當前進行中的任務、關鍵決策與原因、下一步行動。Self-succession 時，新 Orchestrator 只需讀這一份文件就能完整接手。

**gen-dev-workflow 可借鏡的做法**：

在 Token Budget Gate 觸發時，強制產出一份結構化的 `HANDOFF.md`：

```markdown
# Workflow Handoff — <branch-name>

## 狀態快照
- Stage: 2 (Implementation)
- Mode: sequence
- Completed Tasks: [1, 2, 3] / Total: 7
- pause_level: balanced

## 已完成的工作摘要
- Task 1: 建立 data model (commit: abc1234)
- Task 2: 實作 repository layer (commit: def5678)
- Task 3: 撰寫 unit tests (commit: ghi9012)

## 關鍵決策記錄
- 選用 freezed 而非手寫 fromJson，因為 model 有 10+ 個欄位
- API endpoint 改用 v2 路徑，因為 v1 缺少 pagination 支援

## 下一步行動
- 接續 Task 4: 實作 BLoC state management
- Plan 路徑: docs/plans/2026-07-31-xxx.md
- Spec 路徑: docs/issues/specs/xxx.md

## 檔案路徑索引
- State JSON: .claude/workflow-state/<branch>.json
- Worktree: /path/to/worktree
```

**好處**：
- 新 Session 的 Agent 讀一份文件即可完整接手，不需要花 10k+ tokens 去搜尋、拼湊、推理「目前進度到哪了」。
- 「關鍵決策記錄」防止新 Session 的 Agent 推翻前 Session 已經做過的架構決策。
- 結構化格式讓 `continue` 指令可以自動解析，進一步降低接手成本。

**向後相容**：`HANDOFF.md` 是 SKILL.md 層面的新增指示，不動 `wf-state.sh`。舊流程中 Token Budget Gate 的 checkpoint + WIP commit 行為完全保留，`HANDOFF.md` 是額外的加值。

---

### 5.6 借鏡總結：teamwork-preview vs gen-dev-workflow 改善對照表

> **🔍 實查校正 (2026-08-06)**：本表原記錄的是 2026-07-31 的「現況 vs 建議」。
> 逐項實查 `.claude/skills/gen-dev-workflow/` 後確認 **5 項全數已處理**，
> 下表已改為「提案 → 實際落地形式」對照。原始的痛點分析保留在各節內文。

| 維度 | 2026-07-31 提案 | **實際落地形式（2026-08-06 實查）** | 狀態 |
|:-----|:---------------|:----------------------------------|:---:|
| **STAGE 0a 勘查** | 3 Explorer 平行 + 寫 survey 檔 | Workflow `parallel()` 雙線 `agent()`，`agentType: 'Explore'`，結構化 schema 直接回傳（SKILL.md:722-725） | ✅ |
| **STAGE 2 執行** | 逐 task 序列 spawn Fresh Worker | Workflow `pipeline()` 並行 + `isolation: 'worktree'` 每任務獨立工作區（SKILL.md:739） | ✅ |
| **STAGE 3 驗證** | Reviewer 後串接單一 Challenger | 多 verifier **各帶不同 lens** 平行對抗，reviewer 收斂後親自判斷（SKILL.md:747-749、verifier.md:11） | ✅ |
| **Model 選擇** | `model_hint` → flash/inherit/pro | 推論等級表（4 級），model 綁 agent frontmatter + effort 派發時帶入的**二維**分級（SKILL.md:584-637） | ✅ |
| **跨 Session 交接** | 獨立 `HANDOFF.md` | **改以 state 檔 + WIP commit 交接筆記覆蓋**，不另建文件（避免雙份狀態漂移，見 §5.5） | ✅ 需求已覆蓋 |

> **共通模式**：5 項中有 4 項的落地載體是 **Claude `Workflow` 工具**而非原提案設想的
> bash 腳本或 `invoke_subagent` 迴圈。這是提案後才出現的能力，回頭看反而更貼合需求——
> 並行、結構化回傳、worktree 隔離都是內建的，不必自己造。
> **教訓：架構提案寫的是「要解決什麼」，落地時該重新挑當下最省的載體，不必照抄提案的實作形式。**

> **刻意不借鏡的部分**（Linus 式實用主義判斷）：
> - ❌ **Sentinel 監護層**：gen-dev-workflow 的主 Agent 本身就是 Coordinator，額外加一層 Sentinel 是浪費。
> - ❌ **四重驗收閘門**：Reviewer + Challenger 兩重已足夠。再加雙倍 Reviewer + Auditor 是過度工程，邊際效益趨近零。
> - ❌ **Heartbeat Cron 自我續命**：Token Budget Gate 已經解決了 Session 存活問題，不需要另一套機制。

---

### 結論 (Summary & Next Steps)

本腦力激盪文件完成了三層次的深度分析：

1. **歷史基準修復**（2026-07-17 ~ 2026-07-21）：5 個 Bash Bug + 5 個流程漏洞已全數修復，奠定穩固地基。
2. **開源框架比對與優化提案**（2026-07-30）：借鏡 MetaGPT、AutoGen、SWE-agent、ChatDev，提出 4 項含完整 Bash 實作的架構優化（`pause_level`、`cmd_rollback.sh`、`wf-truncate.sh`、`wf-exec.sh`）。
3. **teamwork-preview 逆向工程啟示**（2026-07-31）：從實測 transcript 還原其多智能體架構，萃取出 5 項可直接移植至 `gen-dev-workflow` 的改善方向（平行勘查、Fresh Worker、對抗式 Challenger、Model 分級、結構化 Handoff）。

上述 9 項優化提案（§3 的 4 項 + §5 的 5 項）構成了 `gen-dev-workflow` 2.0 的完整架構升級藍圖。

---

### 📊 落地現況（2026-08-06 實查於 `.claude/skills/gen-dev-workflow/`）

| 提案 | 狀態 | 實查證據 |
|:-----|:---:|:---------|
| §5.1 平行勘查 | ✅ 已完成 | SKILL.md:722-725 Workflow 雙線 `agent()` |
| §5.2 Fresh Worker | ✅ 已完成 | SKILL.md:739 `pipeline()` + `isolation: 'worktree'` |
| §5.3 對抗式驗證 | ✅ 已完成 | SKILL.md:747-749、`.claude/agents/verifier.md:11` |
| §5.4 Model 分級 | ✅ 已完成 | SKILL.md:584-637 推論等級表 |
| §5.5 Handoff | ✅ 需求已覆蓋 | SKILL.md:545-575 state 檔 + WIP commit 交接（不採 `HANDOFF.md`） |
| §3 提案 1 `pause_level` | ✅ **已完成**（2026-08-06 · `9bce068`） | `wf-state.sh:141` `should_pause()` 單一判定來源；`:172` `apply_sets()` 白名單含 `pause_level` + enum 校驗；`:269`/`:286` 為 `stage-done`/`task-done` 兩個呼叫端；SKILL.md:179 暫停粒度章節、:872 選項語法 |
| **批次佇列**（非原提案，2026-08-06 新增） | ✅ **已完成**（`9bce068`） | `wf-state.sh:349-430` `batch-init`/`batch-get`/`batch-next`/`batch-done`/`batch-fail`/`batch-abort`；獨立 schema + `batch_write` 原子寫入；SKILL.md:328 批次模式章節 |
| **Gap 2.6 獨立入口狀態防護**（2026-08-14 補正） | ✅ **已完成**（2026-08-14 · 方案 A+C） | `SKILL.md:146` 首步硬性化；`.claude/hooks/wf-guard-stage-check.sh` PreToolUse 攔截 responder 派發；`.agents/hooks.json` 與 `.claude/settings.local.json` 掛載；`wf-state.sh:98` 補齊 `4->5` 轉移表 |
| §3 提案 2 `cmd_rollback.sh` | ⬜ **未實作** | 全專案查無此檔；SKILL.md 內 `rollback` / `回滾` 零命中 |
| §3 提案 3 `wf-truncate.sh` | ⬜ **未實作** | `scripts/` 下僅有 `wf-state.sh` |
| §3 提案 4 `wf-exec.sh` | ❌ **不採用**（2026-08-10 定案） | 前提已變：委派改走 MCP 工具呼叫，不經 bash 子進程，沒有 `$?` 可保留，此形狀無對應物。其要解決的「回報不可信」問題改由**驗收紀律**覆蓋（`implementer.md`「回報不等於事實」+ SKILL.md 委派紀律第 3 條）。**前一版的判斷（「agy headless 不可用 ⇒ 委派已死 ⇒ 不必寫轉接層」）方向對、結論錯**——不可用的是傳輸層，不是委派本身；正解是換傳輸層，不是放棄委派 |

**修正結論**：§5 的 5 項（teamwork-preview 借鏡）**全數已處理**，本文件此前仍將其列為
「待實施藍圖」，屬狀態欄漂移。§3 的提案 1（`pause_level`）已於 2026-08-06 落地，
**剩餘待辦為提案 2 `cmd_rollback.sh` 與提案 3 `wf-truncate.sh` 兩支腳本**，提案 4 前提存疑。
§4 的「3 階段實作藍圖」與「4 層驗證協定」是為 §3 那些腳本設計的，僅在動工時適用；
§5 各項已用 Claude `Workflow` 落地，不走該藍圖。

> **📝 §3 提案 1 的落地差異（2026-08-06 · `9bce068`）**：整體採用原設計的三段式
> enum 與安全備援策略，但有三處刻意偏離，記錄供後續參考——
> 1. **判定收斂為單一 `should_pause()` 函式**，而非原提案在 `stage-done` 與 `task-done`
>    內各寫一份 `case`。理由與 features 側 §P7 的 `NetworkEntry.isFailed` 完全同構：
>    同一判定寫兩份，遲早漂移。
> 2. **quick 模式對 `balanced` 明示短路回 `strict`**（原提案未涉及 mode 交互）。
>    quick 不拆任務（無 task 迴圈）、stage 為自由標籤（不匹配 `0b`/`2`/`4`），
>    套 `balanced` 只會落空退化；明示短路讓讀腳本的人不會誤判為 bug。
> 3. **schema 接受 `pause_level == null`**——舊 state 檔無此欄位仍須通過校驗，
>    否則既有流程會在 `validate()` 全數卡死（never break userspace）。
>
> **另新增批次佇列**（非原提案範圍）：原四項提案全是**單一 workflow 內**的基礎腳本，
> 未涵蓋「多個獨立需求各自 worktree/branch/PR 依序執行」的外層編排需求。
> 該能力與 `pause_level` 正交——前者決定跑幾個 workflow，後者決定每個 workflow 停幾次；
> 批次要能順跑，內層仍需 `pause_level=balanced`，故兩者同批實作。
> ⚠️ **已知邊界**：Claude 無法自行清空 context，故批次為「自動接續 + 使用者 `/clear` 換場」
> 而非全自動。真無人值守需走 cron 驅動（每次喚醒即全新 context），未實作。

> **流程教訓**：本文件與 `2026-09-04-features-brainstorm.md` 兩份腦力激盪文件，
> 累計已出現 **7 次「標為待辦、實際已完成」**（features 側：§D6、§P8；
> workflow 側：§5.1~§5.4 四項，以及 **§3(B) 第 4 項 Guide→Sensor**——
> 該項於 `a557dfc`（2026-08-19）落地為 `.claude/hooks/wf-guard-delegate-cwd.sh`，
> 文件卻仍標「四項全部只是提案，未動任何程式碼」，於 **2026-08-23** 實查發現並回寫），
> 以及 **1 次反向漂移**（features 側 §P7 的教訓段落被誤讀為現存問題，已於 2026-08-06 補時間錨註記）。
> **兩個方向的根源相同：狀態敘述沒有綁定時間點。**
>
> 🔴 **第 7 次是最壞的一種**：前 6 次漂移的是**各節內文**，尚有「落地現況」表可對照；
> 這次漂移的是 **§3(B) 那張本身就宣告「任一項落地後應立即回寫本表」的動工順序表**——
> 提醒寫在表裡，卻沒人回來改表。**光靠文件自我提醒防不住漂移，要靠外部實查。**
> 上一次 `pause_level` 完成後立刻回寫的做法是對的，但那依賴當下記得；
> 沒記得的那次（Issue #134）就漂了 4 天。
> 建議每次 release 或每月固定跑一次 `/gen-list-work-item-by-priority` 的實查核對，
> 別讓狀態欄持續漂移——漂移的待辦清單會讓人去做已經做完的事。

---

## 🟣 第三部分：知名開發者的實務工作流比對 (2026-08-15)

> **與第二部分的區別**：§第二部分比的是**學術／開源多 Agent 框架**（MetaGPT、AutoGen、
> SWE-agent、ChatDev）——那些是論文與框架。本部分比的是**具名工程師手工打造、
> 跑在自己真實專案上的工作流**。後者更值得比對，因為它們與 `gen-dev-workflow` 的處境相同：
> 一個人、一個 repo、要真的把 code 出貨，不是刷 benchmark。
>
> **🔍 查證方法**：以下每一項都經 `WebFetch` 實際讀取原始來源確認作者、機制與主張，
> 非僅憑搜尋摘要或記憶。附上的 URL 即為查證所用來源。
>
> ⚠️ **本次研究的已知邊界（誠實標註 · 2026-08-16 更新）**：
>
> **第一輪**（8 項，§2）：原設計為「多線搜尋 → 深讀 → 三重對抗查核」，但**對抗查核階段因 session 額度耗盡未執行**（85 個 agent 中 68 個中止）。WebFetch 查證由主對話**親自補做**，涵蓋 §2 全部 8 項的核心來源。
>
> **第二輪**（13 項，§3.5）：補查剩餘 32 項中的 **Tier 1（4 項，可能修正結論）與 Tier 2（9 項，官方文件與具名個人）**，全數經 WebFetch 查證，其中 Tier 1 另加一輪「專門證偽」複核。**結果：6 項判定 REVISES。**
>
> **第三輪**（19 項，§3.6）：補完最後的 Tier 3（工具與論文）。前兩次嘗試分別因**網路中斷（ENOTFOUND）**與**額度耗盡**失敗，第三次 **19/19 全數成功、零淘汰**。
>
> ✅ **至此 32 項候選全部查證完畢**（8 + 13 + 19 + 跨輪 recheck）。
>
> 📌 **第三輪推翻了第二輪的一個預期**：當時寫「這 19 項多屬工具與論文，修正既有結論的機率低於 Tier 1/2」——**結果仍有 5 項 REVISES**，比例與 Tier 1/2 相當。教訓：**「工具類價值較低」是先驗偏見，不是實測結果。**
>
> ⚠️ **逐項查證抓到 2 筆作者歸屬錯誤**（ASDLC 實為 Ville Takanen 非 Claudio Lassala；Decoupled HITL 實為 Cheng & Cheng 兩人、無 Stanford 隸屬）。若當初直接採信搜尋階段結果，這兩筆會誤植進文件。

### 1. 對照矩陣

| 軸線 | Ralph (Huntley) | ACE-FCA (Horthy) | Harper Reed | Hashimoto | Beck | Böckeler | Superpowers (Vincent) | `gen-dev-workflow` |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **階段拆解** | ❌ 單一 prompt 無限迴圈 | ✅ research→plan→implement | ✅ spec→plan→todo | ✅ 16 個 session 分段 | ✅ 逐 test 推進 | — | ✅ brainstorm→plan→implement | ✅ 0a→0b→1→2→3→4 |
| **狀態持久化** | 檔案（每輪重讀） | plan 檔（狀態壓回檔案） | `todo.md` 打勾跨 session | `spec.md` + `@` 檔案引用 | `plan.md` 未打勾的 test | — | skill 檔 | ✅ JSON state + shell 唯一入口 |
| **程式強制約束** | ❌ 純 prompt | ❌ 純流程紀律 | ❌ 純文件 | ❌ 人工把關 | ❌ system prompt 勸說 | ✅ **Sensors（linter/test）** | ⚠️ skill 文件 | ✅ **轉移表 + 棘輪 exit 1** |
| **context 管理** | ✅ 每輪 reset | ✅ **刻意壓在 40-60%** | 跨 session 續接 | ✅ 分 16 session | — | — | subagent 隔離 | ✅ Token Gate >150k 切 session |
| **平行隔離** | ❌ | — | ❌ | ❌ 序列 | ❌ | — | ✅ 自動建 worktree | ✅ per-worktree state |
| **對抗式審查** | ❌ | ❌ | ❌ | ✅ 人類親審 | ✅ 人類盯場 | ✅ code review agent | ✅ subagent code review | ✅ 驗收 model ≥ 實作 model |
| **回報不可信** | 接受爛結果、`git reset` | — | — | ✅ 「不 ship 我看不懂的 code」 | ✅ **抓 agent 刪測試作弊** | ✅ 確定性 sensor | — | ✅ 主對話親自 `git log` 驗證 |

### 2. 逐項解析

#### 2.1 Ralph / Ralph Wiggum Loop — Geoffrey Huntley

- **來源**：<https://ghuntley.com/ralph/>
- **機制**：`while :; do cat PROMPT.md | claude-code ; done`。一輪一個任務、**每輪全新 context**、每輪餵相同的規格檔。
- **設計原理**：作者自述「**deterministically bad in an undeterministic world**」——LLM 本身不確定，但**迴圈結構**可確定。失敗不是工具問題而是 prompt 調校機會；壞掉就 `git reset --hard` 重來，靠「最終一致性」收斂。
- **佐證（不是可學）**：「每輪 fresh context」與我們 Token Gate 切 session 是**同一個洞察的兩種強度**——他每輪都重置，我們撞到 150k 才重置。Ralph 證明了「context 重置」這件事本身有效，但**我們已有同一機制的精緻版**，不需要往他那個方向走。
- **🔴 為什麼「每輪 fresh context」我們學不了**（此問題被實際提出過，記錄完整推導以免日後重提）：

  fresh context 的收益是真的——消除 context 污染（前一輪的錯誤推理與失敗嘗試不累積）、消除 context 衰減（不會用到 150k 時開始遺忘早期指令）、迴圈輸入完全相同故變異只來自模型本身、無狀態即無狀態 bug。他那句「deterministically bad」的重點正是：**把不確定性集中在模型一處，不讓它散佈在累積的 context 裡。**

  但這些收益的代價，在他的情境付得起、在我們的付不起：

  1. **他用「重跑」換「續接」——我們不能。** Ralph 每輪 fresh 的前提是每輪都能從頭重來，失敗處理就是 `git reset --hard`。我們 STAGE 2 跑到第 5 個任務時 context 爆掉，不可能把前 4 個已 commit、已過驗收的任務丟掉重跑——那不只是浪費，是**破壞已經人類確認的成果**。
  2. **他沒有暫停點，我們有。** fresh context 的代價是「模型不記得剛才跟你談了什麼」。他全程無人類確認環節故無所謂；我們每個 stage 都有暫停點，使用者在 STAGE 0b 確認過的計畫、STAGE 2 逐任務確認過的變更，**每輪清空就得重講**。
  3. **我們已有更精準的等價物。** fresh context 要解決的是 context 污染與衰減，我們的解法不是「不重置」，而是**重置時帶著結構化狀態走**：Token Gate → 寫 state 檔 → WIP commit（帶交接筆記）→ 切 session（context 真的清空）→ 新 session 讀 state 續接。**我們也有 fresh context，只是重置頻率不同、而且不丟進度。**

  **結論：真正該學的是 §2.2 ACE-FCA，不是 Ralph。** 兩者都在講 context 管理但主張不同——Ralph 每輪重置且丟掉重跑（適用無人值守玩具專案），ACE-FCA 維持 40-60% 不讓 context 長大（適用長流程）。我們與 ACE-FCA 的差距是真的（被動剎車 vs 主動巡航），與 Ralph 的差距則是**刻意的設計取捨**。
- **不學**：無狀態機、無暫停點、接受「醒來發現 codebase 壞掉」。對單人玩具專案可行，對要出 PR 的流程是災難。

#### 2.2 ACE-FCA — Dex Horthy (HumanLayer)

- **來源**：<https://github.com/humanlayer/advanced-context-engineering-for-coding-agents>（`ace-fca.md`）
- **機制**：research → plan → implement 三階段，plan 寫成 repo 內的 markdown 檔，實作時**把狀態壓縮回 plan 檔**。
- **設計原理**：兩個主張值得抄——
  1. **context 刻意壓在 40–60%**，不是用滿才處理。「內容是你唯一能影響輸出品質的槓桿」。
  2. **審查槓桿階層**：「一行爛的 *plan* 會導致數百行爛 code；一行爛的 *research* 會導致數千行」——所以**該花力氣審 plan 與 research，不是審 code**。
- **🟢 可學（真正的新東西）**：我們的 Token Gate 是 **150k 才觸發的被動剎車**，ACE-FCA 是**主動維持在 40-60% 的巡航控制**。這解釋了為何長流程後段品質下滑——我們允許 context 長到 150k 才動作，那時 agent 早已在高污染區工作。
- **已有**：階段拆解、plan 檔為真相來源（我們的 STAGE 0a/0b 產物即是）。

#### 2.3 spec.md → prompt_plan.md → todo.md — Harper Reed

- **來源**：<https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/>
- **機制**：三件式文件。對話式 LLM 產 `spec.md` → 推理模型把 spec 拆成 `prompt_plan.md`（一系列給 codegen 的 prompt）→ `todo.md` 作為跨 session 打勾清單。
- **設計原理**：作者明言 `todo.md` 的用途是「**keeping state across sessions**」——這正是我們 state 檔要解決的問題，只是他用 markdown 打勾、我們用 JSON + schema 校驗。
- **已有**：我們的 `completed_tasks` 陣列 + `task-done` 就是強型別版的 `todo.md`。**佐證我們的方向對**，但他的方案沒有校驗，打勾可以隨便亂打。

#### 2.4 16-session 分段 + oracle — Mitchell Hashimoto

- **來源**：<https://mitchellh.com/writing/non-trivial-vibing>（Ghostty 自動更新功能實例）
- **機制**：一個功能拆成 **16 個 session、約 8 小時、$15.98 token**。用「oracle」（唯讀、較慢較貴的模型）先產計畫存成 `spec.md`，再逐 session 實作。穿插「**anti-slop session**」專門清理。
- **設計原理**：兩點——
  1. **「更好組織與文件化的 code 讓未來的 agentic session 表現更好」**：清理不是潔癖，是為後續 session 鋪路。
  2. **「我不 ship 我看不懂的 code」**：理解失敗就直接拒絕 AI 的方案。
- **🟢 可學**：**anti-slop session** 是我們沒有的概念。我們 STAGE 3 審查的是「這次改動對不對」，沒有「為了讓下次 agent 更好做而整理」這種**面向未來的清理**。
- **佐證**：他的「oracle 用更貴模型做計畫」= 我們的「planner 用最強推論」；他的分 16 session = 我們的 Token Gate 切 session。

#### 2.5 Augmented Coding — Kent Beck

- **來源**：<https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes>
- **機制**：把 TDD 紀律寫進 system prompt——「找 `plan.md` 中下一個未標記的 test、實作該 test、**只寫剛好讓它通過的 code**」。全程盯著中間結果，隨時準備喊停。
- **設計原理**：與 vibe coding 的分野是「**在 vibe coding 你不在乎 code，只在乎系統行為**」；augmented coding 則要求 code 品質、複雜度、測試覆蓋率都達到手寫標準。
- **🔴 最有價值的一條**：他列出 agent 失控的三個警訊，其中第三個是——
  > 「任何 genie 在**作弊**的跡象，例如**停用或刪除測試**」
  >
  這是我們「委派紀律第 3 條：回報不等於事實」的**獨立佐證**。Beck 是 TDD 發明人，他親自踩到「agent 為了讓測試過而刪測試」這個坑。我們要求主對話親自驗證，方向完全正確。
- **已有**：TDD 紀律（`test-driven-development` skill）、驗收與實作分離。

#### 2.6 Harness Engineering：Guides vs Sensors — Birgitta Böckeler (Thoughtworks)

- **來源**：<https://martinfowler.com/articles/harness-engineering.html>
- **機制**：提出 **`Agent = Model + Harness`**，並把 harness 的控制項二分——
  - **Guides（前饋控制）**：在 agent 動手**之前**引導。如 coding conventions 文件、bootstrap 指令。
  - **Sensors（回饋控制）**：在 agent 動手**之後**偵測並自我修正。如 linter、測試、code review agent。
- **設計原理**：她進一步區分**計算式**（確定性、毫秒級、**結果可靠**）與**推論式**（語意、慢、機率性）控制。關鍵論述：計算式 sensor 因為可靠，所以能在**每次變更**都跑；機率性的 AI sensor 做不到這點。
- **🟢 這給了我們一套精確的詞彙**：本文件反覆論證的「**約束寫在 prompt 裡 = 沒有強制力**」（Gap 2.6、委派 cwd 弱點），用她的框架講就是——
  > **我們一直在用 Guide 解決該用 Sensor 解決的問題。**
  >
  `wf-state.sh` 的 `exit 1`、hook 的 `PreToolUse` 攔截，都是**計算式 Sensor**；SKILL.md 的文字規範是 **Guide**。Gap 2.6 的教訓（「守衛需要被呼叫才生效」）本質是：**Guide 可以被忽略，Sensor 不行**。
- **可學**：委派 cwd 約束目前是 Guide（prompt 裡的道德勸說），該升級成 Sensor（hook 攔截或委派後自動 `git status` 驗證）。這與文件既有結論一致，但 Böckeler 的框架讓「為什麼非做不可」講得更清楚。
  - **✅ 2026-08-21 已落地**（issue #134 / PR #135）：`wf-guard-delegate-cwd.sh` 同時實作括號內的**兩種**手段——hook 攔截（`pre`，阻擋派發者失誤）與委派後 `git status` 驗證（`post`，偵測子進程失誤）。兩者交集為空故併用。實作過程也修正了 Böckeler 框架的一處套用偏差：`pre` 端驗證的是「那段 Guide 有沒有被寫進 prompt」，本身仍是 **Guide 的自動化檢查**而非真 Sensor；唯有 `post` 端看檔案系統客觀事實的才是真 Sensor。

#### 2.7 Superpowers — Jesse Vincent

- **來源**：<https://blog.fsck.com/2025/10/09/superpowers/> ｜ <https://github.com/obra/superpowers>
- **機制**：Claude Code 的 skill plugin 系統。brainstorm → plan → implement 三階段；**自動建 git worktree** 做平行隔離；實作走 RED/GREEN TDD；可「逐個 task 派給 subagent 實作後再逐個 code review」。
- **設計原理**：核心強制語句是「**If you have a skill to do something, you *must* use it**」——用 skill 的存在本身當作行為約束。
- **⚠️ 特別說明**：**本 session 就載入了 superpowers**（見系統提示的 `using-superpowers`）。所以這不是「別人的做法」，而是我們**已在共用的基礎設施**。它與 `gen-dev-workflow` 的關係是互補：superpowers 管「流程紀律與 skill 選用」，`gen-dev-workflow` 管「六階段編排與狀態機」。
- **佐證**：worktree 平行隔離、subagent 逐任務實作 + code review、TDD——三項我們都有，且是各自獨立收斂到同一答案。

#### 2.8 🔴 反方立場：Just Talk To It — Peter Steinberger

- **來源**：<https://steipete.me/posts/just-talk-to-it>
- **主張**：**明確反對**本文件推崇的一切——反對繁複規劃文件、反對 subagent 範式（他用「分開的視窗」取得「完整的控制與可見度」）、反對冗長的 persona 規則檔（「跟模型說『你是專精於生產級 LLM 應用的 AI 工程師』不會改變任何事」）。
- **理由**：精簡 prompt 下「codex 反而更小心、讀更多檔案」；繁複的 scaffolding 造成 **context 浪費**與認知負擔，效益不成比例。
- **為什麼要收錄**：**一份只收錄同意自己的證據的文件沒有價值。** Steinberger 的批評直指 `gen-dev-workflow` 最脆弱的地方——6 個 stage、7 個 agent 角色、一份 1000 行的 SKILL.md，這些 ceremony 真的都在付出等值的回報嗎？
- **本專案的回應（Linus 式）**：他的批評對**探索性、單人、小改動**成立——這正是我們有 **quick 模式**（單暫停點、不建 worktree）的原因。但他的方案無法回答：**context 撞 150k 怎麼辦？** 他沒有狀態持久化，session 一斷進度就沒了。我們的 state 檔不是 ceremony，是**為了能中斷續接**而付的必要代價。**兩者的分野不是「誰對」，而是「任務有多長」**——短任務他對，長任務我們對。這也是為什麼 `pause_level` 與 quick 模式必須存在：**讓同一套流程能退化成他那種輕量模式**。

### 3. 三分類結論

#### (A) 已經有的——別人也這樣做，佐證設計正確，**不是待辦**

| 我們的機制 | 誰獨立收斂到同一答案 |
|:---|:---|
| 階段拆解 + plan 檔為真相來源 | Horthy、Harper Reed、Hashimoto、Vincent、Beck |
| 跨 session 狀態持久化 | Harper Reed（`todo.md`）、Hashimoto（`spec.md`） |
| context 用盡切 session | Huntley（每輪 reset）、Hashimoto（分 16 session） |
| git worktree 平行隔離 | Vincent (Superpowers) |
| 驗收與實作分離、不讓寫 code 的 model 自審 | Böckeler（sensor）、Vincent（subagent review） |
| 「回報不等於事實」須外部驗證 | **Beck（親自抓到 agent 刪測試作弊）**、Hashimoto |
| 用程式碼而非文字強制 | **Böckeler（Sensors 必須是計算式才可靠）** |

> 七項全數有獨立佐證。這說明 `gen-dev-workflow` 的骨架不是閉門造車——
> 但也說明**這些不是我們的獨創**，寫文件時不該當成賣點。

#### (B) 真正可學——別人有、我們沒有

> **⚠️ 注意項數**：本類共 **4 項**，其中 **ACE-FCA 貢獻兩項**（第 1 與第 3）。
> 曾有一次盤點誤以「每個章節各一項」計數而漏掉第 3 項——**逐項解析的章節數 ≠ 可學項目數**。

1. **🟢 context 主動巡航（ACE-FCA）**｜effort: 低｜價值: **高**

   - **他們怎麼做**：context 刻意壓在 **40–60%**；「context 視窗的內容是你唯一能影響輸出品質的槓桿」。
   - **我們現況**：Token Gate 是**被動剎車**——`<60k` 正常 ／ `60–100k` 提示精簡 ／ `100–150k` 強制走 MCP 委派 ／ `>150k` 才強制 checkpoint 切 session。
   - **🔴 差距**：我們允許 context 一路長到 150k 才動作。**問題是 agent 在 100k–150k 這段已經在高污染區工作了**——那些輸出照樣被 commit、照樣進 PR。等到 150k 才切 session，壞掉的產出早就落地。
   - **附帶價值**：這替一個既有現象提供了機制層面的解釋——**長流程後段品質下滑**。此前只能歸因於「後面的任務比較難」。
   - **判斷：值得做。** 本次研究**唯一的高價值新洞察**。不需新腳本，改 SKILL.md Token Gate 表格的閾值與行為即可。

2. **🟡 anti-slop session（Hashimoto）**｜effort: 低｜價值: 中

   - **他們怎麼做**：16 個 session 中穿插專門的清理 session，理由是「更好組織與文件化的 code 讓未來的 agentic session 表現更好」。
   - **我們現況**：STAGE 3 審查的是「**這次改動對不對**」——正確性、規格符合度、code quality。
   - **🔴 差距**：缺少**面向未來**的清理。兩者問的不是同一個問題——STAGE 3 問「這段 code 有沒有錯」，anti-slop 問「**這段 code 會不會讓下一個 agent 讀錯**」。
   - **判斷：條件性值得。** 對長期維護的 repo 有價值，對一次性 PR 是純成本。建議先當作 `pause_level=strict` 下的可選步驟，不強制。

3. **🟡 審查槓桿階層（ACE-FCA）**｜effort: **極低**｜價值: 中

   - **他們怎麼做**：「一行爛的 **plan** 會導致數百行爛 code；一行爛的 **research** 會讓你收穫數千行爛 code」——所以該花力氣審 plan 與 research，不是審 code。這是對傳統 code review 優先序的反轉。
   - **我們現況**：STAGE 0b 有暫停點，使用者會看到計畫。
   - **🔴 差距**：**沒有明說「這裡才是最該仔細看的地方」**。實務上使用者可能在 0b 隨手按過，卻在 STAGE 2 逐任務仔細看 diff——**槓桿完全用反了**。0b 看漏一行，後面幾百行都建在錯的基礎上。
   - **判斷：值得做，投報率最高。** 就是在 STAGE 0b 暫停點加一句提示文字。

4. **🟢 把 Guide 升級成 Sensor（Böckeler）**｜effort: 中｜價值: **高**

   - **他們的框架**：`Agent = Model + Harness`。**Guide**（前饋，動手前引導）**可以被忽略**；**Sensor**（回饋，動手後偵測）才是確定性、無法繞過的。
   - **我們現況**：委派 cwd 約束寫成 prompt 裡的一段文字（「🔴 邊界：不得存取或修改此目錄以外的任何檔案」）。
   - **🔴 差距**：那段文字**沒有任何強制力**，是寫給另一個 LLM 看的道德勸說——用 Böckeler 的框架講，**這是 Guide，但它要達成的效果需要 Sensor**。MCP 呼叫無法指定 cwd，子進程若在主 repo 而非 worktree 動手，`wf-state.sh` 的所有 guard 都不會有反應：**狀態機管的是 state JSON 的合法性，管不到檔案寫在哪顆磁碟位置上。** 目前的緩解（委派紀律第 3 條事後跑 `git status`）屬**偵測**不屬**預防**。
   - **判斷：值得做。** 這**不是新發現**——§「同構的第二個弱點」早已記錄且已判定正解是 hook 攔截。Böckeler 的貢獻是給了精確詞彙讓理由更硬。**Gap 2.6 已用 hook 成功解掉同型問題，有現成範式可抄。**

##### 🔴 建議動工順序（2026-08-16 決議）

| 順位 | 項目 | effort | 價值 | 理由 |
|:---:|:---|:---:|:---:|:---|
| 1 | **§3 審查槓桿階層** | 極低 | 中 | 投報率最高，改一段提示文字 |
| 2 | **§1 context 主動巡航** | 低 | 高 | 唯一的高價值新洞察；與順位 1 同屬 SKILL.md 改動，可同批做 |
| ~~3~~ | ~~**§4 Guide→Sensor**~~ ✅ **已於 2026-08-19 完成**（`a557dfc` / Issue #134） | 中 | 高 | 需寫 hook，但 Gap 2.6 有成功範式——實際確如預估，抄 Gap 2.6 的 `exit 2` 範式落地 |
| 4 | **§2 anti-slop** | 低 | 中 | 條件性，設成可選即可 |

> **排序理由**：前兩項都只動 SKILL.md（文字與閾值），可合併為一次改動；第 3 項要寫 hook 與掛載，成本跳一級但價值高；第 4 項價值條件性，排最後。
>
> ⚠️ **狀態標註（2026-08-23 實查更新）**：四項中 **§4 Guide→Sensor 已完成**
> （`.claude/hooks/wf-guard-delegate-cwd.sh`，390 行，Issue #134，`a557dfc` → `36a5996` → `3411455`），
> 其餘三項（審查槓桿階層、context 主動巡航、anti-slop）**仍是提案，未動程式碼**。
> 原記「四項全部只是提案」屬狀態欄漂移——這是本文件累計**第 7 次**「標為待辦、實際已完成」。
> 任一項落地後**應立即回寫本表**，不要等下次盤點。
>
> 🔴 **2026-08-16 第二輪查證後，本順序已被推翻**——見下方修訂表。

##### 🔴 修訂後的動工順序（2026-08-16 第二輪查證後）

第二輪查出的 6 項 REVISES 中，有數項**比原本四項更緊急**，因為它們是「**既有機制實際上沒生效**」而非「可以更好」：

| 順位 | 項目 | 類型 | effort | 理由 |
|:---:|:---|:---|:---:|:---|
| ~~**0**~~ | ~~**把 hook 的 `sys.exit(1)` 改成 `sys.exit(2)`**（**BUG-1**）~~ ✅ **已於 2026-08-17 完成** | 🔴 **修 bug** | 極低 | `.claude/hooks/wf-guard-stage-check.sh:111,126` 原用 exit 1，官方明載**非 blocking、動作照跑**。已改為 `exit 2` 並以四情境實測驗證（見文件開頭 BUG-1） |
| **1** | **驗收 fresh session 衛生**（R2） | 🟢 新可學 | 極低 | 只餵 spec+測試+diff、修正後另起新 session。不需第二家廠牌即可吃到多數獨立性收益 |
| **2** | **改寫機制 6 的理由**（R1） | 🔴 修正文件 | 極低 | 規則不動，理由從「能力不足」改為「同分佈熟悉度」。歪理由會導出錯誤簡化 |
| **3** | 審查槓桿階層（原順位 1） | 🟢 新可學 | 極低 | 不變 |
| **4** | context 主動巡航（原順位 2） | 🟢 新可學 | 低 | 不變 |
| **5** | **改用 `SubagentStart` + 檢查 exit code**（R3/R4） | 🔴 修正實作 | 低 | `exit 1` 掛成 hook 無效；`SubagentStart` 可依 agent type 過濾，比手刻 payload 解析更穩 |
| ~~**6**~~ | ~~Guide→Sensor：委派 cwd（原順位 3）~~ ✅ **已於 2026-08-19 完成** | 🟢 新可學 | 中 | `wf-guard-delegate-cwd.sh`：pre 端檢查派發 prompt 是否含目標 worktree 絕對路徑，缺失/不符即 `exit 2` 阻擋；post 端以 git status 差集偵測目標 worktree 以外的寫入與新增 commit（只告警不阻斷）。⚠️ **R5 的擴大範圍未做**——偵測建立在 git status 上，只涵蓋主 repo 與已知 worktree，寫入非 git 位置仍偵測不到（該檔檔頭已載明屬另案）。該另案即 §W2，已於 2026-08-30 實查重新定性為 ⏸ 降級待命（Issue #152） |
| **7** | anti-slop（原順位 4） | 🟡 條件性 | 低 | 不變 |

> **為什麼順序變了**：原本四項全是「錦上添花」；第二輪查出的 R7 是**既有防護失效**、R1/R3 是**理由或實作錯誤**。
> **修 bug 與修錯誤前提，永遠排在優化之前。**

##### 第三輪新增的可落地項（2026-08-16 · §3.6）

不重排上表，另列於此——這些都是**加欄位／加校驗**，與 `wf-state.sh` 既有語彙相同，不需新架構：

| 項目 | 來源 | effort | 價值 | 一句話 |
|:---|:---|:---:|:---:|:---|
| **`confirmed_by: human\|auto`** | R11(c) | 極低 | 中 | state 檔目前分不出「人確認」與「autonomous 自動放行」 |
| **迴圈偵測**（`issues_hash` 或修復次數上限 3） | R12(a) | 低 | **高** | `3→2→3` 打轉目前只能靠人察覺，純機械可判 |
| **三值裁決 `PASS/CONCERNS/FAIL`** | R8 | 低 | 中 | 二值制下「可過但留案」只能假裝 PASS 或卡死 |
| **退回邊帶 `--reason` 寫入 state** | R8 | 低 | 中 | 退回應是具名的一等公民，且要求產出「更新後的 plan」 |
| **Falsifiable claims（封閉集合）** | R11(a) | 中 | **高** | 子 agent 只能說可機械驗證的話，取代散文回報 |
| **委派 dev log（append-only）** | R9 | 中 | **高** | 稽核系統側錄的軌跡，而非 agent 自述 |
| **worktree port 配置** | R12(b) | 低 | 中 | 只隔離了 state 檔，`flutter run` 仍會撞 port |

> 🔴 **R11 三項（claims / receipts / confirmed_by）建議合併為一次改動**——
> 它們都是「把驗證從人治變成 state 檔上的必要欄位」，拆開做會改三次 schema。

#### (C) 刻意不學——別人有但對本專案是過度工程或方向錯誤

| 不學什麼 | 誰在做 | 理由 |
|:---|:---|:---|
| **無限迴圈直到收斂** | Ralph (Huntley) | 「醒來發現 codebase 壞掉、`git reset --hard` 重來」對要出 PR 的流程不可接受。我們的退回路徑（3→2）是**有界重試**，不是無限迴圈。 |
| **每輪 fresh context（重置即丟進度）** | Ralph (Huntley) | 收益（消除 context 污染與衰減）是真的，但代價是「每輪從頭重來」。我們有暫停點與已確認的成果，丟不起。**我們已有精緻版**：重置時帶結構化 state 走，context 一樣清空但進度不丟。完整推導見 §2.1。 |
| **完全放棄結構化流程** | Steinberger | 他的批評對短任務成立，但無法回答「context 撞牆怎麼辦」。我們用 **quick 模式**覆蓋他的使用情境，不需要把整套流程拆掉。 |
| **把 spec 拆成一系列預生成 prompt** | Harper Reed (`prompt_plan.md`) | 預先把所有 prompt 寫死，等於放棄「依前一步結果調整下一步」的能力。我們的 task 陣列保留了這個彈性。 |

### 3.5 🔴 第二輪查證：修正既有結論（2026-08-16）

> **背景**：第一輪研究因額度耗盡，有 32 項候選未查證。第二輪補查了其中 **13 項**（Tier 1 可能修正結論者 4 項 + Tier 2 官方文件與具名個人 9 項），**剩餘 19 項工具／論文仍未查證**（見文末邊界說明）。
>
> 結果比預期嚴重：**6 項判定為 REVISES（修正既有結論）**，而非單純佐證。以下逐項記錄。

#### R1. 🔴 機制 6 的**理由是錯的**（兩份獨立來源）

**來源**：
- Wataoka, Takahashi, Ri《Self-Preference Bias in LLM-as-a-Judge》<https://arxiv.org/abs/2410.21819>
- Daniel Vaughan《Cross-Model Adversarial Review》<https://codex.danielvaughan.com/2026/03/28/cross-model-adversarial-review/>

**我們現在的理由**：「便宜 model 能力不足以審自己，所以驗收 model 要 ≥ 實作 model」——把自審失敗歸因於**能力位階**。

**🔴 這個歸因沒有證據支持。** arXiv 論文的關鍵實驗設計正好切斷這條因果，原文逐字：

> 「LLMs assign significantly higher evaluations to outputs with lower perplexity than human evaluators, **regardless of whether the outputs were self-generated**. This suggests that the essence of the bias lies in perplexity and that the self-preference bias exists because **LLMs prefer texts more familiar to them**.」

偏誤在**非自己生成**的輸出上一樣出現，只要該輸出 perplexity 低。**自變數是「文本相對 judge 的熟悉度」，不是「judge 有多強」。** Vaughan 從實務端得到同一結論：

> 「use models from **different training distributions**. A Claude-reviewed Codex PR is more reliable than a Codex-reviewed Codex PR — **not because Claude is 'better'**, but because it was trained on different data with different biases.」
>
> 「The same model that rationalised a design shortcut during implementation **will rationalise it again during review**. This is not a limitation that better prompting can fix. It requires a structural solution.」

**對我們的衝擊**：現行「opus 審 sonnet」**仍在同一訓練家族內**。sonnet 實作時合理化的設計捷徑，opus 因共享訓練分佈與先驗，仍傾向視為「標準做法」而放過。**我們以為拉高位階就解決了自審偏誤，這個結論站不住。**

**⚠️ 但要避免過度修正**（兩份來源都沒說能力位階無用）：
- 弱 critic 仍會漏掉真實 violation（與家族無關）。能力是**必要但不充分**。
- **正確做法是改寫理由，不是刪掉位階規則。**
- 建議改寫為：「驗收 model ≥ 實作 model」保留，理由改為「**能力位階是必要但不充分；自審偏誤的根因是同分佈熟悉度，需要跨分佈、或至少跨 context 的結構性隔離**」。

**證據強度誠實標註**：arXiv 論文有實驗數據；Vaughan 那篇是個人 blog 且夾帶書籍推廣，查證明確回報「**No empirical data or experiments presented — this is pattern documentation, not research**」。「跨分佈優於同家族」無量化對照。

> **📌 查證誤差一則**（記錄以免日後誤引）：先前流程中出現的逐字片語「architecturally incapable of neutrality」**無法在原文查證到**，疑為概括而非原文用字。引用時請改用上方已逐字確認的句子。另 Builder model 名稱應為 `Codex CLI / codex-spark / gpt-5.4`。

#### R2. 🟢 零成本可落地：驗收的 session 衛生（同軸線，不需第二家廠牌）

跨廠牌成本高（我們未必有第二家），但 Vaughan 與 Anthropic 官方 best-practices 都指出**另一個獨立機制，成本近乎為零**：

- **Critic 必須在無 build 階段歷史的 fresh session 執行**，只餵 spec + 測試 + diff
- **修正後重新驗收必須另起新 session**，禁止沿用同一 session

官方 best-practices（<https://code.claude.com/docs/en/best-practices>）的理由更根本——獨立性來自**推理過程的可見性**，reviewer「sees only the diff and the criteria you give it, **not the reasoning that produced the change**」。

**推論**：即使實作與驗收用同一顆 model，只要驗收跑在 fresh context 且只看 diff + 準則，**就已取得多數獨立性收益**；反之，用更強的 model 卻把整段實作對話餵給它，偏誤依然存在。**我們的規則對了但理由歪了，而歪掉的理由會導出錯誤的簡化**（例如「同 model 就不必隔離 context」）。

#### R3. 🔴 機制 1 的 `exit 1` 若掛成 hook 會**完全失效**

**來源**：Claude Code Hooks 官方文件 <https://code.claude.com/docs/en/hooks>

`wf-state.sh` 非法轉移用 `exit 1`。官方明載**只有 `exit 2` 是 blocking**；「Any other exit code doesn't block on its own for most hook events」——exit 1 配非 JSON stdout 會被當成 **non-blocking error，動作照跑**，只在 transcript 印一行錯誤。

**這推翻了「exit 1 = 拒絕」的假設。** 目前 `wf-state.sh` 是被當一般 CLI 呼叫、由 skill prompt 自行判讀退出碼——**那是機率性的**，模型可以無視 exit code 繼續走。這正是 hook 要解決的問題本身。

**另兩處修正**：
- **「exit 2 絕對阻擋」的表述要收窄**：`PermissionRequest` 事件「Exit code 2 isn't honored」，須改用 `decision` 物件；`PermissionDenied`、`Notification` 等事件的 exit code 亦被忽略。正確表述是「exit 2 **在可阻擋事件清單上**不可被 JSON 覆寫，清單外完全無效」。
- **多 hook 不會短路**：所有 matching hook 平行跑完才合併，**deny 不會阻止 sibling hook 的副作用**。原文直接警告「Don't rely on one hook's deny to suppress side effects in another hook」。

#### R4. 🟢 我們沒用到的 hook 事件（機制 2、7、8 的現成升級路徑）

gdw 目前只用 `PreToolUse`。官方尚有：

| 事件 | exit 2 的效果 | 對應我們的缺口 |
|:---|:---|:---|
| `Stop` | 阻止 Claude 停止，繼續對話 | 棘輪只防「未確認往前衝」，**沒防「stage 中途擅自收工」** |
| `SubagentStart` | 依 **agent type** 過濾攔截 | 比在 PreToolUse 手刻 Task payload 解析更短、更不易失效 |
| `TaskCompleted` | 阻止任務被標記完成 | 機制 8「回報不等於事實」的**事前阻擋**版（現行是事後 `git log` 偵測） |
| `TeammateIdle` | 把要偷懶的 agent 叫回去 | — |

**⚠️ Stop hook 的逃生閥**：官方明載 Stop hook **連擋 8 次即被強制覆寫**，且須自行處理 `stop_hook_active` 否則無限迴圈。這反向驗證了我們走 shell 狀態機 + 檔案旗標的選型（天然免疫），但也說明**確定性 gate 必須有逃生閥**。

#### R5. 🔴 機制 4：我們的 worktree 隔離**不是可執行的斷言**

**來源**：Claude Code worktree 官方文件 <https://code.claude.com/docs/en/worktrees>

**我們現在**：STAGE 1 起每個 workflow 一個 worktree、state 檔存各自 worktree——**這只是把檔案分開放**。git worktree 本身對 `git -C ../main`、`cd ../main && ...`、`GIT_WORK_TREE=` **毫無防禦**。

**官方作法是執行期攔截**，四道檢查且 **fail-closed**：檔案編輯、指令工作目錄、git 重導向、**指令形狀**（無法靜態驗證的 brace expansion／unquoted heredoc 即使不含 git 也一律拒絕，且 "You can't turn this check off"）。隔離**自動繼承**到所有 subagent 與背景 session。

**對我們的衝擊**：任何 agent 只要 `cd` 出去就能踩到別的 workflow 的 state 檔——**這正是 `wf-state.sh` 的原子寫入與 schema 校驗擋不到的攻擊面**：它保護單一檔案的完整性，不保護「你根本不該碰這個檔案」。

**⚠️ 一個反直覺的事實**：worktree **並非全隔離**——`.git`、project-scope plugins、permission 核准（寫回主 checkout 的 `.claude/settings.local.json`）三者是**共享**的。

#### R6. 機制 7 的定位該升格

gdw 把 PreToolUse hook 當成 Gap 2.6 的**點狀補丁**（擋一個已知的錯誤行為）。官方在同一位置做的是**面狀的不變量強制**（定義 session 級別的不變量，其餘皆拒）。

**差別在於**：前者要**窮舉壞行為**，後者只要**定義好行為的邊界**。這是設計層級的差異——值得把機制 7 從 workaround 升格為機制骨幹。

#### 🔴 R7. Gap 2.6 的 hook 用了**無效的 exit code**（2026-08-16 修訂版）

> **⚠️ 本節初版結論有誤，已於同日更正。** 初版寫「hook 在本 repo 不存在、Gap 2.6 防護失效」——
> 那是**只查了當前分支**得出的錯誤結論。完整查證後的事實見下。

**事實澄清**：`wf-guard-stage-check.sh` **存在且已 commit**（`56efe3b` 新增、`cf2d784`、`14236b2` 修正）。

```
main 分支                      → HAS（檔案存在）
docs/202607/update-brainstorm  → MISSING（本 docs 分支從 c1cd3d3 分出，晚於 hook commit 的分支點之前）
```

**先前「檔案不存在」的觀察是真的，但推論錯了**——不是「從未落地」，而是**當前分支沒有**。Gap 2.6 在 `main` 上正常存在。

**🔴 但實查原始碼後發現一個真實缺陷**，且正是 R3 指出的問題：

```python
# .claude/hooks/wf-guard-stage-check.sh（main 分支）
sys.exit(1)   # 第 111 行：stage 未推進時的阻擋路徑
sys.exit(1)   # 第 126 行：同上
```

依官方 hooks 文件，**`exit 1` 不是 blocking**——「Any other exit code doesn't block on its own for most hook events」，會被當成 non-blocking error，**動作照跑**，只在 transcript 印一行錯誤。要真正阻擋 `PreToolUse` 必須是 **`exit 2`**，或輸出 `permissionDecision: "deny"` 的 JSON。

**結論**：Gap 2.6 的 hook **有被呼叫、也有偵測到違規、但攔不住**。§4 Gap 2.6 方案 C 寫的「**阻擋該次呼叫**」與其「執行者是 harness 而非 LLM，這是唯一想繞也繞不過的層級」——**設計意圖正確，但實作沒有達成**：exit 1 的實際效果是印一行錯誤然後放行。

**這是目前查到唯一命中真實程式碼的缺陷**，修法極小：把兩處 `sys.exit(1)` 改為 `sys.exit(2)`，並驗證 stderr 訊息仍會回饋給模型。

> 📌 **已登記**：本缺陷已列為文件開頭的 **BUG-1**，狀態 ✅ 已修（2026-08-17）。
> 該區塊只收「已實查確認、命中真實程式碼」的缺陷，與提案類項目分開管理。

> 📌 **雙重教訓**：
> 1. **實查證據必須綁定「在哪個分支／工作區查的」**——同一個 `ls` 在不同分支給出相反答案。
> 2. **「有 hook」不等於「擋得住」**——這正是本文件反覆強調的 Guide vs Sensor：
>    寫了 hook 但用錯 exit code，它就退化成一個只會印錯誤訊息的 Guide。

### 3.6 第三輪查證：32 項全數完成（2026-08-16）

> **本輪補完最後 19 項**（Tier 3 工具與論文）。結果：**19/19 全數查證成功、零淘汰**，
> 其中 **5 項 REVISES、5 項 NEW_LEARNABLE、9 項 CORROBORATES**。
> **至此第一輪 32 項候選全部查證完畢**（8 + 13 + 19 = 40 筆，含跨輪重複與 recheck）。
>
> ⚠️ **兩處作者歸屬需更正**（見下方各項標註）——這正是逐項查證的價值，搜尋階段的歸屬有兩筆是錯的。

#### R8. 🔴 退回路徑該是「一等公民」，三值裁決優於二值（BMAD-METHOD）

**來源**：<https://docs.bmad-method.org/reference/workflow-map/>（BMad Code, LLC）

**兩個我們轉移表缺的東西**：

1. **退回是具名的一條邊**：`bmad-correct-course` 是明確入口，輸入是 mid-sprint 重大變更，**輸出必須是「更新後的 plan」**才能轉移。我們的 `3→2` 退回雖在轉移表上，但實務上驗收失敗常靠人手動改 state 或重跑——**機制 1 的保證在最需要時被繞過**。
2. **三值裁決 `PASS / CONCERNS / FAIL`**：我們機制 2 是布林（`awaiting_confirmation`）、機制 6 驗收也是通過／不通過。`CONCERNS` 多出的語意是「**可前進但留下未結案項**」——二值制下這級問題只能假裝 PASS（問題消失）或判 FAIL（流程停擺）。

**🔴 但它同時強力反向佐證我們**：BMM 的狀態機是 **markdown 指令驅動、非程式強制**。查證找到兩個實證失敗：Issue #1015（code-review 標 story done 卻沒同步 `sprint-status.yaml`，修法只是在指令加一句話）、Issue #1930（correct-course 改寫已完成的 story）。

> **要學的是它的拓樸（退回邊、三值裁決），絕不是它的執行方式（把狀態機寫在 markdown 裡）。**

#### R9. 🔴 稽核對象該是「系統側錄的軌跡」，不是 agent 自述（Container Use）

**來源**：<https://github.com/dagger/container-use>（Dagger）

官方措辭精準：記錄的是「complete command history and logs of what agents **actually did, not just what they claim**」。

**與機制 8 的層級差異**：

| | gdw 機制 8 | Container Use |
|:---|:---|:---|
| 形式 | **紀律**（skill 文字要求主對話親自 `git log`） | **基礎設施**（runtime 在容器邊界自動側錄） |
| 驗證對象 | 結果狀態（commit 有沒有、檔案改了沒） | **過程**（跑了什麼指令、試了什麼、失敗了什麼） |
| 可靠度 | 靠模型記得遵守 | 想不記錄也做不到 |

**這是「不可繞過」對上「應該遵守」的差別**——Linus 意義上的好品味：把需要靠自律的特殊情況，改成結構上不存在的情況。

**最小改法不是引入 Dagger**（容器隔離對單人 Flutter package 是過度工程），而是：**子 agent 的 bash 執行記錄自動落成 append-only dev log 存在該 worktree，驗收時讀那份檔而非讀回報文字**。我們的 worktree 已經是現成的掛載點——**基礎設施已備，只差用途**。

#### R10. 🔴 同 session 自審才是根因，不是模型太便宜（ASDLC）

**來源**：<https://asdlc.io/patterns/adversarial-code-review/>
**⚠️ 作者更正**：實為 **Ville Takanen**（`github.com/villetakanen/asdlc-io`），**非**搜尋階段標示的 Claudio Lassala。因歸屬有誤，本項判定為 `PLAUSIBLE` 而非 `CONFIRMED`。

原文核心句：「If the same computational session writes and reviews code, the 'review' provides **minimal independent validation**」。解法是 **Phase 2 Context Swap**——關掉當前 session、開新 session，只餵 Spec + diff，**不餵 Builder 的推理過程**。

**這與 R1／R2 匯流成同一結論**（第三份獨立來源）：即使 model 等級足夠，**同 session 自審仍會 echo-chamber**。

**另兩項可直接吸收**：
- **Moderator 的結構性職責分離**：parallel critics 為 **read-only**，唯一有 write 權限的是 Moderator。比純 fan-out 多一層去重與 alert fatigue 防護。
- 🔴 **「LLMs are statistically predisposed to underweight negation」**——以 `DO NOT` 表達的約束是最弱環節。**這對我們的 prompt 措辭有直接影響**：約束該寫成正向斷言 + 機械檢查（`wf-state.sh` 的 exit code 正是正解），而非靠 prompt 裡的禁止句。

#### R11. 🟢 把「驗證」從人治升級為資料結構（三份來源匯流）

這三項指向同一個可落地的改法，且**完全貼合我們既有形狀**：

**(a) Falsifiable claims**（Patrick Hughes · <https://bmdpat.com/blog/ai-agent-claims-done-verify-2026>）
五種 claim type 是**封閉集合**，agent 只能說「file X contains Y」這種**一 grep 就見真章**的話，無法用模糊語言蒙混。
> 真正該學的是 claim type 的**封閉性**——不是「請 agent 附上證據」（那還是散文），而是「**只能說這五種話**」。這正對應本專案 style guide 推的 `sealed class` + 窮盡式 `switch`。

**(b) Delegation receipts**（Rel(AI)Build · <https://arxiv.org/html/2606.26924v1>）
論文的 transition guard **不只查順序，還查「交付憑證」**——委派收據必須被記錄、file-writing 的委派必須 `securityScan.status == "clean"` 才能離開該 phase。
> **把紀律降級成資料結構**：我們機制 8 是人治（主對話記得去查），論文把它變成 state 檔上的必要欄位，**缺了就轉不過去**。

**(c) `confirmed_by: human|auto`**（Cheng & Cheng · <https://arxiv.org/abs/2604.23049>）
**⚠️ 作者更正**：實為 **Edward Cheng 與 Jeshua Cheng 兩人**（Jeshua Cheng 標註 InquiryOn），搜尋階段的「Stanford」隸屬與 `et al.` 無法由來源證實。

我們的 `awaiting_confirmation` 是布林，`--confirmed` 通過後即消失——**state 檔無法區分「使用者親自確認」與「`autonomous` 級自動放行」**。兩者在事後稽核與交接時看起來完全一樣。最小改動：state 加一欄 `confirmed_by`。

**綜合判斷**：這三項合起來是一條完整的升級路徑，且都是**加欄位 + 加校驗**，與 `wf-state.sh` 既有的 schema 校驗 + 原子寫入是同一套語彙，**不需要新架構**。

#### R12. 🟢 兩個純機械、零推論成本的機制

**(a) 迴圈偵測 `issues_hash`**（alecnielsen · <https://github.com/alecnielsen/adversarial-review>）
> ⚠️ **搜尋階段的描述嚴重低估**：「3 輪硬上限」只是四條停機條件之一且可調。**真正的重點是 `issues_hash` 比對驅動的 circuit breaker**——用「這輪的 issue 集合跟上輪一模一樣」當停機訊號，而非用輪數。另外 Phase 4 **不對稱**：只有 Claude 綜合與改碼，Codex 全程不寫檔，所以是「對稱批評 + 單邊仲裁」，非對稱辯論。

**我們的缺口**：機制 1 管「stage 間能否轉移」、機制 2 管「人有沒有確認」，**兩者都沒處理「同一 stage 內反覆修不好」**。目前 `3→2→3` 打轉只能靠人在暫停點自己察覺。`issues_hash` 相同 N 次即跳閘是純機械判定。
（Rel(AI)Build 亦有對應機制：**auto-fix 迭代上限 3 次即升級人類**，依據是修復效力在 2–3 次後急遽下降。）

**(b) Port 配置**（Uzi · <https://github.com/devflowinc/uzi>）
機制 4 只保證 **state 檔**隔離，但 worktree 裡跑 `flutter run` / example app / test server **仍會撞 port**。這在 N>1 時是必然衝突而非臆想威脅。
最小版本：worktree 建立時從 range 配 port 寫進 state，驗收指令用該變數——**不需要抄它的 tmux 那套**。
> ❌ **刻意不學**：`uzi auto` 自動按 Enter 過 trust prompt，方向上直接牴觸機制 2（暫停棘輪）與機制 3（`pause_level`）。

#### R13. CORROBORATES 九項（歸納，不逐項展開）

Spec Kit、Kiro Specs、Agent OS、Vibe Kanban、Claude Squad、Stately Agent (XState)、Claude Code Spec Workflow、Ralph (wiggumdev)、Vibe Engineering。

**歸納結論**：這九項全數佐證我們的骨架，**但沒有一項的執行層比我們硬**——多數把階段順序寫在 markdown 或靠使用者不下指令來達成暫停（Claude Code Spec Workflow 是機制 2 的明確反例）。**Stately Agent (XState)** 是唯一在執行層同構的（in-process guard，模型只能在合法轉移中選擇），只是層級不同（in-process vs shell + state 檔）。

### 4. Linus 式總評

> **這批工作流有一個共同的誠實之處：沒有一個人宣稱自己解決了「讓 LLM 可靠」這件事。**
> Huntley 說他的方法「deterministically bad」，Beck 在抓 agent 刪測試，Hashimoto 拒絕
> ship 看不懂的 code，Böckeler 直說機率性 sensor 不可靠。**全都在講同一件事：
> 模型不可信，所以把可靠性放到模型外面。**
>
> `gen-dev-workflow` 的 `wf-state.sh` + hook 攔截走的正是這條路，而且**走得比多數人遠**——
> 上表七項機制中，只有 Böckeler 明確主張「必須是計算式（確定性）控制」，
> 其他人的約束大多仍停留在文件與人工盯場。
>
> **但別自滿：** 這也意味著我們承擔了別人沒有的複雜度。Steinberger 的批評必須留在文件裡
> 當作反面壓力——**每次要往 SKILL.md 加一條規則時，先問這條是 Guide 還是 Sensor。
> 如果是 Guide，它大概率會被忽略，那就不值得加。**

---

## 🟠 第四部分：SKILL.md 拆分後的待辦（2026-08-25 · 由 Issue #142 整併）

> **背景**：`SKILL.md` 從 1017 行拆為 209 行主檔 + 8 份 `references/`（PR #141）。
> 拆分本體與四類斷裂（交叉指涉／歸屬錯置／語意遺失／速查漏步驟）已完成，
> 拆分殘留四項（STAGE 5 攔截後果、STAGE 6 同步範圍、batch `--pause-level`、
> context 區間寫法）亦已修（`8e2063e`）。
>
> 以下兩項是查找途中發現的**既有設計缺口**，非拆分造成。
> 原為 Issue #143／#144，已整併回 Issue #142 統一追蹤。
> **§W1 已於 2026-08-26 解決（`2929e2b`）；§W2 已於 2026-08-30 實查重新定性為 ⏸ 降級待命（Issue #152）**
> ——原描述與 hook 實際程式碼脫節，剩餘缺口收斂為「非 git 位置寫入偵測不到」，
> 且該委派路徑實際使用量趨近於零，附重啟條件見該節。

### §W1. quick→sequence 升級缺少分支與未 commit 變更的遷移步驟 — ✅ 已解決（2026-08-26，採方案 B）

> `references/execution-modes.md:33` 對升級只寫「將 Root 中未 commit 的變更帶入新工作區」，
> 沒有定義**怎麼帶**。而 `wf-state.sh upgrade` 只改 state JSON（`mode`→sequence、`stage`→2），
> **完全不碰 git**——所以 state 會顯示「已升級」，工作區卻可能根本沒建成。

**實測確認的兩個硬阻礙**（2026-08-25 於暫存 repo 重現）：

| 照文件執行 | 結果 |
|:---|:---|
| `git worktree add -b <branch> <path>`（沿用 ticket-id-dev-prep 的帶 `-b` 寫法） | `fatal: a branch named '...' already exists` |
| `git worktree add <path> <branch>`（去掉 `-b`） | `fatal: '...' is already used by worktree at '<原 repo>'` |

**兩種寫法都 fatal**——quick 模式直接在原 repo checkout 該分支，分支既存在又被佔用。
且 `git worktree add` 不搬未 commit／已 staged／未追蹤的變更，即使建成也會把做到一半的工作留在原地。

**已實測可行的步驟**（關鍵是文件漏掉的第 2 步）：

```bash
# 1. 未 commit 變更打成 WIP commit（不用 stash——stash 是 repo 層級，跨 worktree 易混淆；
#    commit 跟著分支走，切過去自然帶到）
git add -A && git commit -m "WIP: quick 升級前保存"

# 2. 🔴 原 repo 切離該分支——文件漏掉這步，是唯一的失敗點
git checkout main

# 3. 為既存分支建 worktree（不帶 -b）
git worktree add .claude/worktrees/<repo>-<slug> <branch>

# 4. state 升級 + 搬移
wf-state.sh upgrade <state 檔>
mkdir -p <worktree>/.claude/workflow-state
wf-state.sh promote <state 檔> --branch <branch> --dest <worktree>/.claude/workflow-state

# 5. cd 進 worktree，接 STAGE 2
```

實測結果：worktree 內含已 commit 與原未 commit 的內容、untracked 檔也在；
state 檔 `mode=sequence stage=2`，原 repo 的已由 `promote` 刪除。

**但先問三個鐵律問題再決定要不要補**：

1. **真實問題？** 部分——觸發條件只有「以為是小修正、動手發現不是」。實查 git 歷史與
   state 目錄，**本 repo 至今無任何升級發生過的痕跡**。
2. **更簡單的方法？** 有。撞到時 `git stash` 或 WIP commit → 走完整流程從 `origin/main`
   拉新 worktree → 取回變更，三行指令，比修好 `upgrade` 便宜。
3. **會破壞什麼？** 補文件不會。但要注意這條路徑**繞過 STAGE 0a/0b**——升級的理由通常是
   「發現需要設計判斷」，直接接 STAGE 2 等於在沒有 spec/plan 的情況下做一件已知需要計畫的事。

**兩個候選方案**：

- **A. 補齊步驟** — 把上述實測過的五步寫進 `execution-modes.md`，並補失敗回復規則
  （搬到一半失敗時如何還原）。附帶還要定義 `promote` 對 branch-scoped state 的
  遷移來源／呼叫順序／目標路徑／來源刪除（目前文件只寫 pending 檔用法，
  但實作接受任何通過 schema 校驗的檔案）。
- **B. 移除 `upgrade`** — 文件改為「quick 中途發現超出範圍 → 停下、WIP commit、
  走完整流程重新開始」，並拿掉 `wf-state.sh upgrade` 指令。
  理由是 Linus 判準：`upgrade` 是為「不浪費已做的工作」長出的特殊情況，
  但場景罕見、實作是壞的、繞過成本只有三行指令——**消滅特殊情況比修好它更有價值**。

**⚠️ 附帶發現（比上述更該先做）**：`command-cheatsheet.md` 列了所有指令，卻**沒有任何一列
說明升級怎麼觸發**。實際設計是「無使用者指令——由 Claude 判斷超標後停下提議，或使用者
直接口頭要求」，但這件事只藏在 `execution-modes.md:33` 的一句話裡。
**先讓人知道它怎麼被觸發，才輪得到它怎麼執行。**

**Effort**：A 低（純文件）／B 低（刪指令 + 改文件）｜**價值**：⭐⭐（觸發機率低）

> **✅ 決議（2026-08-26 · commit `2929e2b`）：採方案 B，並一併補上附帶發現。**
>
> - `wf-state.sh` 的 `upgrade` 子命令、用法說明、`state-machine.md` 的表格列全數移除
> - `execution-modes.md` 改為「**超出範圍時收工重來**」：WIP commit 或 stash → 照 STAGE 1 從
>   `origin/main` 建新 worktree → 在新工作區 cherry-pick／stash pop → 刪掉 quick 的 state 檔。
>   並就地記下「為什麼不做就地升級」（兩種 worktree 寫法皆 fatal、不搬未 commit 變更、
>   落在 STAGE 2 等於跳過 0a/0b），避免日後有人重新推導一次
> - `command-cheatsheet.md` 補上它從來沒有的那一列：**這件事怎麼觸發**——沒有指令，
>   由 Claude 判斷後停下提議，或使用者直接口頭要求
>
> 選 B 不選 A 的理由：A 是把一條沒人走、走了也不該走的路修平；B 是承認這條路不該存在。
> 繞過成本只有三行指令，而 `upgrade` 是為「不浪費已做的工作」長出的特殊情況——
> **消滅特殊情況比修好它更有價值**。

### §W2. 委派子進程的檔案系統邊界：Sensor 已存在，觀測範圍受限於 git — ⏸ 降級待命（2026-08-30 實查重新定性）

> **標題沿革**：原標題為「~~仍是 Guide 而非 Sensor~~」。2026-08-30 實查後該定性已不精確
> （post 端的 `git status` 差集是確定性 Sensor；pre 端則是自動化 Guide／准入檢查，
> 詳見下方「兩端性質」表），故改為現名。引用本節的舊標題時請注意此變更。
>
> 這是 §3(B) 第 4 項「Guide→Sensor」（`a557dfc` / Issue #134，2026-08-19 完成）的**殘留缺口**，
> 即上表順位 6 標注的「**R5 的擴大範圍未做**……該檔檔頭已載明屬另案」——本節就是那個另案。
>
> **🔴 2026-08-30 實查更新（Issue #152）**：本節原以 `⬜ 待辦` 描述的「現況」與
> `wf-guard-delegate-cwd.sh`（390 行）實際程式碼嚴重脫節——原文寫於 2026-08-25，
> 而該 hook 落地後歷經 `a557dfc` → `36a5996` → `3411455` 三次演進，文件未同步。
> 下方現況表與候選方案表均已依實際程式碼重寫。

**現況**（2026-08-30 逐行核對 `.claude/hooks/wf-guard-delegate-cwd.sh`）：

透過 `mcp__gemini-cli__ask-gemini` 委派的子進程具備寫檔、跑 shell、`git commit` 能力。
限制它的手段**不只是** prompt 裡的文字——`wf-guard-delegate-cwd.sh` 已註冊於
`.claude/settings.local.json`（該檔為 gitignore 的本機設定，行號隨機器而異；
2026-08-30 於本機實查為 `:252,272`）的 `PreToolUse` / `PostToolUse`
（matcher `mcp__gemini-cli__ask-gemini`），在工具呼叫層攔截：

| 端 | 實際行為 | 缺口 |
|:---|:---|:---|
| pre | `run_pre()` 比對派發 prompt 是否含目標 worktree 絕對路徑，不符即 `sys.exit(2)`——**對派發者失誤具實際阻擋力**（BUG-1 的 exit code 教訓已內化，程式碼內有註解標記）。另有 P-1～P-6 六道 false-positive 防護：payload 解析失敗、非委派工具、不在 worktree、無 state 檔、branch 對不上、stage 非 2，任一命中即放行 | 只比對**派發意圖**（prompt 寫了哪個目錄）。**對子進程的約束仍是 prompt 文字，子進程可忽略**——故此端是自動化 Guide，不是 Sensor |
| post | `take_status()` 以 `git status --porcelain` 差集偵測目標 worktree 以外的寫入與新增 commit，命中則告警並寫入 `cwd-violations.log` | 只涵蓋主 repo 與已知 worktree，**寫到非 git 位置偵測不到**；只告警不阻斷 |

原文宣稱的三項缺口，逐項核對如下（**一項不成立、一項半成立、一項成立但非疏漏**）：

- 「pre 檢查的是**字串**，不是實際能寫到哪」→ **成立**（這點原文沒說錯）：
  `run_pre()` 判斷的確實是 `target not in prompt`，管不到子進程實際往哪寫。
  但**它擋的對象是派發者而非子進程**，在這個定位上是確定性的。
  另需澄清：post 端比對路徑的 `is_allowed()` 兩側都 `os.path.realpath`，
  防 symlink 與 `..` 繞過，並以路徑分隔符為界避免 `/x/.pub-cache-evil`
  被 `/x/.pub-cache` 誤判命中——**該防護屬 post 端，不是 pre 端**，勿混為一談。
- 「限制手段是 prompt 裡的一段文字，沒有強制力」→ **對子進程而言仍成立**，但對**派發者**
  不成立：`PreToolUse` 的 `exit 2` 確定性攔截「派發時未寫對目錄」這個失誤，與子進程是否
  「願意讀 prompt」無關。換言之，這一層擋的是派發者的手滑，不是子進程的違規。
- 「post 只告警不阻斷」→ **屬實，但為刻意設計**（程式碼標記 `U-1`）：PostToolUse
  觸發時動作已完成，回捲無意義。這是機制的正確取捨，不是疏漏。

另有原文未記載的既有防護：`whitelist_roots()` 動態解析 git 內部目錄、`PUB_CACHE`、
Flutter/Dart SDK 根（由 `which` 反解，相容 fvm）與 `TMPDIR`，**優先動態解析、並保留
`~/.pub-cache`／`~/fvm`／`/tmp` 等 fallback**（設計原則見 `docs/features/2026-08-19-delegation-cwd-sensor.md:114`：
以解析出的實際路徑為準，fallback 僅在解析不到時兜底）；
`diff_entries()` 只回報 after 新增項，委派前既有的 dirty 檔不算越界（P-9）；
整體 fail-open（P-11），hook 自身壞掉不連帶卡死 workflow。
純函式已有測試 `.claude/hooks/tests/test_delegate_cwd_logic.py`。

**剩餘的真實缺口**：**所有未被「委派前後兩次 `git status` 取樣」呈現的檔案系統活動**。
這不只是「寫到非 git 位置」一種形狀，至少還包括：

- **短暫寫入**：委派期間在目標 worktree 外建檔又於 PostToolUse 前刪除，前後取樣無差異
- **巢狀 repository／submodule 內部**：其內容不呈現在父 repo 的 `status` 中
- **`.gitignore` 忽略的檔案**：`take_status()` 用 `--untracked-files=normal` 而**未帶 `--ignored`**，
  被忽略的檔案不進快照也不進 `diff_entries()`。此為**刻意設計**（程式碼標記 `P-10`）——
  否則 build 產物與快取會把告警淹沒——但代價是這類寫入確實看不見
- **非 git 位置**：其他專案、家目錄普通檔

三者同源——皆為以 `git status` 差集為觀測基底的固有天花板，非實作疏失。

用 Böckeler 的框架講（§2.6）：本節標題「Guide 而非 Sensor」的定性**部分已不成立，但不能反向over-claim**。
**兩端的性質不同，必須分開講**：

| 端 | 性質 | 理由 |
|:---|:---|:---|
| pre | **自動化 Guide／准入檢查**（非 Sensor） | `run_pre()` 只判斷 `target not in prompt`，確定性攔截的是**派發者寫錯目錄**這個失誤。它約束子進程的手段仍是 prompt 文字，**子進程大可忽略該文字往別處寫**——這一層的強制力沒有變 |
| post | **Sensor** | `git status` 差集是動手後的計算式偵測，不依賴子進程配合 |

所以準確的說法是：**Sensor 已存在於 post 端，但觀測範圍受限於 git；pre 端則是把原本的人工紀律升級成自動化准入檢查**。
缺的不是「把 Guide 升級成 Sensor」（§4 第 4 項，已於 `a557dfc` 完成該項所指的 hook 攔截），
而是「把既有 Sensor 的觀測基底從 git 擴大到檔案系統」，那是性質不同、成本高一個量級的另一件事。

**候選方案的實查判定**（2026-08-30）：

| 候選方案 | 判定 | 依據 |
|:---|:---|:---|
| pre 端對正規化絕對路徑做強制校驗 | ✅ **已實作** | `is_allowed()` 雙側 `os.path.realpath` 比對 |
| 容器隔離（Dagger／Container Use） | ❌ 出局（**成本**，非能力不足） | 技術上做得到 fs 邊界，但對單人 Flutter package 過度工程——本文件先前已如此評估 |
| 專用受限使用者 + 檔案系統權限 | ❌ 出局（**成本**，非能力不足） | 技術上做得到，但需改動系統層帳號，遠超問題嚴重度 |
| 受限掛載點 | ❌ 出局（**成本**，非能力不足） | 同上 |
| 限制寫入型委派，只允許唯讀分析 | ⏸ 保留 | 唯一完全落在專案內且確定有效，但會實質閹割 STAGE 2 委派能力 |

覆蓋非 git 位置需 fs-level 觀察。`docs/plans/2026-08-19-delegation-cwd-sensor.md:148`
在原始實作時已界定此範圍：「要涵蓋任意檔案系統寫入，需要 fs-level 觀察
（fswatch／eBPF／FUSE），成本與誤判率都遠高於本次範圍，屬另案。」
macOS 另有 `/usr/bin/sandbox-exec`，是**目前環境可見、且不需改動本 repo 以外系統層設定**的
fs 層限制候選（上表三個 ❌ 項技術上同樣做得到，差別在採用成本），但 MCP server 於
`~/.claude.json` 以 `npx -y gemini-mcp-tool` 啟動（`"env": {}`）——**那是全域設定，
不在本 repo 內**，改它會影響所有專案而非僅此 repo，超出本專案可控範圍。

**實用性判準**（Linus 第三條：解決真實存在的問題）：

| 指標 | 實測值（2026-08-30） |
|:---|:---|
| `mcp__gemini-cli__ask-gemini` 累計呼叫 | **2 次**（`~/.claude.json` 的 `skillUsage`） |
| `gemini` CLI | **未安裝**（`which gemini` → not found；本機僅有 `agy`） |
| `cwd-violations.log` | **從未產生**（全 repo `find` 零命中） |

此委派路徑的實際使用量趨近於零。為零使用量的路徑補強安全邊界，**複雜度與嚴重度不匹配**——
這正是「解決想像中的威脅」而非真實問題。故由 `⬜ 待辦` 降為 `⏸ 降級待命`。

**重啟條件**（滿足任一即重新評估）：

1. 委派使用量顯著上升（`cwd-violations.log` 開始產生紀錄，或 `ask-gemini` 成為常態工具）
2. MCP server 設定移入專案內（屆時 `sandbox-exec` 或等價方案落在可控範圍）
3. 出現實際的越界事故

**刻意不做**：在 prompt 裡再加一段沒有強制力的文字——那正是本項批評的對象。
也不改現有三條委派紀律的措辭（作為 Guide 仍有價值，只是不能當作邊界）。

**Effort**：中～高（依方案而定）｜**價值**：⭐⭐（安全強度，不影響日常執行；因使用量趨近於零，價值由 ⭐⭐⭐ 下修）

> **⚠️ 兩項都不影響正常流程執行**（2026-08-25 實查）：
> ~~§W1 只在「quick 中途超標」時觸發，本 repo 至今未發生~~（已於 2026-08-26 解決）；
> §W2 是安全強度不足而非功能故障，委派本身正常運作，hook 也確實掛著。
> 兩者皆非阻擋項，可依實際需要排程。
