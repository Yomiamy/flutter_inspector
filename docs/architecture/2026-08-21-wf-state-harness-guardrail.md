# wf-state.sh: Execution Harness 與 Guardrail 機制解析

> **📝 更新紀錄 (Changelog)**：
> * **2026-08-21**：§「同構的第二個弱點：委派的工作目錄約束」結案（issue #134 / PR #135 已合併）。該節指出的 hook 層對策已落地為 `.claude/hooks/wf-guard-delegate-cwd.sh`（`pre` 阻擋派發者失誤、`post` 偵測子進程失誤，只告警不阻斷）。`wf-state.sh` 本身未修改——檔案位置本就不在其管轄範圍，這正是該節的原始結論。檔名日期前綴由 `2026-08-08` 更新至 `2026-08-21`。
> * **2026-08-10**：委派傳輸層由 `agy -p` headless 改為 `gemini-mcp-tool`（MCP）。**本文件描述的 `wf-state.sh` 機制完全未受影響**（狀態機與委派後端正交），僅在文末「結構性邊界」節補上新的同類弱點：MCP 無法指定 cwd，工作目錄約束只能寫在 prompt 裡——與 Gap 2.6 同構的「約束不在強制層」問題。
> * **2026-08-08**：依 `wf-state.sh` 原始碼逐行重新核對（基準 commit `daadf03`）。新增 §1.4 暫停粒度、§1.5 佔位檔回收、§2.6 quick 升級單向閘、§3 批次佇列子系統、§4 指令全表；修正 §2.3 轉移表（原漏 `3→2` 退回與 3 條 STAGE 5 轉移）、§2.4 白名單（原漏 `pause_level`）、§2.5 任務完整性驗證的實際觸發條件（僅 `next=3`）。檔名日期前綴由 `2026-07-21` 更新至 `2026-08-08`。
> * **2026-07-21**：建立初版。

> **核心信條**：把 LLM 當成一台不受控、隨時可能暴衝的引擎。單靠 Markdown 提示詞去約束 LLM 就像用「道德勸說」在管教程式碼；我們必須在底層實作「硬體級別的防呆機制」。

`wf-state.sh` 是 `gen-dev-workflow` 技能的專屬狀態機 (State Machine) 腳本。它被設計為工作流狀態檔 (State JSON) 的**唯一存取入口**。

在這支腳本裡，**Harness（基礎執行設施）** 與 **Guardrail（邊界防護）** 有著明確的職責劃分：Harness 負責提供標準化的掛載點讓 LLM 驅動流程；而 Guardrail 負責擋下所有愚蠢、出格或破壞性的行為。

> **本文件的核對基準**：`.claude/skills/gen-dev-workflow/scripts/wf-state.sh`（439 行，commit `daadf03`）。所有機制描述均以腳本原始碼為準，非以 SKILL.md 的敘述為準——當兩者衝突時，**程式碼是唯一權威**。

---

## 1. Harness 機制（基礎執行設施）

Harness 的目標是**抹平底層系統複雜度**，讓 LLM 不需要親自處理檔案競爭、型別轉換或 JSON 序列化，只要呼叫標準 API 即可。

### 1.1 唯一掛載點的封裝
腳本提供了標準的 `init`, `promote`, `get`, `set`, `advance`, `stage-done`, `task-done`, `confirm`, `upgrade`, `prune` 等指令介面，外加一組批次佇列指令（見 §3）。它將繁瑣的 shell 指令隱藏起來，讓 LLM 統一透過這個介面讀寫狀態，而非使用原始的 `cat`、`sed` 或 `echo`，這為自動化執行提供了穩定的軌道。

檔案定位由 `resolve()` 統一處理：參數含 `/` 視為路徑，否則視為相對 `$STATE_DIR`（預設 `.claude/workflow-state`，可用 `WF_STATE_DIR` 覆寫）的檔名。LLM 不需要自己拼路徑。

### 1.2 檔案層級的競爭與原子性 (`claim_new`, `atomic_write`)
*   **排他佔位**：`claim_new` 利用 `set -C; : > file` 實作排他創建，消除「檢查存在到創建檔案」中間的併發窗口 (Race Condition)。
*   **原子寫入**：`atomic_write` 強制資料先寫入暫存檔 (`mktemp`)，確認 JSON 解析成功且**通過 schema 校驗**後，才使用 `mv` 覆蓋原檔。確保腳本中途當機時，磁碟絕不會留下寫壞一半的 JSON。
*   **校驗的子 shell 隔離**：`atomic_write` 內以 `( validate "$tmp" )` 包住校驗——`validate` 失敗時會 `die`（即 `exit 1`），若不隔離在子 shell 中，暫存檔就會來不及清理而洩漏。這個括號不是風格，是資源保證。

### 1.3 型別與變數轉換的基礎設施 (`jq_val`, `apply_sets`)
幫 LLM 處理 Bash 傳遞參數到 JSON 儲存時的型別地雷。`jq_val` 的判定順序為：
1. 符合 `^-?[1-9][0-9]*$` 或字面 `0` / `-0` → 輸出為 **JSON 數字**
2. 字面 `true` / `false` / `null` → 輸出為 **JSON 布林/空值**
3. 其餘一律經 `jq -n --arg` 轉為**字串**（自動處理引號跳脫）

第 1 條的正則刻意排除了帶前導零的數字（如 `007`），讓它退化成字串而非產生非法 JSON。LLM 不會因為處理引號和型別而寫出崩潰的 bash 邏輯。

### 1.4 暫停粒度的單一判定來源 (`should_pause`)
`should_pause <state 檔> <gate>` 是**全腳本唯一**決定「這個暫停點該不該停」的地方。LLM 不需要自己判斷，只要照常呼叫 `stage-done` / `task-done`，看回傳訊息是「等待使用者確認」還是「自動推進」即可。

| `pause_level` | Stage 關卡 | STAGE 2 任務間 |
|:---|:---|:---|
| `strict`（預設） | 全停 | 每個任務都停 |
| `balanced` | 只停 `0b` / `2` / `4` | 不停 |
| `autonomous` | 全不停 | 不停 |

兩個關鍵的防呆設計：

*   **失效方向偏保守**：`jq -r '.pause_level // "strict"'` 加上 `case` 的 `strict|*)` 萬用分支，代表欄位缺失、值異常、甚至檔案被寫壞成無法辨識的值，一律退回 `strict`。壞掉的方向永遠偏向「多停一次」，不偏向「少停一次」。
*   **quick × balanced 的明示短路**：`balanced` 的關卡集（`0b`/`2`/`4`）是 sequence 專屬的 stage 值，而 quick 模式的 stage 是自由標籤且無 task 迴圈。若不特別處理，對 quick 套 `balanced` 會「看似生效、實則全部落空」——腳本因此明文將這個組合降級為 `strict`，拒絕提供假的安全感。

### 1.5 佔位檔的失敗回收 (`trap ... EXIT`)
`init`、`promote`、`batch-init` 三處都遵循同一個模式：`claim_new` 搶到檔名後**立即**設 `trap 'rm -f "$f"' EXIT`，等 `atomic_write` 成功才 `trap - EXIT` 解除。

這解決的是一個具體的死結：若 `claim_new` 建了 0-byte 佔位檔、但後續寫入失敗，那個空檔會永遠佔住該 branch 對應的檔名——之後任何流程想用同一個 branch 都會撞到「已存在，不覆蓋既有流程」而卡死。trap 保證失敗路徑不留殘骸。

---

## 2. Guardrail 機制（邊界防護與斷路器）

Guardrail 的設計哲學充滿了對 LLM 的「極度不信任」。它的任務是：一旦發現不對勁，立刻 `exit 1` 讓流程當機，**絕對拒絕靜默失敗 (Silent Failure)**。

### 2.1 資料結構守護 (`validate`)
每次讀寫都會強制跑 `jq -e` 檢查 Schema 的完整性與欄位型別：

*   `schema_version` 必須為 `1`
*   `workflow_id` / `stage` 必須是字串
*   `mode` 必須是 `sequence` / `jump` / `quick` 三者之一
*   `completed_tasks` 必須是陣列，且**所有元素都是數字**
*   `total_tasks` 必須是 `null` 或數字
*   `pause_level` 必須是 `null` 或三個合法值之一
*   `awaiting_confirmation` 必須是布林值

任何異常都會中斷寫入，確保**爛資料連磁碟的邊都摸不到**。`get` 指令同樣先校驗再輸出——腐壞的檔案會立即失敗，而不是被靜默續接。

### 2.2 強制暫停棘輪 (Pause Point Ratchet)
這是防範 LLM「無聲遺忘與越權」的最強防護欄。

腳本規定，在觸發 `stage-done` 或 `task-done` 後，狀態檔會依 `should_pause()` 的判定鎖上 `awaiting_confirmation=true`。如果 LLM 試圖在未經使用者同意的情況下呼叫 `advance` 推進流程，只要未攜帶 `--confirmed` 旗標，腳本就會無情報錯：

> `stage <N> 等待使用者確認中。先在對話中暫停詢問，獲確認後帶 --confirmed 重跑`

這強迫 LLM 在程式碼層級證明「確實有停下來等使用者確認」——跳過暫停點從「無聲遺忘」變成必須蓄意加旗標、在 Bash 歷史留下痕跡的可稽核動作。

⚠️ **棘輪與 `pause_level` 的職責分離**：`pause_level` 只決定「要不要設 `awaiting_confirmation`」，一旦設了，棘輪的強制力完全不變。`autonomous` 關掉的是「等使用者點頭」，不是關掉任何一道校驗（見 §2.3–2.5，全部照常生效）。

### 2.3 寫死狀態機轉移表 (`legal_transition`)
不容許 LLM 憑感覺跳關。在 `sequence` 模式下，腳本直接查表匹配合法路徑，共 **10 條**：

| 分類 | 合法轉移 |
|:---|:---|
| 主鏈 | `0a→0b`、`0b→1`、`1→2`、`2→3`、`3→4`、`4→done` |
| 審查退回 | `3→2` |
| STAGE 5 循環 | `reviewer→responder`、`responder→reviewer`、`reviewer→publisher` |

若試圖從 `0a` 直接跳到 `2`，腳本會判定為非法轉移並直接 `exit 1`。

> **`3→2` 不是漏洞而是設計**：審查不通過必須能退回實作，否則流程遇到問題就是死路。STAGE 5 的三條轉移則讓「回覆 PR review」的 responder ⇄ reviewer 循環有合法路徑可走。
>
> **quick / jump 模式不套用轉移表**——quick 的階段本來就非正式、jump 是使用者明示跳段。但 §2.1 的 schema 校驗與 §2.2 的棘輪對三種 mode 一視同仁。

### 2.4 寫入權限白名單 (`apply_sets`)
腳本明確限制了 `set` 指令可以修改的欄位：

*   **一般白名單**：`spec` / `plan` / `branch` / `issue` / `pr` / `total_tasks` / `interrupted_by`
*   **帶值域校驗**：`pause_level` 允許修改，但值必須是 `strict` / `balanced` / `autonomous`，否則 `die`

如果 LLM 試圖用 `set` 去走後門竄改 `stage` 或 `awaiting_confirmation`，腳本會拒絕操作並明示替代管道（`stage 用 advance、確認用 confirm`），強制其必須走具備嚴格審查的正規路徑。

`apply_sets` 另有一道格式前檢：參數不含 `=` 一律 `die`。這擋掉的是 `set <檔> spec` 這類漏打值的呼叫——若不擋，`${kv#*=}` 會把 key 本身當成 value 寫進 JSON，產生語意錯誤但格式合法的髒資料。

> **先算後寫**：`set` 指令的實作是 `json="$(apply_sets ...)"` 先在記憶體中算完，才 `atomic_write`。`apply_sets` 中途 `die` 時整個指令中止，連暫存檔都不會建立。

### 2.5 任務完整性驗證
攔截 LLM 在實作未完成時強行推進流程。**觸發條件精確**：僅在 `mode=sequence` 且 `next=3`（即 STAGE 2 → STAGE 3）時檢查：

```
completed_tasks 的長度 < total_tasks  →  拒絕推進
```

錯誤訊息會回報實際進度：`實作尚未全部完成（已完成 N / 共 M 任務），拒絕推進至 STAGE 3`。

`total_tasks` 為 `null` 時跳過此檢查——沒宣告總數就無從比對，這是刻意的寬容（並非所有流程都會事先拆好任務數）。

> `task-done` 另有配套限制：`sequence` 模式下僅能在 `stage=2` 執行，避免任務計數在錯誤的階段被污染。而 `completed_tasks` 的寫入經過 `unique`，重複標記同一任務不會灌水通過此校驗。

### 2.6 quick 升級的單向閘 (`upgrade`)
`upgrade` 將 quick 模式轉為完整流程（`mode→sequence`、`stage→2`），並強制**單向**：

*   來源 mode 必須是 `quick`，其他一律 `die`——不存在 sequence 降級回 quick 的路徑，避免用降級來繞過轉移表。
*   同樣受棘輪管轄：`awaiting_confirmation=true` 且未帶 `--confirmed` 時拒絕執行。

---

## 3. 批次佇列子系統（多 workflow 依序執行）

批次佇列讓多個**各自獨立**的需求依序跑完整流程（各自 worktree / branch / PR）。它與主 state 檔是兩套平行的資料結構，刻意不共用 schema。

### 3.1 獨立的 schema 與寫入路徑
`batch_validate` 校驗批次專屬結構（`batch_id` 字串、`cursor` 數字、`pause_level` 三選一、`items` 非空陣列且每項 `.task` 為字串），`batch_write` 則是與 `atomic_write` 同構、但改走批次 schema 的原子寫入。

**兩套校驗不可互換**：批次檔沒有 `stage` / `awaiting_confirmation`，用主 schema 去驗會全數失敗。分成兩個函式而非加分支，是讓型別錯誤在呼叫端就暴露。

### 3.2 批次檔的自動定位 (`resolve_batch`)
省略檔名時自動掃描 `$STATE_DIR/.batch-*.json`：

| 找到數量 | 行為 |
|:---|:---|
| 0 個 | `die`，提示先跑 `batch-init` |
| 1 個 | 直接採用 |
| ≥2 個 | `die` 並列出全部，**要求使用者明示** |

≥2 個時拒絕猜測，是與 SKILL.md「不因為看到某個批次檔就自行接續它」同源的紀律。

### 3.3 游標邊界防護
`batch-done` / `batch-fail` 在標記前先檢查 `cursor < total`，已跑完的批次再標記會被 `die` 擋下（`批次已全部處理完畢（cursor=N/M），無當前項目可標記`），避免游標溢出寫壞陣列索引。

這兩個指令另有一處參數解析的細節：第一參數若以 `--` 開頭則**不**當成檔名 shift 掉，確保 `batch-done --pr <url>`（省略檔名直接帶選項）能正確解析。

> **失敗不中止批次**：`batch-fail` 同樣讓游標前進到下一項。各項獨立，沒有理由讓後面的陪葬。

### 3.4 中止與清理
`batch-abort` 只刪批次檔，明文保證**已建立的 branch / PR 不受影響**——沿用整條 workflow「branch 永不自動刪除」的紀律。

---

## 4. 指令全表

| 指令 | 用途 | 主要 Guardrail |
|:---|:---|:---|
| `init` | 建新 state（無 `--branch` → pending 檔） | sequence 只能從 `0a` 起始；`pause_level` 值域校驗；佔位檔 trap |
| `promote` | pending → `<branch-slug>.json` | 需 `--branch`；來源先校驗；佔位檔 trap |
| `get` | 校驗後輸出 JSON | 讀取即校驗，腐壞檔立即失敗 |
| `set` | 更新欄位 | 白名單 + `k=v` 格式檢查 + 先算後寫 |
| `stage-done` | 標記 stage 完成、進入暫停點 | sequence 下參數須等於目前 stage |
| `task-done` | 任務完成（記入 `completed_tasks`） | sequence 下僅能在 STAGE 2；`unique` 去重 |
| `confirm` | 清除等待旗標（stage 不變） | — |
| `advance` | 推進 stage | 棘輪 + 轉移表 + 任務完整性（`next=3`） |
| `upgrade` | quick → sequence（單向） | 來源須為 quick；棘輪 |
| `prune` | 清理 7 天以上的孤兒 pending 檔 | 只刪 `.pending-*.json`，`-mtime +7` |
| `batch-init` | 建批次佇列 | 至少一個項目；`pause_level` 值域；佔位檔 trap |
| `batch-get` / `batch-next` | 讀批次 / 取下一項 | 批次 schema 校驗；跑完回傳 `DONE` |
| `batch-done` / `batch-fail` | 標記當前項並前進游標 | 游標邊界檢查；`--` 前綴不誤吞 |
| `batch-abort` | 中止批次 | 只刪批次檔，branch/PR 保留 |

---

## 總結

*   **Harness** 告訴 LLM：「你要開車，方向盤和油門在這裡。」
*   **Guardrail** 告訴 LLM：「你敢開出車道、闖紅燈或不繫安全帶，我就直接熄火，把你踹下車。」

用 Markdown 文件規範 LLM 行為，最終只會淪為願望清單。真正的工程實踐，是將這些規範寫入無法被繞過的底層腳本，用 `exit 1` 來保證系統的正確性。

### 🔴 這套防線的結構性邊界

必須誠實標註：**上述所有 Guardrail 只在腳本被呼叫時才生效**。

腳本擋得住「呼叫了 `advance` 但參數不合法」，擋不住「根本沒呼叫腳本就推進流程」。這正是 [`2026-08-25-workflow-brainstorm.md`](../brainstorm/2026-08-25-workflow-brainstorm.md) 記錄的 **Gap 2.6**——STAGE 5/6 這類獨立入口不在主鏈上，LLM 容易全程不碰 `wf-state.sh`，此時再多的內部校驗都無從觸發。

**對策必須落在入口攔截（hook 層），繼續往腳本內部堆校驗是無效的**。判讀本文件的防護強度時，請把「LLM 會記得呼叫腳本」視為尚未被程式碼保證的前提。

### 🔴 同構的第二個弱點：委派的工作目錄約束（2026-08-10 新增）

2026-08-10 委派傳輸層改走 MCP（`mcp__gemini-cli__ask-gemini`）後，出現一個**與 Gap 2.6 結構完全相同**的弱點，值得並列記錄：

**MCP 工具呼叫無法指定工作目錄（cwd）**。子進程實際在哪個目錄動手，只能靠派發 prompt 裡寫死絕對路徑來「請求」它遵守：

```
工作目錄：<worktree 絕對路徑>
🔴 邊界：不得存取或修改此目錄以外的任何檔案。
```

這段文字**沒有任何強制力**——它是寫給另一個 LLM 看的道德勸說，和本文件開頭批評的「用 Markdown 約束 LLM」是同一件事。子進程若在主 repo 而非 worktree 動手，`wf-state.sh` 的所有 Guardrail 都不會有任何反應：**狀態機管的是 state JSON 的合法性，管不到檔案實際寫在哪顆磁碟位置上。**

| | Gap 2.6 | 委派 cwd 約束 |
|:---|:---|:---|
| 失效模式 | 根本沒呼叫腳本 | 約束只寫在 prompt 裡 |
| Guardrail 反應 | 無（未觸發） | 無（不在管轄範圍） |
| 正確對策層級 | hook 攔截 | hook 攔截 / 委派後驗證 |

**目前的緩解措施是事後驗證而非事前阻擋**：委派紀律第 3 條要求主對話親自跑 `git status` / `git log` 確認實際落地位置，屬**偵測**不屬**預防**。真正的解法同樣落在 hook 層——這再次印證本文件的核心結論：**約束若不在無法繞過的執行層，就只是願望清單。**

> **📌 2026-08-21 結案（issue #134 / PR #135 已合併）**：本節指出的 hook 層對策已落地為 `.claude/hooks/wf-guard-delegate-cwd.sh`，單一腳本兩個 mode 分別對應上表最後一列的兩種選項——**兩者併用而非擇一**，因為它們攔的是不同的失效原因：
>
> | | `pre`（PreToolUse） | `post`（PostToolUse） |
> |:---|:---|:---|
> | 攔誰的錯 | **派發者**忘寫／寫錯工作目錄 | **子進程**收到正確 prompt 卻沒照做 |
> | 判斷依據 | prompt 是否含目標 worktree 絕對路徑 | 主 repo 與其他 worktree 的 `git status` before/after 差集 |
> | 行為 | `exit 2` **真阻擋**（零次無效委派） | `exit 0` **只告警不阻斷** + 寫入 `cwd-violations.log` |
>
> 兩者交集為空：`pre` 抓不到子進程失誤（prompt 寫得再完美也管不住對方），`post` 抓不到派發者失誤（要浪費一整輪委派才發現）。
>
> **`post` 刻意不阻斷**：PostToolUse 觸發時檔案已寫入，`exit 2` 回捲不了已發生的事；且白名單漏列是最高風險，阻斷式上線一漏列就卡死流程，會導致機制被整個關掉。
>
> **偵測範圍的誠實邊界**：機制建立在 `git status` 之上，只涵蓋主 repo 與已知 git worktree。寫入非 git worktree 的位置（其他專案、家目錄普通檔案）偵測不到——涵蓋那些需要 fs-level 觀察（fswatch／eBPF），成本遠超本問題嚴重度，屬另案。
>
> 因此本節的「正確對策層級」欄位已由**待辦**轉為**已實作**；但本節的核心論證（約束不在執行層就只是願望清單）不變，且被實作結果進一步佐證：預防在物理上不可得（MCP 介面無 cwd 參數），**確定性偵測就是本問題的天花板**。
