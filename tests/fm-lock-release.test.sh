#!/usr/bin/env bash
# fm-lock.sh release: drop the fleet session lock for chat handoff.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-lock-release)

test_release_already_free() {
  local home out
  home="$TMP_ROOT/free"
  mkdir -p "$home/state"
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-lock.sh" release)
  assert_contains "$out" "lock released: already free" "release on free home"
  [ ! -e "$home/state/.lock" ] || fail "lock file appeared on free release"
  pass "release: already free"
}

test_release_stale_pid() {
  local home out
  home="$TMP_ROOT/stale"
  mkdir -p "$home/state"
  # PID 1 is almost never a verified harness match for fm_harness_pid_alive.
  printf '1\n' > "$home/state/.lock"
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-lock.sh" release)
  assert_contains "$out" "lock released: was stale pid 1" "stale release message"
  [ ! -e "$home/state/.lock" ] || fail "stale lock file remained"
  pass "release: stale pid"
}

test_release_removes_recorded_pid_file() {
  local home out
  home="$TMP_ROOT/any-pid"
  mkdir -p "$home/state"
  printf '%s\n' "$$" > "$home/state/.lock"
  out=$(FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-lock.sh" release)
  assert_contains "$out" "lock released:" "release printed success"
  [ ! -e "$home/state/.lock" ] || fail "lock file remained after release"
  pass "release: removes lock file for any recorded pid"
}

test_release_refuses_symlink() {
  local home status
  home="$TMP_ROOT/symlink"
  mkdir -p "$home/state" "$home/other"
  printf '1\n' > "$home/other/target"
  ln -s "$home/other/target" "$home/state/.lock"
  status=0
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-lock.sh" release >/dev/null 2>&1 || status=$?
  [ "$status" -eq 1 ] || fail "symlink lock must refuse release (got $status)"
  [ -L "$home/state/.lock" ] || fail "symlink lock must remain"
  pass "release: refuses symlink lock"
}

test_release_already_free
test_release_stale_pid
test_release_removes_recorded_pid_file
test_release_refuses_symlink
