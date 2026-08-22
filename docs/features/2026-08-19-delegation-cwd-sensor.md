# 委派工作目錄強制：Guide → Sensor（§4）

> 狀態：規格（STAGE 0a）｜日期：2026-08-19
> 來源：`docs/brainstorm/2026-08-23-workflow-brainstorm.md` §4「把 Guide 升級成 Sensor（Böckeler）」、
> `docs/architecture/2026-08-21-wf-state-harness-guardrail.md`「同構的第二個弱點：委派的工作目錄約束」

---

## 1. 問題陳述

### 1.1 一句話

委派子進程的工作目錄約束，目前只存在於一段**寫給另一個 LLM 看的 prompt 文字**裡，沒有任何執行層強制力；子進程若在主 repo 而非 worktree 動手，整條防線**零反應、零告警**。

### 1.2 靜默失效的具體路徑

依 Böckeler 的 `Agent = Model + Harness` 框架：**Guide**（前饋，動手前引導）可以被忽略，**Sensor**（回饋，動手後偵測）才具確定性。現況的每一層都落在 Guide 側：

| 層 | 現況 | 為何擋不住 |
|:---|:---|:---|
| 傳輸層 | `mcp__gemini-cli__ask-gemini` | **呼叫介面沒有 cwd 參數**。子進程實際在哪個目錄動手，呼叫端無法決定。 |
| 約束層 | `.claude/agents/implementer.md:28-35` 的「工作目錄：<worktree 絕對路徑>／🔴 邊界：不得存取或修改此目錄以外的任何檔案」 | 純文字，寫在派發 prompt 第一段。對子進程是道德勸說，不是強制。 |
| 狀態機層 | `wf-state.sh` 全部 guard（schema、stage 轉移表、暫停棘輪、任務數校驗） | 它校驗的是 **state JSON 內容的合法性**，管轄範圍不含「檔案實際寫在哪顆目錄」。子進程寫錯目錄時，所有 guard **全部通過**。 |
| 緩解層 | `SKILL.md` 委派紀律第 3 條：主對話跑 `git status` / `git log` 確認 | 屬**偵測**不屬預防，且依賴「主對話記得跑」——這正是本專案已知不可靠的假設（與 Gap 2.6 同型）。 |

失效實況（完整路徑）：

```
主對話派發任務 → prompt 第一段寫了 worktree 絕對路徑
  → 子進程忽略該段（或誤解、或 cwd 本來就在主 repo 而它沒切）
  → 在 /Users/yomiry/StudioWorkspace/flutter_inspector 主 repo 直接改檔、git add、git commit
  → 子進程回報「已完成、已 commit」
  → wf-state.sh 所有 guard 通過（state JSON 完全合法）
  → 主對話（若沒跑 git status）驗收通過，推進下一任務
  → 汙染累積在錯誤的 branch 上，直到 STAGE 4 建 PR 時才可能發現，或永遠不發現
```

**這與 Gap 2.6 結構完全同構**：Gap 2.6 是「根本沒呼叫腳本」，本問題是「約束只寫在 prompt 裡」——兩者的 Guardrail 反應都是「無」，正確對策層級都是 hook 攔截。Gap 2.6 已用 `.claude/hooks/wf-guard-stage-check.sh` 成功解掉，有現成範式可抄。

### 1.3 為何現況不可接受

1. **破壞 worktree 隔離的整個前提**。多 workflow 並行的隔離 key 就是「每個 workflow 跑在自己的 worktree」。這條前提一旦可被單一子進程無聲打破，並行安全性從「有保證」降級為「碰運氣」。
2. **汙染的發現成本遠高於預防成本**。錯誤 commit 落在主 repo 的當前 branch 上，要清理需要 reset/cherry-pick，且若期間有其他正常 commit 交錯，清理本身就是風險操作。
3. **零告警使得問題無法被統計**。目前無法回答「這半年委派越界過幾次」，因為沒有任何一層會留下紀錄。

---

## 2. 使用者故事

- **US-1（預防越界寫入）**：身為開發者，當委派子進程在錯誤目錄（主 repo 而非 worktree）動手時，系統必須在**執行層**察覺並讓我知道，而不是靠我記得手動跑 `git status`。

- **US-2（不誤殺正常委派）**：身為開發者，當委派的 cwd 完全正確時，包括所有必然讀寫 worktree 外部路徑的正常操作（git 內部檔、pub cache、Flutter SDK），系統必須放行，不得有任何干擾。

- **US-3（越界時給出可執行的修復路徑）**：身為開發者，當系統偵測到越界時，錯誤訊息必須明確指出「哪個路徑越界了」與「怎麼修」，而不是丟一個布林失敗。

- **US-4（不在 workflow 中時完全透明）**：身為開發者，當我在主 repo 做日常開發、或跑一個與 workflow 無關的獨立委派時，這層防護必須自動判定不適用並放行，絕不影響日常。

- **US-5（越界事實可稽核）**：身為維護者，我需要越界事件留下可查的紀錄，以便判斷這層防護是否真的在攔到東西，或只是擺設。

---

## 3. 三個定案問題的結論與論證

### 3.1 問題① 攔截點：路 A（攔 prompt 內容）vs 路 B（委派後驗證）

原始文件的對策欄寫的是「hook 攔截 / 委派後驗證」——**兩個選項並列，從未拍板**。本規格拍板如下。

**結論：兩者併用，但職責明確切分，且 B 是必要條件、A 是選配的成本優化。**

論證回到 Guide/Sensor 框架：

| | 路 A：PreToolUse 攔 prompt 內容 | 路 B：PostToolUse 驗證檔案系統 |
|:---|:---|:---|
| 檢查對象 | **派發者有沒有照規矩寫 prompt** | **檔案系統實際被寫成什麼樣** |
| 框架歸類 | 仍是 **Guide 的自動化檢查**——它驗證的是那段道德勸說「有沒有被寫進去」，不是「有沒有被遵守」 | 真 **Sensor**——看的是客觀事實，子進程無法繞過 |
| 子進程能否繞過 | **能**。prompt 寫得再完美，子進程照樣可以無視 | **不能**。檔案落在哪就是哪 |
| 時機 | 事前預防（派發前擋下） | 事後偵測（髒已經寫下去） |
| 誤判成本 | **高**——擋掉的是正常委派，直接中斷流程 | **低**——只是多報一次，不阻斷已完成的動作 |

**為何 B 不可省**：路 A 完全無法達成本規格的核心目的。§4 的整個論點就是「那段 prompt 文字是 Guide，需要的效果需要 Sensor」——若只做 A，我們得到的是「一個檢查 Guide 存在性的 Guide」，遞迴地沒有解決任何事。**只做 A 等於把問題換個位置擺著。**

**為何 A 仍值得做（且不是重複工）**：A 與 B 攔的是**兩種不同的失效原因**，不是同一件事的兩次檢查：

- A 攔「**派發者失誤**」：主對話忘了在 prompt 加工作目錄段、或寫了過期／錯誤的路徑。這種失誤在派發前就能確定判定，成本是零次無效委派。
- B 攔「**子進程失誤**」：prompt 完全正確，但子進程沒照做。這種失誤在派發前**不可能**被偵測，只能事後看檔案系統。

若省掉 A，派發者失誤要等到 B 才被抓到，代價是一次完整的無效委派（token + 時間 + 可能已產生的髒檔案）。若省掉 B，子進程失誤永遠抓不到。**兩者的交集為空，因此不是重複工。**

**優先序**：B 是 MUST，A 是 SHOULD。若實作階段需要分批，先做 B。理由：只有 B 能兌現「Guide → Sensor」這個標題；A 只是省下無效委派的成本優化。

**B 的偵測範圍**：委派回來後，檢查**主 repo 與所有非目標 worktree** 是否出現非預期的 dirty 檔案或新 commit。判準是「當前 workflow 的目標 worktree 以外，出現了本次委派造成的變動」。

**B 的定位誠實標註**：B 是偵測不是預防，髒已經寫下去了。但它的價值在於**確定性**——它把「主對話記得跑 git status」這個不可靠的人為步驟，換成無法被跳過的執行層檢查。從「可能發現」變成「必定發現」，這就是 Guide 升級成 Sensor 的全部意義。預防在物理上不可得（MCP 沒有 cwd 參數），能確定性偵測就是本問題的天花板。

### 3.2 問題② 白名單邊界

**問題本身**：worktree 的 `.git` 是一個指向主 repo 的 gitdir 檔案：

```
<worktree>/.git → gitdir: <主repo>/.git/worktrees/<name>
```

因此**任何 git 操作都必然讀寫 worktree 外的路徑**。若判準是「路徑必須以 worktree 前綴開頭」，**每一個 git 指令都會被誤擋，包含 cwd 完全正確的那些**——這會讓這層防護在上線第一天就被關掉。

**結論：白名單必須明列，且判準是「越界寫入」而非「越界存取」。**

兩個層次的收斂：

1. **只管寫入，不管讀取**。讀取 worktree 外的檔案（讀 SDK 原始碼、讀套件源碼、讀主 repo 的參考實作）是正常且必要的行為，一律不視為越界。**唯有寫入才構成汙染。** 這一刀砍掉絕大多數的誤判來源。
2. **寫入路徑再套白名單**。

**白名單（寫入允許）**：

> 🔴 **原則：白名單以「解析出來的實際路徑」為準，禁止硬編碼假設的標準路徑。** 下表的每一列都標明取得方式；凡標為「動態解析」者，實作時必須實際查出來，不可寫死。

| 類別 | 路徑 | 取得方式 | 理由 |
|:---|:---|:---|:---|
| git 內部 | `<主repo>/.git/**` | `git rev-parse --git-common-dir` | worktree 的所有 git 操作（add/commit/checkout）都經由此處的 `worktrees/<name>/` 與共用 objects/refs |
| git 內部 | `<worktree>/.git`（gitdir 指標檔本身） | `git rev-parse --git-dir` | worktree 建立時寫入 |
| git 全域設定 | `~/.gitconfig`、`~/.config/git/**` | 固定 | `git commit` 可能觸碰；`gh` 認證流程亦然 |
| SSH known_hosts | `~/.ssh/known_hosts` | 固定 | `git fetch/push` 首次連線寫入 |
| Dart/Flutter 套件快取 | `$PUB_CACHE`，未設定時回退 `~/.pub-cache` | **動態解析**（先讀環境變數） | `flutter pub get` / `dart pub get` 必寫 |
| Flutter/Dart SDK | SDK 根目錄（本機為 fvm 管理） | **動態解析**：`dirname $(dirname $(readlink -f $(which flutter)))`，另納入 `$FLUTTER_ROOT` 與 `~/fvm/**` | `flutter` / `dart` 指令會寫 SDK 內的 cache 與版本標記 |
| 工具設定 | `~/.dart-tool/**`、`~/.flutter`、`~/.dartServer/**` | 固定 | Flutter/Dart 工具鏈的使用者層設定與 analytics 標記 |
| gh CLI | `~/.config/gh/**` | 固定 | `gh` 指令的 hosts/設定 |
| 暫存 | `$TMPDIR/**`、`/tmp/**`、`/private/tmp/**`、scratchpad 目錄 | **動態解析**（`$TMPDIR`） | 工具鏈與 agent 的暫存輸出，本來就不該視為專案汙染 |
| npm/node（若使用） | `~/.npm/**`、`~/.cache/**` | 固定 | MCP 工具鏈本身的執行痕跡 |

**已實測確認的環境事實（2026-08-19）**：

1. **Flutter/Dart 走 fvm，不在標準 SDK 路徑**：
   - `which flutter` → `/Users/yomiry/fvm/default/bin/flutter`
   - `which dart` → `/Users/yomiry/fvm/default/bin/dart`
   - 專案內有 `.fvm/` symlink 指向該處。
   - **若白名單只列 `~/.pub-cache`，`flutter pub get` / `dart analyze` 仍會被擋**——SDK 目錄本身在執行時會被寫入（cache、版本標記）。這是原始需求清單漏列的一項，也是本規格最容易踩的誤判來源。
   - 因此判準不是「列出已知的 SDK 路徑」，而是「**從 `which` 結果反解出 SDK 根目錄**」；`~/fvm/**` 與 `$FLUTTER_ROOT` 作為補充覆蓋，不作為唯一依據。

2. **`PUB_CACHE` 未被覆寫**：本機 `PUB_CACHE` 未設定，實際落在 `~/.pub-cache`（已確認存在）。但白名單**必須容忍 `PUB_CACHE` 被設定的情況**，先讀環境變數、未設定才回退預設值。硬編碼 `~/.pub-cache` 在 CI 或他人機器上會直接誤殺。

3. **委派管道確認可用**：`gemini-cli` 已在全域 `~/.claude.json` 的 `mcpServers` 中啟用（專案無 `.mcp.json`）。**本弱點是實際存在的可觸發路徑，不是理論風險。**

**黑名單（明確視為越界）**：白名單以外的一切寫入，其中最關鍵的是：

- `<主repo>/` 底下**除 `.git/` 以外**的任何工作區檔案（`lib/`、`test/`、`docs/`、`.claude/`、根目錄設定檔）
- 其他 worktree 的工作區檔案
- 家目錄下未列於白名單的任何位置

**白名單維護原則**：白名單只增不減，且新增必須有具體的誤判事證（某次正常委派被擋）。禁止「預防性」新增——那會讓白名單膨脹到失去意義。

### 3.3 問題③ False positive 防護清單

**這是攔截層，寫錯的後果是擋掉正常委派，比不擋更糟。** 對照 `wf-guard-stage-check.sh` 已驗證的防護設計，新機制必須具備下列每一條放行條件（任一條命中即立即放行，不做後續判斷）：

| # | 放行條件 | 理由 |
|:---:|:---|:---|
| P-1 | payload 解析失敗（非 JSON、空輸入） | 不能因為 hook 自己讀不懂輸入就阻斷使用者的動作 |
| P-2 | 被攔的工具不是委派管道（非 `mcp__gemini-cli__ask-gemini`） | 目標外的呼叫一律不管 |
| P-3 | 找不到任何 workflow state 檔 | 非 workflow 情境（日常開發、獨立委派）完全透明 |
| P-4 | 當前 branch 對不上任何 state 檔 | 防止「另一個 worktree 正在跑 workflow」時誤殺當前分支的動作 |
| P-5 | state 檔存在但 stage 不在會委派的階段 | 只有 STAGE 2（實作）會委派 implementer；其他階段不套用 |
| P-6 | 當前不在 worktree 中（state 檔顯示尚在 STAGE 0a/0b，worktree 未建立） | 此時「worktree 外」的概念不成立，無從判定越界 |
| P-7 | 寫入路徑命中白名單（§3.2） | 正常的 git / pub / SDK 行為 |
| P-8 | 變動是讀取而非寫入 | 只管寫入（§3.2 第 1 層收斂） |
| P-9 | 主 repo 的 dirty 檔案在委派**之前**就已存在 | 必須用「委派前 vs 委派後」的差集判定，不能用「委派後主 repo 是否 dirty」的絕對值——否則使用者事先未 commit 的工作會被誤判成子進程越界 |
| P-10 | 變動檔案落在 `.gitignore` 範圍內（build 產物、`.dart_tool/`、`coverage/`） | 非追蹤檔案不構成 repo 汙染 |
| P-11 | hook 腳本自身發生任何未預期例外 | fail-open：hook 壞掉不能連帶讓整條 workflow 不能動 |

**兩條額外的設計硬規則**：

- **P-9 是最容易寫錯的一條**。`wf-guard-stage-check.sh` 沒有這個問題（它讀的是 state 檔的靜態值），但本機制讀的是會隨時間變動的檔案系統狀態，**必須做 before/after 差集**。用絕對值判定必定誤殺。
- **阻擋語意的分層**：路 A（PreToolUse）阻擋時用 `sys.exit(2)`——BUG-1 教訓：PreToolUse 只有 exit 2 具阻擋力，exit 1 屬 non-blocking、動作照跑。路 B（PostToolUse）動作已完成，阻擋無意義，其輸出應為**高可見度告警 + 稽核紀錄**，不試圖用 exit code 回捲已發生的事。

---

## 4. 驗收條件

每條均可寫成機械可驗證的測試情境。

### 路 B（Sensor，MUST）

- **AC-B1**：委派前主 repo 為 clean，委派期間子進程在主 repo 工作區寫入檔案 → 委派回來後必定產生越界告警，且告警內容列出**具體的越界檔案路徑**。
- **AC-B2**：委派前主 repo 為 clean，子進程完全在目標 worktree 內動手（含 `git add` / `git commit`）→ 必定不告警。
- **AC-B3**：委派期間僅執行 `flutter pub get`（寫入 `~/.pub-cache`）與 `flutter --version`（寫入 fvm SDK 快取）→ 必定不告警。
- **AC-B4**：委派前主 repo 已有 dirty 檔案（使用者自己的未 commit 工作），委派期間子進程未新增任何主 repo 變動 → 必定不告警（驗證 P-9 差集判定）。
- **AC-B5**：越界時，事件寫入可稽核的紀錄（時間、workflow branch、越界路徑清單）。
- **AC-B6**：不在任何 workflow 中（無 state 檔）時委派 → 機制完全不啟動，無輸出、無效能可感知差異。
- **AC-B7**：hook 腳本內部拋出例外 → 委派結果不受影響（fail-open 驗證）。

### 路 A（Guide 自動化檢查，SHOULD）

- **AC-A1**：STAGE 2 期間，派發 prompt **未含**工作目錄宣告 → 呼叫被阻擋（exit 2），stderr 明示缺少的段落與正確格式。
- **AC-A2**：派發 prompt 含工作目錄宣告，但路徑**不等於**當前 state 檔對應的 worktree → 呼叫被阻擋，stderr 同時列出「prompt 中的路徑」與「應為的路徑」。
- **AC-A3**：派發 prompt 含正確的工作目錄宣告 → 放行。
- **AC-A4**：state 檔 stage 不是 2（不會委派 implementer 的階段）→ 放行（P-5）。
- **AC-A5**：當前 branch 無對應 state 檔 → 放行（P-4）。
- **AC-A6**：呼叫的不是 `mcp__gemini-cli__ask-gemini` → 放行（P-2）。

### 共同

- **AC-C1**：既有的 `wf-guard-stage-check.sh` 行為完全不受影響（回歸驗證，Never break userspace）。
- **AC-C2**：白名單（§3.2）中的每一類路徑，各有一個對應的放行測試情境。

---

## 5. 範圍邊界

### In scope

- 委派管道 `mcp__gemini-cli__ask-gemini` 的工作目錄越界偵測。
- 越界判準的白名單定義與 false positive 防護。
- 越界事件的告警與稽核紀錄。
- 派發 prompt 中工作目錄宣告的存在性與正確性檢查（路 A）。

### Out of scope

- **`git push` / `gh pr create` 等對外動作的委派管制**。SKILL.md「不委派的硬規則」已規定這些動作由主對話自己執行且須先過對應暫停點。本機制**不以「這是 push 所以擋」為判準，只以「cwd／路徑是否越界」為判準**——cwd 正確的 git 操作（包含 push）一律放行。「該不該委派 push」由 STAGE 4 暫停點管，兩層各管各的，不重疊、不互相補位。
- **`git pull` 拉進非預期 merge 的問題**。那是 git 使用紀律，不歸 cwd hook 管。
- **修改 `wf-state.sh`**。它的管轄範圍本來就不含檔案位置；往裡面堆校驗對本問題無效（這正是 §1.2 表格第三列的結論）。
- **子進程逾時控制**。MCP 呼叫無法帶 `--print-timeout` 是另一個已知限制，與 cwd 無關。
- **改造 MCP 委派管道使其支援 cwd 參數**。上游工具介面不在本專案控制範圍內；若上游未來支援，本機制的路 A 可退役，路 B 仍應保留（子進程仍可能在 cwd 內用絕對路徑寫出界）。
- **其他 agent（reviewer / verifier / responder）的路徑管制**。它們不走 MCP 委派、且以讀取為主，不構成本問題。

---

## 6. 風險與未決事項

### 風險

| # | 風險 | 影響 | 緩解方向 |
|:---:|:---|:---|:---|
| R-1 | 白名單漏列導致誤殺正常委派 | **最高**——會讓機制在上線初期就被關掉，等於白做 | 路 B 先以「僅告警、不阻斷」上線；累積實測後再考慮升級強度。白名單只增不減。 |
| R-2 | before/after 差集的快照時機不準（委派期間使用者自己也在改檔） | 中——產生假告警 | 快照範圍限縮在「git 追蹤的檔案 + 未追蹤但非 ignore 的檔案」，並在告警文字中標明「若這是你自己的改動請忽略」 |
| R-3 | PostToolUse hook 的執行成本（每次委派回來都要掃檔案系統） | 低 | 只掃主 repo 與已知 worktree 的 `git status --porcelain`，不做全檔案系統遍歷 |
| R-4 | 路 A 的 prompt 字串比對過於死板（格式微調就誤擋） | 中 | 比對「是否含目標 worktree 絕對路徑字串」，不比對整段格式 |
| R-5 | 主 repo 在 STAGE 0a/0b 就是合法工作目錄（worktree 尚未建立） | 中——此時任何主 repo 寫入都會被誤判 | P-6：worktree 未建立時機制不啟動 |
| R-6 | ~~worktree 的 `.git` 實際格式未實測~~ → ✅ **已於 2026-08-19 實測確認，假設成立**（見 U-6） | 已解除 | 判準維持動態取得，不解析 `.git` 檔內容 |

### 未決事項

- **U-1｜路 B 的告警強度**：✅ **已定案（2026-08-19，使用者裁決）＝僅 stderr 告警 + 稽核紀錄，不阻斷流程。** 理由：R-1（白名單漏列）是最高風險，阻斷式上線會在漏列時直接卡死流程，等於逼使用者關掉整個機制。僅告警則漏列只造成一次假警報，機制得以存活並累積實測資料。日後是否升級為阻斷，依實際誤判率再議——升級屬另案，不在本次範圍。
- **U-7｜路 A／路 B 的實作範圍**：✅ **已定案（2026-08-19，使用者裁決）＝A 與 B 同批實作，同一個 PR 落地。** 兩者阻擋語意刻意不同且自洽：路 A 於派發前可確定判定，採 `sys.exit(2)` 阻斷；路 B 事後偵測，只告警不阻斷（見 U-1）。
- **U-2｜稽核紀錄的位置與生命週期**：✅ **已定案並實作**＝`.claude/workflow-state/cwd-violations.log`，append-only JSON lines（欄位：`ts`／`branch`／`worktree`／`paths`／`new_commits`）。與 state 檔同目錄，跟著 workflow 生命週期走，不另建目錄、不做輪替。該目錄已在 `.gitignore` 內，紀錄天然不進版控。寫入失敗一律吞掉不影響流程。
- **U-3｜路 A 是否需要在 Fallback 模式下運作**：MCP 不可用時 implementer 退回自行執行，此時無 MCP 呼叫可攔，路 A 天然不觸發。路 B 是否仍應涵蓋 Fallback 情境下的越界？（傾向：應涵蓋，因為 B 看的是檔案系統，與傳輸層無關；但觸發時機需另定。）
- **U-4｜多 worktree 並行時的目標判定**：當本機同時存在多個 workflow worktree，路 B 如何確定「本次委派的目標 worktree」？（傾向：以當前 branch 對應的 state 檔為準，即 P-4 的同一套判定邏輯。）
- **U-6｜worktree `.git` 格式**：✅ **已實測（2026-08-19，於 worktree `flutter-inspector-134-delegate-cwd-sensor`）**，結果全部符合原假設：
  - worktree 的 `.git` 是**檔案**（113 bytes，非目錄），內容為單行 `gitdir: <主repo>/.git/worktrees/<name>`。
  - `git rev-parse --git-dir` → `<主repo>/.git/worktrees/<name>`
  - `git rev-parse --git-common-dir` → `<主repo>/.git`
  - **兩者不相等**，故 P-6「以 `--git-dir != --git-common-dir` 判定身處 worktree」成立。
  - 兩個路徑**都落在主 repo 的 `.git/` 底下**，印證 §3.2「任何 git 操作都必然寫 worktree 外路徑」——白名單非有不可。
  - 結論不變：仍一律用 `git rev-parse` 動態取得，**不解析 `.git` 檔內容**（實測只是確認假設，不是改用硬編碼的理由）。
- **U-5｜白名單的表達位置**：✅ **已定案並實作**＝寫死在 hook 腳本的 `whitelist_roots()` 內，不抽設定檔、不做 loader。目前只有一個消費者。
- **U-8｜掛載設定是否進版控**：✅ **已定案（2026-08-19，使用者裁決）＝不進版控。** 實查確認 `.claude/settings.local.json` 從未被 git 追蹤，且 Gap 2.6 的修復 commit `9a40c96` 同樣只 commit hook 腳本、未 commit 掛載——沿用既有慣例。三個理由：(1) 該檔是單一 JSON 物件而非 append-only 清單，進版控會讓開發者互相覆蓋，是永久的 merge conflict 來源；(2) 本 repo 為 public，該檔 225 條 permissions 中有 29 條含絕對路徑，會洩漏機器佈局與其他專案名稱（已確認無 token／密鑰）；(3) 協作者真正需要的只有那 8 行掛載，而非他人的個人權限清單。**替代方案**：掛載片段寫在 hook 腳本首部註解，可直接複製。

---

## 7. 成功的定義

一句話：**「委派子進程在錯誤目錄動手」這件事，從『只有主對話記得跑 git status 才會發現』變成『必定被發現』。**

> **範圍限定**：此處的「必定被發現」，效力範圍是**主 repo 與已知 git worktree**。實作建立在 `git status` 之上，
> 寫入不屬於任何 git worktree 的位置（其他專案、家目錄普通檔案）偵測不到。
> 這不是實作缺陷而是刻意的成本取捨——fs-level 觀察（fswatch／eBPF）的複雜度與誤判率遠超本問題的嚴重度。
> 實務上委派子進程的越界目標幾乎必然是主 repo（那正是 §1.2 描述的失效路徑），該情境已完整涵蓋。

不追求「必定被阻止」——MCP 介面沒有 cwd 參數，物理上做不到事前阻斷子進程的實際行為。確定性偵測就是本問題的天花板，而從「可能發現」到「必定發現」，正是 Guide 升級成 Sensor 的全部內容。
