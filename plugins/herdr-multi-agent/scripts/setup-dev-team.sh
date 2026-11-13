#!/usr/bin/env bash
# Set up a herdr dev team for one project as four new tabs of Claude agents.
#
#   tab 1  <project>-product-owner                            1 pane
#   tab 2  <project>-manager, <project>-architect             2 panes
#   tab 3  <project>-dev-lead, <project>-dev-1..3             4 panes
#   tab 4  <project>-review-lead, <project>-reviewer-1..3     4 panes
#
# Run from a herdr pane (HERDR_ENV=1). Role prompts come from ../agents/.
# Bash 3.2 compatible, since macOS ships that version by default.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/../agents"
PROTOCOL_FILE="$SCRIPT_DIR/messaging-protocol.md"

usage() {
  cat <<'EOF'
Usage: setup-dev-team.sh <project> [--cwd DIR] [--dry-run] [--no-agents] [-- CLAUDE_ARGS...]

Creates four tabs in the current herdr workspace and starts a team of Claude
agents for <project>:

  tab 1  <project>-product-owner                            (1 pane)
  tab 2  <project>-manager, <project>-architect             (2 panes)
  tab 3  <project>-dev-lead, <project>-dev-1..3             (4 panes)
  tab 4  <project>-review-lead, <project>-reviewer-1..3     (4 panes)

Arguments:
  <project>     Lowercase project name or code, e.g. "caghes". Letters, digits,
                and dashes; must start with a letter.
  --cwd DIR     Working directory for every pane (default: current directory).
  --dry-run     Print the plan and the herdr commands without running them.
  --no-agents   Build the tabs and panes but start no agents (layout test).
  -- ARGS       Extra arguments passed to each claude agent after its role prompt.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

PROJECT=""
CWD="$PWD"
DRY_RUN=0
NO_AGENTS=0
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --cwd)
      [ $# -ge 2 ] || die "--cwd needs a directory"
      CWD="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-agents)
      NO_AGENTS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_ARGS=("$@")
      break
      ;;
    -*)
      usage >&2
      die "unknown option: $1"
      ;;
    *)
      [ -z "$PROJECT" ] || die "unexpected argument: $1"
      PROJECT="$1"
      shift
      ;;
  esac
done

[ -n "$PROJECT" ] || { usage >&2; exit 2; }
printf '%s' "$PROJECT" | grep -Eq '^[a-z][a-z0-9-]*$' \
  || die "project must be lowercase letters, digits, and dashes, starting with a letter: '$PROJECT'"

# Agent names must match [a-z][a-z0-9_-]{0,31} in herdr.
PO="$PROJECT-product-owner"
MANAGER="$PROJECT-manager"
ARCHITECT="$PROJECT-architect"
DEV_LEAD="$PROJECT-dev-lead"
DEVS=("$PROJECT-dev-1" "$PROJECT-dev-2" "$PROJECT-dev-3")
REVIEW_LEAD="$PROJECT-review-lead"
REVIEWERS=("$PROJECT-reviewer-1" "$PROJECT-reviewer-2" "$PROJECT-reviewer-3")
ALL=("$PO" "$MANAGER" "$ARCHITECT" "$DEV_LEAD" "${DEVS[@]}" "$REVIEW_LEAD" "${REVIEWERS[@]}")

for n in "${ALL[@]}"; do
  [ "${#n}" -le 32 ] || die "agent name '$n' is longer than 32 characters; use a shorter project name"
done

for role in product-owner manager architect dev-lead developer review-lead reviewer; do
  [ -f "$AGENTS_DIR/$role.md" ] || die "missing role file: $AGENTS_DIR/$role.md"
done
[ -f "$PROTOCOL_FILE" ] || die "missing messaging protocol: $PROTOCOL_FILE"

[ -d "$CWD" ] || die "directory does not exist: $CWD"
CWD="$(cd "$CWD" && pwd)"

if [ "$DRY_RUN" -eq 0 ]; then
  [ "${HERDR_ENV:-}" = 1 ] || die "not inside a herdr pane (HERDR_ENV is not 1). Run this from a herdr pane."
  [ -n "${HERDR_WORKSPACE_ID:-}" ] || die "HERDR_WORKSPACE_ID is not set"
  command -v herdr >/dev/null 2>&1 || die "herdr is not in PATH"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  # Check names before creating anything, so a clash cannot leave half-built tabs.
  if [ "$NO_AGENTS" -eq 0 ]; then
    for n in "${ALL[@]}"; do
      if herdr agent get "$n" >/dev/null 2>&1; then
        die "an agent named '$n' is already running. Close it or choose another project name."
      fi
    done
  fi
fi
WS="${HERDR_WORKSPACE_ID:-<workspace>}"

# herdr_json <herdr args...>: run herdr and print its JSON, or a stub in dry-run.
herdr_json() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  + herdr $*" >&2
    echo '{}'
    return 0
  fi
  herdr "$@"
}

# json_field <json> <jq filter> <dry-run placeholder>
json_field() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "$3"
    return 0
  fi
  jq -er "$2" <<<"$1" || die "unexpected herdr response (no $2): $1"
}

role_label() { # <agent name> -> human-readable role
  case "$1" in
    "$PO") echo "product owner" ;;
    "$MANAGER") echo "manager" ;;
    "$ARCHITECT") echo "architect" ;;
    "$DEV_LEAD") echo "dev team lead" ;;
    "$REVIEW_LEAD") echo "review team lead" ;;
    *-dev-[0-9]) echo "developer" ;;
    *-reviewer-[0-9]) echo "reviewer" ;;
  esac
}

peers_for() { # <agent name> -> one "- name" line per agent it may message
  case "$1" in
    "$PO")
      printf '%s\n' "- the user (in this chat)" "- $MANAGER" "- $ARCHITECT"
      ;;
    "$MANAGER")
      printf '%s\n' "- $PO" "- $ARCHITECT" "- $DEV_LEAD" "- $REVIEW_LEAD"
      ;;
    "$ARCHITECT")
      printf '%s\n' "- $PO" "- $MANAGER"
      ;;
    "$DEV_LEAD")
      printf '%s\n' "- $MANAGER"
      printf -- '- %s\n' "${DEVS[@]}"
      ;;
    "$REVIEW_LEAD")
      printf '%s\n' "- $MANAGER"
      printf -- '- %s\n' "${REVIEWERS[@]}"
      ;;
    *-dev-[0-9])
      printf '%s\n' "- $DEV_LEAD"
      ;;
    *-reviewer-[0-9])
      printf '%s\n' "- $REVIEW_LEAD"
      ;;
  esac
}

roster() {
  local n
  for n in "${ALL[@]}"; do
    printf -- '- %s (%s)\n' "$n" "$(role_label "$n")"
  done
}

# render_prompt <role key> <agent name> -> full system prompt on stdout
render_prompt() {
  local role="$1" self="$2" body protocol
  body="$(awk 'c >= 2 { print; next } /^---[[:space:]]*$/ { c++; next }' "$AGENTS_DIR/$role.md")"
  protocol="$(cat "$PROTOCOL_FILE")"
  body="${body//__PROTOCOL__/$protocol}"
  body="${body//__PROJECT__/$PROJECT}"
  body="${body//__SELF__/$self}"
  body="${body//__ROSTER__/$(roster)}"
  body="${body//__PEERS__/$(peers_for "$self")}"
  printf '%s\n' "$body"
}

# setup_message <role prompt>: wrap the role so the agent adopts it without contacting anyone yet.
setup_message() {
  printf '%s\n\n%s\n' \
    "This is a setup message from the dev team script. Adopt the role below for the rest of this session. Reply with one line confirming your role. Do not message any teammate until the user or a teammate contacts you first." \
    "$1"
}

# start_agent <agent name> <pane id> <role key>
#
# herdr rejects agent arguments that contain newlines, and role prompts are
# multi-line, so the role is sent as the agent's first message instead.
start_agent() {
  local name="$1" pane="$2" role="$3" prompt args
  if [ "$NO_AGENTS" -eq 1 ]; then
    echo "    $name: no agent started (--no-agents)"
    return 0
  fi
  prompt="$(render_prompt "$role" "$name")"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    start $name in $pane as $role ($(printf '%s' "$prompt" | wc -c | tr -d ' ') byte prompt)"
    return 0
  fi
  args=(agent start "$name" --kind claude --pane "$pane" --timeout 60000)
  if [ "${#EXTRA_ARGS[@]}" -gt 0 ]; then
    args+=(-- "${EXTRA_ARGS[@]}")
  fi
  herdr "${args[@]}" >/dev/null
  herdr agent prompt "$name" "$(setup_message "$prompt")" >/dev/null
  echo "    started $name in $pane"
}

# new_tab <label>: sets TAB_ID and ROOT_PANE
new_tab() {
  local out
  out="$(herdr_json tab create --workspace "$WS" --cwd "$CWD" --label "$1" --no-focus)"
  TAB_ID="$(json_field "$out" '.result.tab.tab_id' "<tab: $1>")"
  ROOT_PANE="$(json_field "$out" '.result.root_pane.pane_id' "<root pane: $1>")"
  echo "  tab $TAB_ID: $1"
}

# split_pane <pane id> <right|down>: sets NEW_PANE
split_pane() {
  local out
  out="$(herdr_json pane split "$1" --direction "$2" --cwd "$CWD" --no-focus)"
  NEW_PANE="$(json_field "$out" '.result.pane.pane_id' "<pane: split $1 $2>")"
}

# build_team_tab <label> <lead> <lead role> <member role> <member>...
# The lead takes the left column; members stack down the right column.
build_team_tab() {
  local label="$1" lead="$2" lead_role="$3" member_role="$4" prev="" member
  shift 4
  new_tab "$label"
  start_agent "$lead" "$ROOT_PANE" "$lead_role"
  for member in "$@"; do
    if [ -z "$prev" ]; then
      split_pane "$ROOT_PANE" right
    else
      split_pane "$prev" down
    fi
    prev="$NEW_PANE"
    start_agent "$member" "$prev" "$member_role"
  done
}

echo "Dev team for '$PROJECT' in workspace $WS (cwd $CWD)"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN: no herdr commands will run."
fi
echo "Roster:"
roster | sed 's/^/  /'
echo

echo "Tab 1: product owner"
new_tab "$PROJECT product owner"
start_agent "$PO" "$ROOT_PANE" product-owner
PO_TAB="$TAB_ID"

echo "Tab 2: planning (manager and architect)"
new_tab "$PROJECT planning"
start_agent "$MANAGER" "$ROOT_PANE" manager
split_pane "$ROOT_PANE" right
start_agent "$ARCHITECT" "$NEW_PANE" architect

echo "Tab 3: dev team"
build_team_tab "$PROJECT dev team" "$DEV_LEAD" dev-lead developer "${DEVS[@]}"

echo "Tab 4: review team"
build_team_tab "$PROJECT review team" "$REVIEW_LEAD" review-lead reviewer "${REVIEWERS[@]}"

if [ "$DRY_RUN" -eq 0 ]; then
  herdr tab focus "$PO_TAB" >/dev/null
  echo
  echo "Done. Talk to $PO in tab $PO_TAB."
fi
