# Token Budget Gate（context 用量控管）

這是長流程（6 stages + 每任務暫停）的存活機制。**每個 stage 切換前、以及 STAGE 2 每個任務完成後**，評估主對話 context 用量並依下表行動：

| Context 用量 | 行為 |
|---|---|
| < 60k | 正常流程，不做任何事 |
| 60–100k | ⚠️ 提示使用者「context 已 <用量>，建議精簡」。委派 agent 時要求只回報摘要，不回貼完整 diff / 檔案內容 |
| 100–150k | ⚠️ 完整流程且 MCP 可用時：implementer / publisher 強制走 MCP 委派（不自行讀大檔），主對話只保留高層判斷。**MCP 不可用時走 Fallback 或按下方 `> 150k` 規則切 session，不得因此卡住等待 MCP 恢復**。Quick 模式本無 implementer 委派，此行不適用於其直接實作步驟 |
| > 150k | ⛔ **強制 checkpoint，主動切 session** — 走下方「context 超標切 session 閉環」 |

## context 超標切 session 閉環

這是本 workflow 相對其他系統的關鍵優勢：**已有 per-branch state 檔，所以 Token Gate 撞牆時不會丟失進度**。

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
