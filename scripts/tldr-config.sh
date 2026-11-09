#!/usr/bin/env bash
# /tldr command backend. Shows settings, or edits ~/.claude/tldr.json (or the
# project's .claude/tldr.json with --project) atomically. Run with `help`.
#
# Security: arguments are lowercased, split without globbing, matched against
# literal command names, and handed to jq only as --arg strings. jq validates
# every value against the same whitelist the hooks use. Nothing is eval'd.
# Status output never echoes values or key names read from config files, so
# an untrusted project config cannot put free text into Claude's context.

src=${BASH_SOURCE[0]}
case "$src" in */*) here=${src%/*} ;; *) here=. ;; esac
# shellcheck source=lib.sh
. "$here/lib.sh" || exit 1

if ! tldr_have_jq; then
  echo "tldr: jq not found on PATH. Install jq (brew install jq / apt install jq)."
  exit 1
fi

help_text='tldr: /tldr:tldr <command>
  status                    show settings and where each one comes from (default)
  on | off | always         TLDR on long replies / never / on every reply
  top | bottom              where the TLDR goes
  short [N] | full          cap the whole reply at N lines / no cap
  lines N                   reply length (lines) that triggers a TLDR, 1-500
  bullets N                 max TLDR bullets, 1-5
  include +risks -running   add/remove TLDR items (outcome, needs_you, running, risks)
  include outcome,risks     replace the item list
  strict on | strict off    Stop hook re-asks when a long reply has no TLDR
  choices on | choices off  label decision options with keys you answer with
  keys CHARS                your option keys, e.g. keys aoeuhtns (user config only)
  set KEY VALUE             set any key (names as in status)
  unset KEY                 drop your value, fall back to project/default
  reset                     clear all your settings
  --project                 with any change: write <project>/.claude/tldr.json instead
  help                      this text
Changes apply from your next prompt.'

die_usage() {
  printf 'tldr: %s\nRun /tldr:tldr help for all commands.\n' "$1"
  exit 2
}

# Normalize: lowercase, then split on whitespace with globbing off.
words=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')
set -f
# shellcheck disable=SC2086
set -- $words
set +f

scope=user
argv=()
for w in "$@"; do
  case "$w" in
    --project|-p) scope=project ;;
    *) argv+=("$w") ;;
  esac
done
set -- "${argv[@]+"${argv[@]}"}"

# Printable form of a user token for error messages.
tok() { printf '%s' "$1" | tr -cd 'a-z0-9_,+.-' | cut -c1-40; }

edits='[]'
add_edit() {
  edits=$(printf '%s' "$edits" | jq -c --arg op "$1" --arg k "${2-}" --arg v "${3-}" '. + [{op: $op, k: $k, v: $v}]')
}
# need <count> <usage>: exact number of arguments after the command word.
need() { [ "$argc" -eq "$1" ] || die_usage "usage: /tldr:tldr $2"; }

cmd=${1-}
[ "$#" -gt 0 ] && shift
argc=$#
action=edit
case "$cmd" in
  ''|status)         need 0 status; action=status ;;
  help|-h|--help)    printf '%s\n' "$help_text"; exit 0 ;;
  on)                need 0 on; add_edit on ;;
  off|always)        need 0 "$cmd"; add_edit set when "$cmd" ;;
  top|bottom)        need 0 "$cmd"; add_edit set position "$cmd" ;;
  full)              need 0 full; add_edit set body full ;;
  short)
    [ "$argc" -le 1 ] || die_usage "usage: /tldr:tldr short [N]"
    add_edit set body short
    [ "$argc" -eq 1 ] && add_edit set short_lines "$1"
    ;;
  lines)             need 1 "lines N"; add_edit set long_lines "$1" ;;
  bullets)           need 1 "bullets N"; add_edit set max_bullets "$1" ;;
  strict)            need 1 "strict on|off"; add_edit set strict "$1" ;;
  choices)
    need 1 "choices on|off"
    case "$1" in on) add_edit set choices keys ;; *) add_edit set choices "$1" ;; esac
    ;;
  keys)              need 1 "keys CHARS"; add_edit set hint_keys "$1" ;;
  include)
    [ "$argc" -ge 1 ] || die_usage "usage: /tldr:tldr include +item -item | include item,item"
    for t in "$@"; do add_edit include '' "$t"; done
    ;;
  set)               need 2 "set KEY VALUE"; add_edit set "$1" "$2" ;;
  unset)             need 1 "unset KEY"; add_edit unset "$1" ;;
  reset)             need 0 reset; action=reset ;;
  *)                 die_usage "unknown command \"$(tok "$cmd")\"" ;;
esac

ucfg=$(tldr_user_config_path)
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
pcfg="$proj/.claude/tldr.json"
[ "$pcfg" = "$ucfg" ] && pcfg=''

pretty() { # home-relative path for display
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# file_state <path>: none | ok | malformed
file_state() {
  if [ -z "$1" ] || [ ! -f "$1" ]; then echo none
  elif jq -e 'type == "object"' "$1" >/dev/null 2>&1; then echo ok
  else echo malformed; fi
}

layer() { if [ -n "$1" ]; then tldr_read_layer "$1"; else printf '{}'; fi; }

# jq: display helpers shared by status and the change report.
TLDR_JQ_SHOW='
def show($k): if $k == "strict" then (if . then "on" else "off" end)
              elif $k == "include" then join(",") else tostring end;
def src($k): if ($k | IN(personal[]) | not) and ($p | has($k)) and ($p[$k] | ok($k)) then "project"
             elif ($u | has($k)) and ($u[$k] | ok($k)) then "user" else "default" end;
def pad($n): tostring | . + (" " * ([$n - length, 1] | max));
'

if [ "$action" = status ]; then
  us=$(file_state "$ucfg")
  ps=$(file_state "$pcfg")
  label() { # label <path> <state> <reset hint>
    case "$2" in
      ok)        pretty "$1" ;;
      none)      printf '%s (none)' "$(pretty "$1")" ;;
      malformed) printf '%s (malformed, ignored; fix it or run /tldr:tldr %s)' "$(pretty "$1")" "$3" ;;
    esac
  }
  ulabel=$(label "$ucfg" "$us" reset)
  if [ -z "$pcfg" ]; then plabel='none'; else plabel=$(label "$pcfg" "$ps" 'reset --project'); fi

  u=$(layer "$ucfg"); p=$(layer "$pcfg")
  jq -nr --argjson u "$u" --argjson p "$p" --arg ul "$ulabel" --arg pl "$plabel" "$TLDR_JQ_DEFS $TLDR_JQ_SHOW"'
    merged as $m
    | ([key_order[] as $k | $m[$k] | show($k) | length] | max + 2) as $w
    | def bad($name; $l): [ key_order[] as $k | select(($l | has($k)) and (($l[$k] | ok($k)) | not))
                            | "  ignored invalid \($name) value for \($k)" ];
      def unknown($name; $l): ([$l | keys[] | select(. as $k | key_order | index($k) | not)] | length)
                            | if . > 0 then ["  ignored \(.) unknown key(s) in \($name) config"] else [] end;
    [ "tldr: user    \($ul)", "      project \($pl)",
      "  \("key" | pad(13))\("value" | pad($w))\("from" | pad(9))allowed",
      ( key_order[] as $k
        | "  \($k | pad(13))\($m[$k] | show($k) | pad($w))\(src($k) | pad(9))\(allowed[$k])" ),
      ( bad("user"; $u) + bad("project"; $p) + unknown("user"; $u) + unknown("project"; $p)
        + [ personal[] as $k | select($p | has($k)) | "  ignored \($k) in project config (personal key: set it in your user config)" ] )[],
      "Change: /tldr:tldr help"
    ] | join("\n")'
  exit $?
fi

# ---- edit / reset ----
if [ "$scope" = project ]; then
  [ -n "$pcfg" ] || die_usage "--project: project dir is your home dir; edit the user config instead"
  target=$pcfg
else
  target=$ucfg
fi
tdir=$(dirname "$target")

if [ "$action" = reset ]; then
  current='{}'
else
  case "$(file_state "$target")" in
    none) current='{}' ;;
    ok)   current=$(jq -c . "$target") || { echo "tldr: cannot read $(pretty "$target")"; exit 1; } ;;
    *)    echo "tldr: $(pretty "$target") is not a valid JSON object; fix it or run /tldr:tldr reset$([ "$scope" = project ] && echo ' --project')"
          exit 1 ;;
  esac
fi

u=$(layer "$ucfg")
p=$(layer "$pcfg")
res=$(printf '%s' "$current" | jq -c --argjson u "$u" --argjson p "$p" --argjson edits "$edits" --arg scope "$scope" "$TLDR_JQ_DEFS"'
  def fail($m): error({tldr: $m});
  def keyalias: ({lines: "long_lines", bullets: "max_bullets", keys: "hint_keys"}[.] // .);
  def canon: . as $inc | include_items | map(select(. as $x | $inc | index($x)));
  def parse($k):
    if   $k | IN("long_lines", "short_lines", "max_bullets") then (tonumber? // .)
    elif $k == "strict" then
      (if IN("on", "true", "yes") then true elif IN("off", "false", "no") then false else . end)
    elif $k == "include" then (split(",") | map(select(length > 0)))
    else . end;
  def known($k; $raw):
    if defaults | has($k) then . else fail("unknown key \"\($raw[:40])\"; keys: \(key_order | join(", "))") end;
  def lower: if $scope == "project" then defaults | overlay($u) else defaults end;
  def apply1($e):
    if $e.op == "on" then
      (if .when == "off" or (has("when") | not) then .when = "long" else . end)
    elif $e.op == "unset" then
      ($e.k | keyalias) as $k | known($k; $e.k) | del(.[$k])
    elif $e.op == "set" then
      ($e.k | keyalias) as $k | known($k; $e.k)
      | (if $scope == "project" and ($k | IN(personal[])) then fail("\($k) is personal: set it without --project") else . end)
      | ($e.v | parse($k)) as $v
      | if $v | ok($k) then .[$k] = (if $k == "include" then ($v | canon) else $v end)
        else fail("\($k) must be \(allowed[$k])") end
    elif $e.op == "include" then
      . as $cur | (lower | overlay($cur)).include as $base
      | $e.v as $t
      | ( if   $t | startswith("+") then [$t[1:]]
          elif $t | startswith("-") then [$t[1:]]
          else ($t | split(",") | map(select(length > 0))) end ) as $names
      | ([$names[] | select(. as $x | include_items | index($x) | not)] | first) as $badname
      | if $badname then fail("include: unknown item \"\($badname[:40])\"; items: \(include_items | join(", "))") else . end
      | ( if   $t | startswith("+") then $base + $names
          elif $t | startswith("-") then $base - $names
          else $names end | canon ) as $new
      | if ($new | length) == 0 then fail("include: keep at least one item") else .include = $new end
    else fail("internal: bad edit") end;
  try {ok: (reduce $edits[] as $e (.; apply1($e)))}
  catch (if type == "object" and has("tldr") then {error: .tldr} else {error: "internal error: \(.)"} end)
')
[ -n "$res" ] || { echo "tldr: internal error applying change"; exit 1; }
err=$(printf '%s' "$res" | jq -r '.error // empty')
[ -z "$err" ] || die_usage "$err"
new=$(printf '%s' "$res" | jq -c '.ok')

mkdir -p "$tdir" || { echo "tldr: cannot create $(pretty "$tdir")"; exit 1; }
tmp=$(mktemp "$tdir/.tldr.json.XXXXXX") || { echo "tldr: cannot create temp file in $(pretty "$tdir")"; exit 1; }
if printf '%s\n' "$new" | jq . >"$tmp" 2>/dev/null && mv -f "$tmp" "$target"; then
  :
else
  rm -f "$tmp"
  echo "tldr: failed to write $(pretty "$target")"
  exit 1
fi

# Report: the effective value of each touched key and where it now comes from.
u=$(layer "$ucfg")
p=$(layer "$pcfg")
jq -nr --argjson u "$u" --argjson p "$p" --argjson edits "$edits" --arg scope "$scope" \
       --arg path "$(pretty "$target")" --argjson reset "$([ "$action" = reset ] && echo true || echo false)" \
       "$TLDR_JQ_DEFS $TLDR_JQ_SHOW"'
  def keyalias: ({lines: "long_lines", bullets: "max_bullets", keys: "hint_keys"}[.] // .);
  merged as $m
  | ( if $reset then []
      else [ $edits[] | if .op == "on" then "when" elif .op == "include" then "include" else (.k | keyalias) end ]
           | unique | . as $t | key_order | map(select(. as $k | $t | index($k))) end ) as $touched
  | [ (if $reset then "tldr: cleared \($path); \(if $scope == "user" then "back to defaults" else "project overrides removed" end), applies from your next prompt"
       else "tldr: saved \($path); applies from your next prompt" end),
      ( $touched[] as $k
        | "  \($k) = \($m[$k] | show($k)) (\(src($k)))"
          + (if $scope == "user" and src($k) == "project" then "  <- project config overrides yours here" else "" end) )
    ] | join("\n")'
