#!/usr/bin/env bash
# Behavior tests for Grok-harness hook authentication, teardown cleanup, and session-lock holder detection.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-grok-harness)

make_spawn_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|send-keys|kill-window) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse gh-axi gh
  printf '%s\n' "$fakebin"
}

make_spawn_case() {
  local name=$1 case_dir home proj wt fakebin grok_home id
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_spawn_fakebin "$case_dir/fake")
  grok_home="$case_dir/grok"
  id="grok-$name-x1"
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config" "$grok_home"
  printf 'brief\n' > "$home/data/$id/brief.md"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  touch "$home/state/.last-watcher-beat"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin|$grok_home|$id"
}

run_grok_spawn() {
  local home=$1 proj=$2 wt=$3 fakebin=$4 grok_home=$5 id=$6
  FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    GROK_HOME="$grok_home" PATH="$fakebin:$PATH" \
    "$SPAWN" "$id" "$proj" grok --mode no-mistakes --yolo off 2>&1
}

test_grok_hook_requires_registered_token() {
  local rec case_dir home proj wt fakebin grok_home id out status hook token target evil evil_target
  rec=$(make_spawn_case hook-auth)
  IFS='|' read -r case_dir home proj wt fakebin grok_home id <<EOF
$rec
EOF
  out=$(run_grok_spawn "$home" "$proj" "$wt" "$fakebin" "$grok_home" "$id")
  status=$?
  expect_code 0 "$status" "grok spawn should succeed"
  assert_contains "$out" "spawned $id harness=grok" "grok spawn did not report success"

  hook="$grok_home/hooks/fm-turn-end.sh"
  assert_present "$hook" "grok hook script was not installed"
  assert_grep 'token=' "$wt/.fm-grok-turnend" "grok pointer did not contain a token"
  target="$home/state/$id.turn-ended"
  assert_no_grep "$target" "$wt/.fm-grok-turnend" "grok pointer exposed the turn-end path"
  token=$(sed -n 's/^token=//p' "$wt/.fm-grok-turnend")
  assert_present "$grok_home/hooks/fm-turn-end.d/$token" "grok auth registry entry was not written"

  evil="$case_dir/evil"
  evil_target="$case_dir/evil-target.turn-ended"
  mkdir -p "$evil"
  printf '%s\n' "$evil_target" > "$evil/.fm-grok-turnend"
  GROK_WORKSPACE_ROOT="$evil" bash "$hook"
  assert_absent "$evil_target" "old-style grok pointer touched an arbitrary target"

  {
    printf '%s\n' 'ignored'
    printf 'token=%s\n' "$token"
  } > "$wt/.fm-grok-turnend"
  GROK_WORKSPACE_ROOT="$wt" bash "$hook"
  assert_absent "$target" "grok pointer accepted token outside the first line"

  printf 'token=%s\n' "$token" > "$wt/.fm-grok-turnend"
  GROK_WORKSPACE_ROOT="$wt" bash "$hook"
  assert_present "$target" "registered grok pointer did not touch the task turn-end file"
  pass "grok global hook requires a firstmate registry token"
}

test_grok_teardown_removes_pointer_and_token() {
  local rec case_dir home proj wt fakebin grok_home id out status token
  rec=$(make_spawn_case teardown)
  IFS='|' read -r case_dir home proj wt fakebin grok_home id <<EOF
$rec
EOF
  out=$(run_grok_spawn "$home" "$proj" "$wt" "$fakebin" "$grok_home" "$id")
  status=$?
  expect_code 0 "$status" "grok spawn should succeed before teardown"
  token=$(sed -n 's/^token=//p' "$wt/.fm-grok-turnend")

  FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    GROK_HOME="$grok_home" PATH="$fakebin:$PATH" \
    "$TEARDOWN" "$id" --force >/dev/null 2>&1 \
    || fail "grok teardown failed"

  assert_absent "$wt/.fm-grok-turnend" "grok pointer survived teardown"
  assert_absent "$grok_home/hooks/fm-turn-end.d/$token" "grok auth token survived teardown"
  assert_absent "$home/state/$id.grok-turnend-token" "grok state token survived teardown"
  pass "grok teardown removes pointer and token state"
}

test_fm_lock_recognizes_grok_holder() {
  local home fakebin out
  home="$TMP_ROOT/lock-home"
  fakebin=$(fm_fakebin "$TMP_ROOT/lock-fake")
  mkdir -p "$home/state"
  printf '%s\n' "$$" > "$home/state/.lock"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"comm="*) printf '%s\n' '/usr/local/bin/grok'; exit 0 ;;
  *"args="*) printf '%s\n' 'grok'; exit 0 ;;
esac
exit 1
SH
  chmod +x "$fakebin/ps"
  out=$(FM_HOME="$home" PATH="$fakebin:$PATH" "$ROOT/bin/fm-lock.sh" status)
  assert_contains "$out" "lock: held by live harness pid" "fm-lock did not recognize grok as a live holder"
  pass "fm-lock recognizes grok harness processes"
}

test_grok_hook_preserves_unrelated_hooks() {
  local rec case_dir home proj wt fakebin grok_home id out status sibling
  rec=$(make_spawn_case sibling-hooks)
  IFS='|' read -r case_dir home proj wt fakebin grok_home id <<EOF
$rec
EOF
  sibling="$grok_home/hooks/captain-custom.json"
  mkdir -p "$grok_home/hooks"
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"true"}]}]}}\n' > "$sibling"
  cp "$sibling" "$case_dir/sibling-before.json"
  out=$(run_grok_spawn "$home" "$proj" "$wt" "$fakebin" "$grok_home" "$id")
  status=$?
  expect_code 0 "$status" "grok spawn should succeed beside an unrelated hook"
  cmp -s "$case_dir/sibling-before.json" "$sibling" \
    || fail "grok spawn changed an unrelated hook file"
  assert_present "$grok_home/hooks/fm-turn-end.sh" "firstmate hook script was not installed"
  assert_present "$grok_home/hooks/fm-turn-end.json" "firstmate hook registration was not installed"
  pass "grok hook install leaves unrelated ~/.grok/hooks files untouched"
}

test_grok_hook_refuses_unexpected_hook_script() {
  local rec case_dir home proj wt fakebin grok_home id out status hook
  rec=$(make_spawn_case unexpected-script)
  IFS='|' read -r case_dir home proj wt fakebin grok_home id <<EOF
$rec
EOF
  hook="$grok_home/hooks/fm-turn-end.sh"
  mkdir -p "$grok_home/hooks"
  printf '%s\n' '#!/bin/sh' 'echo captain-owned' > "$hook"
  cp "$hook" "$case_dir/hook-before"
  out=$(run_grok_spawn "$home" "$proj" "$wt" "$fakebin" "$grok_home" "$id") || status=$?
  [ "${status:-0}" -ne 0 ] || fail "grok spawn overwrote an unexpected hook script"
  assert_contains "$out" "unexpected content" "grok spawn omitted the unexpected-hook refusal"
  cmp -s "$case_dir/hook-before" "$hook" || fail "unexpected hook script refusal changed the file"
  pass "grok hook install refuses unexpected fm-turn-end.sh without overwriting it"
}

test_grok_hook_refuses_unexpected_hook_json() {
  local rec case_dir home proj wt fakebin grok_home id out status json
  rec=$(make_spawn_case unexpected-json)
  IFS='|' read -r case_dir home proj wt fakebin grok_home id <<EOF
$rec
EOF
  json="$grok_home/hooks/fm-turn-end.json"
  mkdir -p "$grok_home/hooks"
  printf '%s\n' '{"hooks":{"SessionStart":[]}}' > "$json"
  cp "$json" "$case_dir/json-before"
  out=$(run_grok_spawn "$home" "$proj" "$wt" "$fakebin" "$grok_home" "$id") || status=$?
  [ "${status:-0}" -ne 0 ] || fail "grok spawn overwrote an unexpected hook registration"
  assert_contains "$out" "unexpected content" "grok spawn omitted the unexpected-json refusal"
  cmp -s "$case_dir/json-before" "$json" || fail "unexpected hook json refusal changed the file"
  pass "grok hook install refuses unexpected fm-turn-end.json without overwriting it"
}

test_grok_hook_refuses_dangling_hook_script() {
  local case_dir hook outside out status
  case_dir="$TMP_ROOT/dangling-hook-script"
  hook="$case_dir/grok/hooks/fm-turn-end.sh"
  outside="$case_dir/outside-hook.sh"
  mkdir -p "$case_dir/grok/hooks"
  ln -s "$outside" "$hook"
  out=$(HOME="$case_dir/home" GROK_HOME="$case_dir/grok" \
    "$ROOT/bin/fm-grok-turnend-hook.sh" install 2>&1) || status=$?
  [ "${status:-0}" -ne 0 ] || fail "grok hook install followed a dangling hook symlink"
  assert_contains "$out" "is a symlink" "dangling hook symlink refusal was not explicit"
  assert_absent "$outside" "dangling hook symlink received installed content"
  [ -L "$hook" ] || fail "dangling hook symlink was replaced after refusal"
  pass "grok hook install refuses dangling hook symlinks"
}

test_grok_hook_refuses_json_control_characters() {
  local case_dir grok_home valid_grok_home out status
  case_dir="$TMP_ROOT/control-character-path"
  grok_home="$case_dir/grok"$'\n'x
  out=$(HOME="$case_dir/home" GROK_HOME="$grok_home" \
    "$ROOT/bin/fm-grok-turnend-hook.sh" install 2>&1) || status=$?
  [ "${status:-0}" -ne 0 ] || fail "grok hook install accepted a control character in GROK_HOME"
  assert_contains "$out" "JSON control character" "control-character path refusal was not explicit"
  assert_absent "$grok_home/hooks/fm-turn-end.json" "control-character path created a registration"
  valid_grok_home="$case_dir/grok home"
  out=$(HOME="$case_dir/home" GROK_HOME="$valid_grok_home" \
    "$ROOT/bin/fm-grok-turnend-hook.sh" install 2>&1) \
    || fail "grok hook install rejected a valid path containing spaces:$'\n'$out"
  jq -e . "$valid_grok_home/hooks/fm-turn-end.json" >/dev/null 2>&1 \
    || fail "grok hook install emitted invalid JSON for a path containing spaces"
  pass "grok hook install refuses JSON control characters in GROK_HOME"
}

test_grok_hook_requires_registered_token
test_grok_hook_preserves_unrelated_hooks
test_grok_hook_refuses_unexpected_hook_script
test_grok_hook_refuses_unexpected_hook_json
test_grok_hook_refuses_dangling_hook_script
test_grok_hook_refuses_json_control_characters
test_grok_teardown_removes_pointer_and_token
test_fm_lock_recognizes_grok_holder
