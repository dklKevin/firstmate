#!/usr/bin/env bash
# Install Firstmate's guarded Grok crew turn-end hook.
#
# This command is the sole owner of the firstmate-owned files
# ${GROK_HOME:-$HOME/.grok}/hooks/fm-turn-end.sh and
# ${GROK_HOME:-$HOME/.grok}/hooks/fm-turn-end.json. It never writes any other
# hook file, never deletes sibling hooks, and refuses when those firstmate-owned
# paths exist with unexpected content.
#
# The installed Stop hook always exits 0. It fires only when the workspace holds
# a .fm-grok-turnend pointer that names a Firstmate-created token in
# ${GROK_HOME:-$HOME/.grok}/hooks/fm-turn-end.d/.
#
# Usage:
#   fm-grok-turnend-hook.sh install
set -u

case "${1:-}" in
  install) ;;
  -h|--help)
    sed -n '2,16{s/^# \{0,1\}//;p;}' "$0"
    exit 0
    ;;
  *)
    printf 'usage: %s install\n' "${0##*/}" >&2
    exit 2
    ;;
esac

if [ -z "${HOME:-}" ]; then
  printf 'fm-grok-turnend-hook: refused: HOME is unset.\n' >&2
  exit 1
fi

GROK_HOME_DIR="${GROK_HOME:-$HOME/.grok}"
GROK_HOOKS_DIR="$GROK_HOME_DIR/hooks"
GROK_AUTH_DIR="$GROK_HOOKS_DIR/fm-turn-end.d"
HOOK_SCRIPT="$GROK_HOOKS_DIR/fm-turn-end.sh"
HOOK_JSON="$GROK_HOOKS_DIR/fm-turn-end.json"
FIRSTMATE_HEADER='# Firstmate Grok turn-end hook. Managed by fm-grok-turnend-hook.sh.'

shell_quote() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

atomic_write() {
  local path=$1 mode=${2:-} temp
  temp=$(mktemp "${path}.tmp.XXXXXX") || return 1
  if ! cat > "$temp"; then
    unlink "$temp" 2>/dev/null || true
    return 1
  fi
  if [ -n "$mode" ] && ! chmod "$mode" "$temp"; then
    unlink "$temp" 2>/dev/null || true
    return 1
  fi
  if ! mv -f "$temp" "$path"; then
    unlink "$temp" 2>/dev/null || true
    return 1
  fi
}

regular_not_symlink() {
  local path=$1 label=$2
  if [ -L "$path" ]; then
    printf 'fm-grok-turnend-hook: refused: %s is a symlink at %s.\n' "$label" "$path" >&2
    return 1
  fi
  if [ ! -f "$path" ]; then
    printf 'fm-grok-turnend-hook: refused: %s is not a regular file at %s.\n' "$label" "$path" >&2
    return 1
  fi
  return 0
}

firstmate_owned_hook_script() {
  local path=$1
  if grep -Fqx "$FIRSTMATE_HEADER" "$path" 2>/dev/null; then
    return 0
  fi
  # Previous firstmate-generated scripts lacked the header but carried the
  # distinctive per-task pointer and token-registry checks.
  grep -Fq '.fm-grok-turnend' "$path" 2>/dev/null \
    && grep -Fq 'fm.????????????' "$path" 2>/dev/null \
    && grep -Fq 'token=' "$path" 2>/dev/null
}

firstmate_owned_hook_json() {
  local path=$1
  grep -Fq 'fm-turn-end.sh' "$path" 2>/dev/null \
    && grep -Fq '"Stop"' "$path" 2>/dev/null
}

if [ -L "$GROK_HOME_DIR" ]; then
  printf 'fm-grok-turnend-hook: refused: Grok home is a symlink at %s.\n' "$GROK_HOME_DIR" >&2
  exit 1
fi
if [ -e "$GROK_HOOKS_DIR" ] || [ -L "$GROK_HOOKS_DIR" ]; then
  if [ -L "$GROK_HOOKS_DIR" ] || [ ! -d "$GROK_HOOKS_DIR" ]; then
    printf 'fm-grok-turnend-hook: refused: Grok hooks path is not a regular directory at %s.\n' "$GROK_HOOKS_DIR" >&2
    exit 1
  fi
fi
if [ -e "$HOOK_SCRIPT" ] || [ -L "$HOOK_SCRIPT" ]; then
  regular_not_symlink "$HOOK_SCRIPT" "Firstmate hook script" || exit 1
  if ! firstmate_owned_hook_script "$HOOK_SCRIPT"; then
    printf 'fm-grok-turnend-hook: refused: Firstmate hook path has unexpected content at %s.\n' "$HOOK_SCRIPT" >&2
    exit 1
  fi
fi
if [ -e "$HOOK_JSON" ] || [ -L "$HOOK_JSON" ]; then
  regular_not_symlink "$HOOK_JSON" "Firstmate hook registration" || exit 1
  if ! firstmate_owned_hook_json "$HOOK_JSON"; then
    printf 'fm-grok-turnend-hook: refused: Firstmate hook registration has unexpected content at %s.\n' "$HOOK_JSON" >&2
    exit 1
  fi
fi
if [ -e "$GROK_AUTH_DIR" ] || [ -L "$GROK_AUTH_DIR" ]; then
  if [ -L "$GROK_AUTH_DIR" ] || [ ! -d "$GROK_AUTH_DIR" ]; then
    printf 'fm-grok-turnend-hook: refused: Firstmate registry is not a regular directory at %s.\n' "$GROK_AUTH_DIR" >&2
    exit 1
  fi
fi

mkdir -p "$GROK_AUTH_DIR" || {
  printf 'fm-grok-turnend-hook: refused: could not create %s.\n' "$GROK_AUTH_DIR" >&2
  exit 1
}

sq_auth_dir=$(shell_quote "$GROK_AUTH_DIR")
if ! atomic_write "$HOOK_SCRIPT" +x <<EOF
#!/usr/bin/env bash
$FIRSTMATE_HEADER
set -u
auth_dir=$sq_auth_dir
workspace=\${GROK_WORKSPACE_ROOT:-}
[ -n "\$workspace" ] || exit 0
p="\$workspace/.fm-grok-turnend"
[ -f "\$p" ] || exit 0
first=
IFS= read -r -n 256 first < "\$p" 2>/dev/null || [ -n "\$first" ] || exit 0
case "\$first" in token=*) token=\${first#token=} ;; *) exit 0 ;; esac
case "\$token" in fm.????????????) : ;; *) exit 0 ;; esac
case "\$token" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
t=\$(cat "\$auth_dir/\$token" 2>/dev/null) || exit 0
case "\$t" in /*.turn-ended) : ;; *) exit 0 ;; esac
touch "\$t" 2>/dev/null || true
exit 0
EOF
then
  printf 'fm-grok-turnend-hook: refused: could not install Firstmate hook script at %s.\n' "$HOOK_SCRIPT" >&2
  exit 1
fi

hook_command=$(json_escape "bash $(shell_quote "$HOOK_SCRIPT")")
if ! printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"%s"}]}]}}\n' "$hook_command" | atomic_write "$HOOK_JSON"; then
  printf 'fm-grok-turnend-hook: refused: could not install Firstmate hook registration at %s.\n' "$HOOK_JSON" >&2
  exit 1
fi
