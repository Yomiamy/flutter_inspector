# 執行模式：Quick 模式與批次模式

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
- **超出範圍時：收工重來，不接續升級。** 中途發現超出小修正範圍（多檔設計判斷、新依賴、要動架構）→ 停下告知使用者，把已做的變更保存起來，然後**走完整流程重新開始**：

  ```bash
  git add -A && git commit -m "WIP: 超出 quick 範圍，轉完整流程"   # 或 git stash -u
  ```

  接著照 STAGE 1 的規則從 `origin/main` 建新的 worktree + branch，在新工作區取回變更（`git cherry-pick` 該 WIP commit，或 `git stash pop`），並刪掉 quick 的 state 檔。

  **為什麼不做「就地升級」**：quick 直接在原 repo checkout 該分支，所以升級時分支既存在又被佔用——`git worktree add -b <branch>` 報 `already exists`、`git worktree add <path> <branch>` 報 `already used by worktree`，**兩種寫法都 fatal**（2026-08-25 實測）。而且 `git worktree add` 不搬未 commit／staged／untracked 的變更。更根本的是，觸發升級的理由通常是「發現需要設計判斷」，而就地升級會落在 STAGE 2，等於**跳過 0a/0b**，在沒有 spec/plan 的情況下做一件已知需要計畫的事。收工重來反而走完整規劃。
- Token Budget Gate 照常適用（`> 150k` 切 session 規則不變；`100k ≤ context ≤ 150k` 的強制 MCP 委派不適用於 Quick 的直接實作步驟，Quick 模式本來就不委派 implementer）。
- ⚠️ **`quick` + `balanced` 無作用**：quick 不拆任務（無 task 迴圈可關）、stage 是自由標籤（不匹配 `0b`/`2`/`4`），腳本會明示短路回 `strict`（`scripts/wf-state.sh` 的 `should_pause()`）。只有 `autonomous` 對 quick 有實效——關掉它唯一的 PR 暫停點。使用者若對 quick 指定 `balanced`，**直接告知無差別**，不要假裝有效果。

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
依該項的類型決定起始 stage（各自 issue / worktree / branch / PR）
  ├─ 描述項（如 "§P4 ..."）      → 跑 0a→4，需產規格與計畫
  ├─ #issue 項（如 "#42"）       → 跳過 0a/0b，從 STAGE 1 起跑
  │                                （規格已在 issue 內，重跑會重複規劃甚至重開 Issue）
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

```text
→ .claude/workflow-state/.batch-*.json
   ├─ 0 個 → 告知「找不到進行中的批次」，不自行猜測
   ├─ 1 個 → 讀取，batch-next 取下一項，繼續
   └─ ≥2 個 → 列出讓使用者選（腳本本身也會 die 要求明示）
```

> ⚠️ 批次檔與「本 session 的 state 檔以外，一律不碰」不衝突——批次檔是**使用者明確建立的佇列**，不是別的流程的 workflow state。但同樣的紀律適用：**不因為看到某個批次檔就自行接續它**，要使用者說「繼續批次」才動。
