#!/usr/bin/env bash
# wf-state.sh — gen-dev-workflow 的 state machine。
# 所有 workflow state 檔的讀寫都必須經過這支腳本；guard 在程式裡，不在文件裡：
#   1. schema 校驗 + 原子寫入（tmp + mv），手寫/半寫壞檔進不了磁碟
#   2. sequence 模式的 stage 轉移合法性檢查（非法跳段直接 exit 1）
#   3. 暫停點棘輪：stage-done / task-done 之後 awaiting_confirmation=true，
#      未帶 --confirmed 的 advance 一律拒絕——跳過暫停點需要「明示旗標」這個蓄意動作
set -euo pipefail

STATE_DIR="${WF_STATE_DIR:-.claude/workflow-state}"
SCHEMA_VERSION=1

die() { echo "wf-state: $*" >&2; exit 1; }
command -v jq >/dev/null || die "需要 jq"

usage() {
  cat <<'EOF'
用法：
  wf-state.sh init [--mode sequence|jump|quick] [--stage <S>] [--branch <branch>]
                   [--pause-level strict|balanced|autonomous] [--set k=v ...]
      建新 state。無 --branch → .pending-<wf-id>.json；有 --branch → <branch-slug>.json
      --pause-level 預設 strict（＝原行為）。balanced 只停 0b/2/4；autonomous 全不停
  wf-state.sh promote <pending-檔> --branch <branch> [--dest <state-dir>]
      pending → <branch-slug>.json（STAGE 1 建好 worktree 後，--dest 指向新 worktree 的 state dir）
  wf-state.sh get <檔>                    校驗後輸出 JSON
  wf-state.sh set <檔> k=v [k=v ...]      更新欄位（不可改 stage/awaiting_confirmation）
  wf-state.sh stage-done <檔> <stage>     標記 stage 完成，進入等待使用者確認
      sequence 模式：<stage> 須等於目前 stage；quick/jump 不受限（自由標籤）
  wf-state.sh task-done <檔> <n>          任務完成（記入 completed_tasks，進入等待確認）
      sequence 模式：僅能在 STAGE 2 執行
  wf-state.sh confirm <檔>                使用者已確認（清除等待旗標，stage 不變）
  wf-state.sh advance <檔> <next> --confirmed
      推進 stage。等待確認中且未帶 --confirmed → 拒絕；sequence 模式非法轉移 → 拒絕
<檔> 可為路徑，或相對 $STATE_DIR 的檔名。

批次佇列（多個獨立 workflow 依序執行，每項各自 worktree/branch/PR）：
  wf-state.sh batch-init <項目> [<項目> ...] [--pause-level <L>]
      建 .batch-<id>.json。項目為自由字串（需求描述或 #issue）
  wf-state.sh batch-get [<檔>]             輸出批次 JSON（省略檔名 → 自動找唯一批次）
  wf-state.sh batch-next <檔>              輸出下一個待跑項目（全跑完 → 輸出 DONE）
  wf-state.sh batch-done <檔> [--pr <url>] 標記當前項目完成，游標移到下一項
  wf-state.sh batch-fail <檔> [--note <s>] 標記當前項目失敗，游標移到下一項
  wf-state.sh batch-abort <檔>             中止整個批次（刪除批次檔，不影響已建的 branch/PR）
EOF
  exit 1
}

resolve() { case "$1" in */*) echo "$1" ;; *) echo "$STATE_DIR/$1" ;; esac; }

validate() {
  jq -e '
    (.schema_version == 1) and
    (.workflow_id | type == "string") and
    (.stage | type == "string") and
    (.mode == "sequence" or .mode == "jump" or .mode == "quick") and
    (.completed_tasks | type == "array") and
    (.completed_tasks | all(type == "number")) and
    (.total_tasks == null or (.total_tasks | type == "number")) and
    (.pause_level == null or .pause_level == "strict" or .pause_level == "balanced" or .pause_level == "autonomous") and
    (.awaiting_confirmation | type == "boolean")
  ' "$1" >/dev/null 2>&1 || die "state 檔校驗失敗：$1"
}

# claim_new <目標檔>  排他佔位：檔案已存在就失敗，避免「檢查存在→mv」中間有並發窗口
claim_new() {
  mkdir -p "$(dirname "$1")"
  ( set -C; : >"$1" ) 2>/dev/null || die "已存在：$1（不覆蓋既有流程）"
}

# atomic_write <目標檔>  （stdin 收 JSON）
atomic_write() {
  local f="$1" tmp
  mkdir -p "$(dirname "$f")"
  tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
  jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
  ( validate "$tmp" ) || { rm -f "$tmp"; exit 1; }   # 子 shell 隔離 validate 的 die，確保 tmp 必被清掉
  mv "$tmp" "$f" || { rm -f "$tmp"; die "搬移暫存檔失敗，清理暫存檔 $tmp"; }
}

# jq 值解析：null / 數字 / 布林原樣，其餘當字串
jq_val() {
  if [[ "$1" =~ ^-?[1-9][0-9]*$ || "$1" == "0" || "$1" == "-0" ]]; then
    echo "$1"
  elif [[ "$1" == "true" || "$1" == "false" || "$1" == "null" ]]; then
    echo "$1"
  else
    jq -n --arg v "$1" '$v'
  fi
}

slugify() { echo "${1//\//-}"; }

legal_transition() {
  case "$1->$2" in
    "0a->0b"|"0b->1"|"1->2"|"2->3"|"3->4"|"3->2"|"4->done"|"4->5"|"5->4"|"5->5"|"4->6"|"5->6"|"6->done"|"reviewer->responder"|"responder->reviewer"|"reviewer->publisher") return 0 ;;
    *) return 1 ;;
  esac
}

batch_validate() {
  jq -e '
    (.schema_version == 1) and
    (.batch_id | type == "string") and
    (.cursor | type == "number") and
    (.pause_level == "strict" or .pause_level == "balanced" or .pause_level == "autonomous") and
    (.items | type == "array") and (.items | length > 0) and
    (.items | all(.task | type == "string"))
  ' "$1" >/dev/null 2>&1 || die "批次檔校驗失敗：$1"
}

# batch_write <目標檔>（stdin 收 JSON）——與 atomic_write 同構，但走 batch schema
batch_write() {
  local f="$1" tmp
  mkdir -p "$(dirname "$f")"
  tmp="$(mktemp "$(dirname "$f")/.wf-tmp.XXXXXX")"
  jq . >"$tmp" || { rm -f "$tmp"; die "非法 JSON，寫入中止"; }
  ( batch_validate "$tmp" ) || { rm -f "$tmp"; exit 1; }
  mv "$tmp" "$f" || { rm -f "$tmp"; die "搬移暫存檔失敗，清理暫存檔 $tmp"; }
}

# resolve_batch [檔]  省略時自動定位唯一批次檔；0 個或 ≥2 個都要求明示
resolve_batch() {
  if [ -n "${1:-}" ]; then resolve "$1"; return; fi
  local found count
  found="$(find "$STATE_DIR" -maxdepth 1 -name ".batch-*.json" 2>/dev/null)"
  count="$(printf '%s' "$found" | grep -c . || true)"
  case "$count" in
    0) die "找不到批次檔（$STATE_DIR/.batch-*.json）。先跑 batch-init" ;;
    1) printf '%s\n' "$found" ;;
    *) die "找到多個批次檔，請明示要操作哪一個："$'\n'"$found" ;;
  esac
}

# should_pause <state 檔> <gate>  回傳該暫停點是否要停（true/false）
# gate = stage 值（0a/0b/1/2/3/4）或字面 "task"（STAGE 2 任務間）
# 單一判定來源：strict 全停、balanced 只停架構關卡、autonomous 全不停。
# pause_level 缺失或值異常一律退回 strict——壞掉的方向偏向「多停一次」，不偏向「少停一次」。
should_pause() {
  local level mode
  level="$(jq -r '.pause_level // "strict"' "$1")"
  mode="$(jq -r '.mode' "$1")"
  # balanced 的關卡集（0b/2/4）是 sequence 專屬的 stage 值，quick 的 stage 是自由標籤、
  # 且無 task 迴圈——對 quick 套 balanced 只會落空退化。明示短路，別讓它看似生效。
  if [ "$mode" = "quick" ] && [ "$level" = "balanced" ]; then
    level="strict"
  fi
  case "$level" in
    autonomous) echo false ;;
    balanced)
      # 架構關卡才停：0b 計畫確認、2 實作整體完成、4 PR 發布前。task 迴圈不停。
      case "$2" in
        0b|2|4) echo true ;;
        *) echo false ;;
      esac
      ;;
    strict|*) echo true ;;
  esac
}

apply_sets() { # $1=json, 之後 k=v...；回傳更新後 json
  local json="$1"; shift
  local kv k v
  for kv in "$@"; do
    if [[ "$kv" != *=* ]]; then
      die "參數格式錯誤：'$kv'。必須為 k=v 格式"
    fi
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      pause_level)
        case "$v" in
          strict|balanced|autonomous) ;;
          *) die "不可設定無效的 pause_level 值：'${v}'（允許值：strict, balanced, autonomous）" ;;
        esac
        ;;
      spec|plan|branch|issue|pr|total_tasks|interrupted_by) ;;
      *) die "不可透過 set 修改欄位：${k}（stage 用 advance、確認用 confirm）" ;;
    esac
    json="$(echo "$json" | jq --arg k "$k" --argjson v "$(jq_val "$v")" '.[$k] = $v')"
  done
  echo "$json"
}

cmd="${1:-}"; shift || usage

case "$cmd" in
  init)
    mode="sequence"; stage="0a"; branch=""; pause_level="strict"; sets=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --mode) [ $# -ge 2 ] || die "--mode 需要值"; mode="$2"; shift 2 ;;
        --stage) [ $# -ge 2 ] || die "--stage 需要值"; stage="$2"; shift 2 ;;
        --branch) [ $# -ge 2 ] || die "--branch 需要值"; branch="$2"; shift 2 ;;
        --pause-level) [ $# -ge 2 ] || die "--pause-level 需要值"; pause_level="$2"; shift 2 ;;
        --set) [ $# -ge 2 ] || die "--set 需要值"; sets+=("$2"); shift 2 ;;
        *) die "init：未知參數 $1" ;;
      esac
    done
    case "$pause_level" in
      strict|balanced|autonomous) ;;
      *) die "無效的 --pause-level：'${pause_level}'（允許值：strict, balanced, autonomous）" ;;
    esac
    [ "$mode" = "sequence" ] && [ "$stage" != "0a" ] && \
      die "sequence 只能從 0a 初始化（非 0a 起始請用 --mode jump）"
    wf_id="wf-$(date +%s)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
    if [ -n "$branch" ]; then
      f="$STATE_DIR/$(slugify "$branch").json"
    else
      f="$STATE_DIR/.pending-$wf_id.json"
    fi
    claim_new "$f"
    trap 'rm -f "$f"' EXIT   # atomic_write 失敗時清掉佔位檔，避免 0-byte 殘留卡死 branch 名
    json="$(jq -n \
      --argjson sv "$SCHEMA_VERSION" --arg id "$wf_id" --arg st "$stage" --arg m "$mode" \
      --arg pl "$pause_level" \
      --argjson br "$( [ -n "$branch" ] && jq -n --arg b "$branch" '$b' || echo null )" \
      '{schema_version:$sv, workflow_id:$id, stage:$st, mode:$m, spec:null, plan:null,
        branch:$br, issue:null, pr:null, completed_tasks:[], total_tasks:null,
        pause_level:$pl, interrupted_by:null, awaiting_confirmation:false}')"
    [ ${#sets[@]} -gt 0 ] && json="$(apply_sets "$json" "${sets[@]}")"
    echo "$json" | atomic_write "$f"
    trap - EXIT
    echo "$f"
    ;;

  promote)
    src="$(resolve "$1")"; shift
    branch=""; dest="$STATE_DIR"
    while [ $# -gt 0 ]; do
      case "$1" in
        --branch) [ $# -ge 2 ] || die "--branch 需要值"; branch="$2"; shift 2 ;;
        --dest) [ $# -ge 2 ] || die "--dest 需要值"; dest="$2"; shift 2 ;;
        *) die "promote：未知參數 $1" ;;
      esac
    done
    [ -n "$branch" ] || die "promote 需要 --branch"
    validate "$src"
    f="$dest/$(slugify "$branch").json"
    claim_new "$f"
    trap 'rm -f "$f"' EXIT   # 同 init：失敗不留 0-byte 佔位檔
    jq --arg b "$branch" '.branch = $b' "$src" | atomic_write "$f"
    trap - EXIT
    rm "$src"
    echo "$f"
    ;;

  get)
    f="$(resolve "$1")"; validate "$f"; cat "$f"
    ;;

  set)
    f="$(resolve "$1")"; shift
    validate "$f"
    json="$(apply_sets "$(cat "$f")" "$@")"   # 先算後寫：apply_sets die 時整個中止，不會建 tmp
    echo "$json" | atomic_write "$f"
    ;;

  stage-done)
    f="$(resolve "$1")"; stage="$2"
    validate "$f"
    mode="$(jq -r '.mode' "$f")"; cur="$(jq -r '.stage' "$f")"
    # sequence 有固定轉移表，stage-done 不得替 advance 代勞改 stage 值；
    # quick/jump 的 stage 是自由標籤（如 review），不套用此限制
    if [ "$mode" = "sequence" ] && [ "$stage" != "$cur" ]; then
      die "sequence 模式 stage-done 參數須等於目前 stage（目前：${cur}），改 stage 請用 advance"
    fi
    awaiting="$(should_pause "$f" "$stage")"
    jq --arg s "$stage" --argjson a "$awaiting" \
      '.stage = $s | .awaiting_confirmation = $a' "$f" | atomic_write "$f"
    if [ "$awaiting" = "true" ]; then
      echo "stage $stage 完成 → 等待使用者確認（confirm 或 advance --confirmed 才能繼續）"
    else
      echo "stage $stage 完成（pause_level: $(jq -r '.pause_level // "strict"' "$f")）→ 自動推進"
    fi
    ;;

  task-done)
    f="$(resolve "$1")"; n="$2"
    validate "$f"
    mode="$(jq -r '.mode' "$f")"; cur="$(jq -r '.stage' "$f")"
    if [ "$mode" = "sequence" ] && [ "$cur" != "2" ]; then
      die "sequence 模式 task-done 僅能在 STAGE 2 執行（目前 stage：${cur}）"
    fi
    awaiting="$(should_pause "$f" task)"
    jq --argjson n "$n" --argjson a "$awaiting" \
      '.completed_tasks = ((.completed_tasks + [$n]) | unique) | .awaiting_confirmation = $a' \
      "$f" | atomic_write "$f"
    if [ "$awaiting" = "true" ]; then
      echo "任務 $n 完成 → 等待使用者確認"
    else
      echo "任務 $n 完成（pause_level: $(jq -r '.pause_level // "strict"' "$f")）→ 自動繼續下個任務"
    fi
    ;;

  confirm)
    f="$(resolve "$1")"
    validate "$f"
    jq '.awaiting_confirmation = false' "$f" | atomic_write "$f"
    ;;

  advance)
    f="$(resolve "$1")"
    if [ $# -ge 2 ]; then
      next="$2"
      shift 2
    else
      die "advance 指令需要提供目標階段 (next)，用法：wf-state.sh advance <檔> <next> [--confirmed]"
    fi
    confirmed=false
    [ "${1:-}" = "--confirmed" ] && confirmed=true
    validate "$f"
    cur="$(jq -r '.stage' "$f")"; mode="$(jq -r '.mode' "$f")"
    awaiting="$(jq -r '.awaiting_confirmation' "$f")"
    if [ "$awaiting" = "true" ] && [ "$confirmed" != "true" ]; then
      die "stage $cur 等待使用者確認中。先在對話中暫停詢問，獲確認後帶 --confirmed 重跑"
    fi
    if [ "$mode" = "sequence" ] && ! legal_transition "$cur" "$next"; then
      die "非法 stage 轉移：$cur -> ${next}（合法路徑見 legal_transition()：主線 0a→0b→1→2→3→4、3→2、4→done；獨立入口 4→5、5→4、5→5、4→6、5→6、6→done；具名 stage reviewer→responder、responder→reviewer、reviewer→publisher）"
    fi
    if [ "$next" = "3" ] && [ "$mode" = "sequence" ]; then
      total="$(jq -r '.total_tasks' "$f")"
      completed_count="$(jq -r '.completed_tasks | length' "$f")"
      if [ "$total" != "null" ] && [ "$completed_count" -lt "$total" ]; then
        die "實作尚未全部完成（已完成 $completed_count / 共 $total 任務），拒絕推進至 STAGE 3"
      fi
    fi
    jq --arg s "$next" '.stage = $s | .awaiting_confirmation = false | .interrupted_by = null' \
      "$f" | atomic_write "$f"
    echo "→ stage $next"
    ;;

  batch-init)
    pause_level="strict"; items=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --pause-level) [ $# -ge 2 ] || die "--pause-level 需要值"; pause_level="$2"; shift 2 ;;
        *) items+=("$1"); shift ;;
      esac
    done
    [ ${#items[@]} -gt 0 ] || die "batch-init 需要至少一個項目"
    case "$pause_level" in
      strict|balanced|autonomous) ;;
      *) die "無效的 --pause-level：'${pause_level}'（允許值：strict, balanced, autonomous）" ;;
    esac
    batch_id="batch-$(date +%s)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
    f="$STATE_DIR/.$batch_id.json"
    claim_new "$f"
    trap 'rm -f "$f"' EXIT
    printf '%s\n' "${items[@]}" \
      | jq -R . \
      | jq -s --arg id "$batch_id" --arg pl "$pause_level" \
          '{schema_version:1, batch_id:$id, pause_level:$pl, cursor:0,
            items:[.[] | {task:., status:"pending", branch:null, pr:null, note:null}]}' \
      | batch_write "$f"
    trap - EXIT
    echo "$f"
    ;;

  batch-get)
    f="$(resolve_batch "${1:-}")"; batch_validate "$f"; cat "$f"
    ;;

  batch-next)
    f="$(resolve_batch "${1:-}")"; batch_validate "$f"
    cursor="$(jq -r '.cursor' "$f")"
    total="$(jq -r '.items | length' "$f")"
    if [ "$cursor" -ge "$total" ]; then
      echo "DONE"
    else
      jq -r --argjson c "$cursor" '.items[$c].task' "$f"
    fi
    ;;

  batch-done|batch-fail)
    # 第一參數為批次檔（可省略 → 自動定位）；省略時不可 shift 掉後續選項
    if [ $# -gt 0 ] && [[ "${1}" != --* ]]; then
      f="$(resolve_batch "$1")"; shift
    else
      f="$(resolve_batch "")"
    fi
    pr=""; note=""; branch=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --pr) [ $# -ge 2 ] || die "--pr 需要值"; pr="$2"; shift 2 ;;
        --note) [ $# -ge 2 ] || die "--note 需要值"; note="$2"; shift 2 ;;
        --branch) [ $# -ge 2 ] || die "--branch 需要值"; branch="$2"; shift 2 ;;
        *) die "${cmd}：未知參數 $1" ;;
      esac
    done
    batch_validate "$f"
    cursor="$(jq -r '.cursor' "$f")"
    total="$(jq -r '.items | length' "$f")"
    [ "$cursor" -lt "$total" ] || die "批次已全部處理完畢（cursor=${cursor}/${total}），無當前項目可標記"
    [ "$cmd" = "batch-done" ] && status="done" || status="failed"
    jq --argjson c "$cursor" --arg s "$status" \
       --argjson pr "$( [ -n "$pr" ] && jq -n --arg v "$pr" '$v' || echo null )" \
       --argjson br "$( [ -n "$branch" ] && jq -n --arg v "$branch" '$v' || echo null )" \
       --argjson nt "$( [ -n "$note" ] && jq -n --arg v "$note" '$v' || echo null )" \
       '.items[$c].status = $s | .items[$c].pr = $pr | .items[$c].branch = $br
        | .items[$c].note = $nt | .cursor = ($c + 1)' \
      "$f" | batch_write "$f"
    remaining=$(( total - cursor - 1 ))
    if [ "$remaining" -gt 0 ]; then
      echo "項目 $((cursor + 1))/$total 標記為 $status → 剩餘 $remaining 項"
    else
      echo "項目 $((cursor + 1))/$total 標記為 $status → 批次全部處理完畢"
    fi
    ;;

  batch-abort)
    f="$(resolve_batch "${1:-}")"; batch_validate "$f"
    rm -f "$f"
    echo "批次已中止並刪除：${f}（已建立的 branch / PR 不受影響）"
    ;;

  prune)
    find "$STATE_DIR" -name ".pending-*.json" -mtime +7 -exec rm -f {} \;
    echo "清理 7 天以上的 pending 狀態檔完成"
    ;;

  *) usage ;;
esac
