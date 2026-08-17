# 狀態追蹤（gen-dev-workflow 參考）

> 本檔是 `gen-dev-workflow` 主 skill 的狀態機參考。主檔（`../SKILL.md`）在需要 state 操作時指向這裡。
> guard 的唯一真實來源是 `../scripts/wf-state.sh`——本檔描述如何使用它，腳本本身才是強制點。

每個 stage 開始前，輸出一行進度提示。**前綴帶流程識別**（pending 階段帶 `<wf-id>`，已建 branch 後帶 branch slug），讓多個並行 workflow 的輸出能一眼分辨：

```
[wf-1717400000-3f9a] [0a/5] 撰寫功能規格中...   ← 尚無 worktree，帶 wf-id
[feature-202605-42-cart] [1/5] 建立 Issue + Worktree 中...  ← 已建 worktree，帶 slug
[feature-202605-42-cart] [2/5] 實作中（共 N 個任務）...
[feature-202605-42-cart] [3/5] 審查中...
[feature-202605-42-cart] [4/5] 發布準備中...
[feature-202605-42-cart] [5/5] 完成 ✦ PR: <URL>
```

## 狀態機腳本（唯一存取入口，強制）

state 檔的**所有**建立、讀取、更新一律透過本 skill 的 `scripts/wf-state.sh`，**絕不手寫或手改 JSON**。guard 在腳本裡，不在本文件裡：

- **schema 校驗 + 原子寫入**：先寫 tmp、`jq` 驗過才 `mv`——壞資料進不了磁碟，寫到一半中斷也不會留下半套 state。
- **stage 轉移合法性**：sequence 模式接受 `0a→0b→1→2→3→4`、`3→2`（審查退回）、`4→done`，以及獨立入口銜接轉移 `4→5`、`5→4`、`5→5`、`4→6`、`5→6`、`6→done`，其餘非法跳段直接 exit 1。quick/jump 模式不套用轉移表（quick 的階段本來就非正式、jump 是使用者明示跳段），但校驗與棘輪照常生效。
- **暫停點棘輪**：`stage-done` / `task-done` 之後 `awaiting_confirmation=true`，未帶 `--confirmed` 的 `advance` 一律拒絕。`--confirmed` 只能在**使用者真的在對話中確認後**帶上——跳過暫停點從「無聲遺忘」變成必須蓄意加旗標、在 Bash 歷史留下痕跡的動作。

| 時機 | 指令 |
|------|------|
| 流程啟動（STAGE 0a） | `wf-state.sh init` → 回傳 pending 檔路徑（內含 wf-id） |
| jump / quick 啟動（已知 branch） | `wf-state.sh init --mode jump\|quick --stage <S> --branch <branch>` |
| STAGE 1 建好 worktree | `wf-state.sh promote <pending-檔> --branch <branch> --dest <worktree>/.claude/workflow-state` （注意：sequence 模式下 `promote` 後須依序執行 `advance 0b --confirmed` → `advance 1 --confirmed` 推進 stage 後，才能執行 `stage-done 1`，詳見下方生命週期表） |
| 欄位更新（spec/plan/issue/pr…） | `wf-state.sh set <檔> k=v`（`stage` 與確認旗標**改不了**，防繞過棘輪） |
| stage 完成、進入暫停點 | `wf-state.sh stage-done <檔> <stage>` |
| STAGE 2 單一任務完成 | `wf-state.sh task-done <檔> <n>` |
| 使用者確認（stage 不變，如 STAGE 2 任務間） | `wf-state.sh confirm <檔>` |
| 使用者確認並推進 stage | `wf-state.sh advance <檔> <next> --confirmed` |
| quick 升級完整流程 | `wf-state.sh upgrade <檔> [--confirmed]`（單向 quick→sequence，stage 落在 2；有暫停點等待確認時須帶 `--confirmed`） |
| 設定暫停粒度 | `wf-state.sh init --pause-level strict\|balanced\|autonomous`，或中途 `wf-state.sh set <檔> pause_level=<L>`（見主檔「暫停粒度」章節） |
| 建立批次佇列 | `wf-state.sh batch-init <項目> ... [--pause-level <L>]` → 回傳批次檔路徑 |
| 取批次下一項 | `wf-state.sh batch-next [<檔>]`（全跑完回傳 `DONE`；省略檔名自動定位唯一批次） |
| 批次項目完成 / 失敗 | `wf-state.sh batch-done [<檔>] [--pr <url>] [--branch <b>]` ／ `batch-fail [<檔>] [--note <s>]` |
| 中止批次 | `wf-state.sh batch-abort [<檔>]`（只刪批次檔，branch/PR/worktree 保留） |
| 續接時讀取 | `wf-state.sh get <檔>`（讀取即校驗，腐壞檔立即失敗而非靜默續接） |

> 腳本路徑：`.claude/skills/gen-dev-workflow/scripts/wf-state.sh`（相對當前工作目錄的 repo root；`cd` 進 worktree 後用 worktree 內的同路徑 checkout）。

## 狀態檔：每個 workflow 一個檔，用 branch 命名

**STAGE 1 之後（已建 worktree）的隔離 key 是工作目錄本身。** 自 STAGE 1 起每個 workflow 都在自己的 worktree 內，state 檔自然分開存放於各自 worktree 的 `.claude/workflow-state/`，不會與其他 workflow 或主 repo 衝突，比舊版「同目錄切 branch」更徹底——連檔名撞名的可能性都不存在。

**STAGE 0a/0b（尚無 worktree）階段**：這段仍在**原 repo 目錄**下執行（規劃階段不需要獨立工作區），此時多個並行 workflow 仍共用同一個 `.claude/workflow-state/`，隔離 key 維持 `<wf-id>`（見下方說明）。

**檔案路徑規則：**

```
<worktree-path>/.claude/workflow-state/<branch-slug>.json   ← 已建 worktree 的 workflow（STAGE 1 之後，存於新 worktree 內）
.claude/workflow-state/.pending-<wf-id>.json                ← 尚無 worktree 時的暫存（STAGE 0a / 0b，存於原 repo）
```

- `<branch-slug>`：當前 branch 名稱把 `/` 換成 `-`。
  例：`feature/202605/42-cart` → `feature-202605-42-cart.json`
- `<wf-id>`：**workflow-id**，流程啟動當下產生的唯一識別碼，格式 `wf-<epoch>-<rand4>`
  （`echo "wf-$(date +%s)-$(head -c2 /dev/urandom | xxd -p)"`，例 `wf-1717400000-3f9a`）。
  即使兩個流程在「同一秒、同一 base branch」上同時啟動，`<rand4>` 也保證檔名不撞。

**workflow-id 是 pending 階段的隔離 key（取代舊的「靠 context 記住路徑」）：**

舊設計把「本 session 對應哪個 pending 檔」只存在對話 context 裡——session 一中斷，pending 檔就成了無主孤兒，新 session 因為還沒 branch 而推導不到它。改用 workflow-id 後，這個識別碼**同時寫進 state 檔內容、並由 session 在每次進度回報行帶上**，所以續接時能精準認領自己的 pending 檔，不會誤撿別人的。

```json
// .pending-<wf-id>.json 內容（STAGE 0a/0b 階段，由 wf-state.sh init 產生，勿手寫）
{
  "schema_version": 1,
  "workflow_id": "wf-1717400000-3f9a",
  "stage": "0a",
  "mode": "sequence",
  "branch": null,
  "spec": null,
  "plan": null,
  "awaiting_confirmation": false
}
```

進度回報行格式（每次 stage 切換、每個任務完成時輸出）：
```
[wf-1717400000-3f9a] [1/5] 建立 Issue + Worktree 中...
```
worktree 建立後改帶 branch slug，不再需要 workflow-id：
```
[feature-202605-42-cart] [2/5] 實作中（共 5 個任務）...
```

**state 檔生命週期（解決「尚無 worktree」這個唯一邊界）：**

| 時機 | 動作 |
|------|------|
| STAGE 0a 啟動（流程剛開始，還沒 worktree，在原 repo 目錄） | `wf-state.sh init` → 腳本產生 `<wf-id>` 並於原 repo 建 `.pending-<wf-id>.json` → 之後進度行都帶 `[<wf-id>]` |
| STAGE 1 建好 worktree 後 | `wf-state.sh promote <pending-檔> --branch <branch> --dest <worktree>/.claude/workflow-state` → 腳本補上 `branch` 欄位（`workflow_id` 保留，便於追溯）、寫入新 worktree、刪除原 repo 的 pending 檔；主對話 `cd` 進新 worktree。<br><br>**🔴 STAGE 1 收尾必讀 (Bug 1.6 Workaround)**：`promote` 不會推進 stage（維持 `0a`）。在 `sequence` 模式下，`promote` 完**不可直接** `stage-done <檔> 1`（會被 guard 擋下）。請**務必依序執行**：<br>1. `wf-state.sh advance <檔> 0b --confirmed`<br>2. `wf-state.sh advance <檔> 1 --confirmed`<br>3. `wf-state.sh stage-done <檔> 1`（進入暫停點等待確認） |
| STAGE 1 之後每次寫入 | 對新 worktree 內的 `<branch-slug>.json` 跑 `set` / `stage-done` / `task-done` / `advance`，因 worktree 本身已隔離，零衝突 |
| 直接 jump 進 STAGE 1+（已知 branch，已在該 worktree 內） | 略過 pending，`wf-state.sh init --mode jump --stage <S> --branch <branch>` 直接建當前 worktree 的 `<branch-slug>.json` |

> 關鍵：pending 階段（原 repo 目錄）靠 `<wf-id>` 認領，避免多個並行 workflow 在同一目錄搶檔；STAGE 1 之後每個 workflow 各自在專屬 worktree 內，天然零衝突，不需要再靠命名規則互相禮讓。

**每個 stage 完成後寫入對應 state 檔**（一律經 `wf-state.sh`，以下 JSON 僅為 schema 參考），讓新 session 可以從中斷點繼續：

**sequence 模式**（正常流程跑到這裡）：
```json
{
  "schema_version": 1,
  "workflow_id": "wf-1717400000-3f9a",
  "stage": "2",
  "mode": "sequence",
  "spec": "docs/features/2026-05-03-cart.md",
  "plan": "docs/plans/2026-05-03-cart.md",
  "branch": "feature/202605/42-cart",
  "issue": 42,
  "pr": null,
  "completed_tasks": [1, 2],
  "total_tasks": 5,
  "interrupted_by": "context_budget",
  "awaiting_confirmation": false
}
```

`interrupted_by` 欄位（可選）：記錄上次為何中斷，續接時用來決定第一句話。
- `"context_budget"` → 因 context 超標主動切 session（見主檔 Token Budget Gate）
- `null` 或不存在 → 正常暫停（使用者主動離開）

**jump 模式**（直接指定特定 stage 執行）：
```json
{
  "schema_version": 1,
  "workflow_id": "wf-1717400500-b21c",
  "stage": "5",
  "mode": "jump",
  "pr": 42,
  "spec": null,
  "plan": null,
  "branch": null,
  "issue": null,
  "completed_tasks": [],
  "total_tasks": null,
  "awaiting_confirmation": false
}
```

`mode` 的用途：
- `sequence` → 前面所有 stage 都有完整 context（spec、plan、branch），可以回頭參照
- `jump` → 只有當前 stage 的資訊，不應假設前面的 context 存在
- `quick` → 快速通道，只有 branch 與（可選）issue，無 spec/plan/worktree（見主檔「Quick 模式」章節）

**狀態檔檢查時機（三種觸發）：**

**三種觸發點，發現狀態檔時走同一套邏輯：**

| 觸發 | 關鍵字 |
|------|--------|
| A | `/gen-dev-workflow` |
| B | 「幫我做 X 功能」/ 「開始開發」/ 「新功能開發」 |
| C | 「繼續」/ 「繼續上次」/ 「繼續開發」 |

**先定位「本 session 對應的 state 檔」（A / B / C 共用）：**
```
→ 若本 session context 已持有 <wf-id>（這個流程在本 session 啟動過 STAGE 0a/0b）
   → 直接認領 .pending-<wf-id>.json，走「狀態檔存在時」（不必看 branch）

→ 否則 slug = 當前 branch（git branch --show-current）把 / 換成 -
→ 候選檔 = .claude/workflow-state/<slug>.json
→ 若候選檔存在 → 它就是本 session 的 state，走「狀態檔存在時」
→ 若候選檔不存在：
   ├─ 強制調用 `git worktree list` 取得所有活動中的工作區路徑
   ├─ 遍歷所有工作區路徑，列出它們底下所有的 `.claude/workflow-state/*.json`（已建 branch 的流程，排除 .pending-*）
   │   ├─ 0 個 → 再看有沒有 pending：
   │   │         列出 .claude/workflow-state/.pending-*.json
   │   │         ├─ 0 個 → 走「狀態檔不存在時」
   │   │         ├─ 1 個 → 提示「找到 1 個尚未建 branch 的流程 <wf-id>（STAGE <N>），要接續它嗎？」
   │   │         └─ ≥2 個 → 列出全部 <wf-id> + stage 讓使用者選，或開新流程
   │   ├─ 1 個 → 提示「當前 branch 無對應流程，但找到 1 個其他流程 <slug>，要接續它嗎？」
   │   └─ ≥2 個 → 列出全部讓使用者選，或開新流程
   └─（並行情境下，每個 session 都待在自己的 branch，候選檔通常一擊命中；
       多個流程同時卡在 STAGE 0a/0b 時，靠各自 context 的 <wf-id> 一擊命中，不會誤撿別人的 pending 檔）
```

> **絕不**用 `git branch --show-current` 推導去認領 pending 檔——pending 階段可能多個流程共用同一 base branch，branch 推不出唯一的 pending 檔。pending 階段的唯一識別永遠是 `<wf-id>`。

> **🔴 定位期間，其他 state 檔唯讀。** 上面「列出其他流程讓使用者選」的分支裡，你對那些檔案的權限**只有列名**——不查它們的 PR 狀態、不讀內容做判斷、更不刪除。它們要等使用者**明確說「接續它」**才成為本 session 認領的檔。使用者若選擇「開新流程」，那些檔案維持原狀，**不因為你路過而被清理**（見下方「本 session 的 state 檔以外，一律不碰」）。

**狀態檔存在時（即上面定位到的 `<slug>.json`）：**
```
→ wf-state.sh get <檔>（讀取即校驗；校驗失敗 → 告知使用者 state 已腐壞，不靜默續接）
→ 若 pr 欄位有值 → gh pr view <pr> --json state --jq '.state'
   ├─ MERGED → 自動刪除該檔，告知「PR 已合併，開發週期完成 ✦」
   ├─ CLOSED → 問使用者「PR 已關閉，要重新開 PR 還是放棄？」
   └─ OPEN   → 展示目前狀態（STAGE <N>），問「繼續還是開新流程？」
→ 若 pr 欄位為 null → 展示目前狀態（STAGE <N>），問「繼續還是開新流程？」
```

**狀態檔不存在時：**
```
→ 觸發 A → 問「要開始新的開發流程嗎？請描述需求」
→ 觸發 B → 直接用使用者描述的需求啟動新流程
→ 觸發 C → 告知「當前 branch 找不到未完成的流程，要開始新的嗎？」
```

## 🔴 本 session 的 state 檔以外，一律不碰

**唯一可寫、可刪的 state 檔，是「先定位」步驟認領到的那一個。** 其他 `.claude/workflow-state/` 底下的檔案，無論看起來多像殘留物、PR 查起來多像已合併，都**不屬於本 session**，一律：

- ❌ 不刪除
- ❌ 不修改
- ❌ 不「順手清理」
- ✅ 只在「先定位」流程需要列出候選時**唯讀列名**

> **它們是別的流程的資產，不是你的垃圾。** 判斷「它已經沒用了」不是你的職權——那個流程的 owner（另一個 session、或使用者本人）才有權決定。你眼中的殘留物，可能是別人明天要續接的進度。

**曾經發生的真實錯誤（此規則的由來）：** 一個在 `main` 上啟動新流程的 session，定位不到自己的候選檔，卻看到目錄裡有另一個流程的 state 檔，於是自行 `gh pr view` 查到該 PR 已 MERGED，就套用下方「MERGED → 刪除」規則把它 `rm` 掉了。那個檔案跟它要開發的功能毫無關係。**下方的刪除時機表，主詞永遠是「本 session 認領到的那一個檔」，不是「任何一個 MERGED 的檔」。**

---

**狀態檔刪除時機**（主詞一律是**本 session 認領到的那一個 state 檔**）：

| 條件 | 動作 |
|------|------|
| **本 session 的** state 檔，其 PR 狀態為 `MERGED` | 自動刪除**該檔** |
| 使用者說「放棄這個功能」（指本 session 正在跑的流程） | 自動刪除**該檔** |
| 其他情況 | 一律保留，直到明確完成 |
| **不是本 session 認領到的檔** | **一律不動**——即使它的 PR 已 MERGED、即使它看起來是殘留物 |

刪除前先自問一句：**「這個檔是我在『先定位』步驟認領到的那一個嗎？」** 答案不是斬釘截鐵的「是」，就不要刪。

> 上述刪除只針對 **state 檔（JSON）**，**git branch 本身一律保留**——流程任何階段（含 PR MERGED 後）都不自動執行 `git branch -d/-D`，branch 由使用者自行決定何時刪除。

> 刪除只動「本 session 對應的那一個」state 檔，絕不清整個 `.claude/workflow-state/` 目錄——別的 session 的進度不可被波及。

> **想清理別人的殘留 state 檔？** 那是使用者的決定，不是你的。可以**告知**（「順帶一提，目錄裡有 X 的 state 檔，其 PR 已合併，你可能想清掉」），但**不要代勞**。
