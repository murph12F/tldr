# shellcheck shell=bash
# Shared helpers for the tldr plugin. Sourced, not executed.
#
# Security model: config files are untrusted (a cloned repo can ship
# .claude/tldr.json). Values never reach the shell: files are parsed by jq,
# every key is checked against a fixed whitelist inside jq, and the injected
# text is assembled in jq from fixed strings plus validated integers.

TLDR_MAX_CONFIG_BYTES=65536

tldr_have_jq() {
  command -v jq >/dev/null 2>&1
}

tldr_user_config_path() {
  printf '%s/.claude/tldr.json' "${HOME:-}"
}

# Print a config file as a compact JSON object, or {} if it is missing,
# too large, unreadable, malformed, or not an object.
tldr_read_layer() {
  local f="$1" size
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    printf '{}'
    return 0
  fi
  size=$(wc -c <"$f" 2>/dev/null) || size=0
  if [ "${size:-0}" -gt "$TLDR_MAX_CONFIG_BYTES" ]; then
    printf '{}'
    return 0
  fi
  jq -c 'if type == "object" then . else {} end' "$f" 2>/dev/null || printf '{}'
}

# jq definitions: defaults, per-key validation, layered merge.
TLDR_JQ_DEFS='
def defaults: {
  when: "long", long_lines: 8, position: "bottom", body: "full",
  short_lines: 5, include: ["outcome", "needs_you"], max_bullets: 3,
  strict: false, choices: "keys", hint_keys: "asdfjkl", pick_info: "short"
};
def int_in($lo; $hi): type == "number" and . == floor and . >= $lo and . <= $hi;
def ok($k):
  if   $k == "when"        then type == "string" and IN("long", "always", "off")
  elif $k == "position"    then type == "string" and IN("bottom", "top")
  elif $k == "body"        then type == "string" and IN("full", "short")
  elif $k == "long_lines"  then int_in(1; 500)
  elif $k == "short_lines" then int_in(1; 100)
  elif $k == "max_bullets" then int_in(1; 5)
  elif $k == "strict"      then type == "boolean"
  elif $k == "choices"     then type == "string" and IN("keys", "off")
  elif $k == "pick_info"   then type == "string" and IN("short", "full")
  elif $k == "hint_keys"   then type == "string" and test("^[a-z0-9]{2,26}$")
                                and ((split("") | unique | length) == length)
  elif $k == "include"     then type == "array" and length > 0
                                and all(.[]; type == "string"
                                  and IN("outcome", "needs_you", "running", "risks"))
  else false end;
def key_order: ["when", "long_lines", "position", "body", "short_lines", "include", "max_bullets", "strict", "choices", "pick_info", "hint_keys"];
# Personal keys are read from the user config only; a project file cannot set them.
def personal: ["hint_keys"];
def include_items: ["outcome", "needs_you", "running", "risks"];
def allowed: {
  when: "long|always|off", long_lines: "1-500", position: "bottom|top",
  body: "full|short", short_lines: "1-100", include: "outcome,needs_you,running,risks",
  max_bullets: "1-5", strict: "on|off", choices: "keys|off",
  hint_keys: "2-26 distinct a-z 0-9 (user config only)", pick_info: "short|full"
};
def overlay($layer):
  reduce (defaults | keys[]) as $k (.;
    if ($layer | has($k)) and ($layer[$k] | ok($k)) then .[$k] = $layer[$k] else . end);
def merged: defaults | overlay($u) | overlay($p | delpaths([personal[] | [.]]))
  | .include |= (. as $inc | ["outcome", "needs_you", "running", "risks"]
                 | map(select(. as $x | $inc | index($x))));
'

# tldr_config <project_dir>: print merged effective config as compact JSON.
# Project file wins per key; invalid values fall back to the lower layer.
tldr_config() {
  local proj="$1" u p
  u=$(tldr_read_layer "$(tldr_user_config_path)")
  p='{}'
  if [ -n "$proj" ]; then
    p=$(tldr_read_layer "$proj/.claude/tldr.json")
  fi
  jq -nc --argjson u "$u" --argjson p "$p" "$TLDR_JQ_DEFS merged"
}

# Resolve the project dir: CLAUDE_PROJECT_DIR (exported to hooks) or the
# hook input's cwd field.
tldr_project_dir() {
  local input="$1"
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  printf '%s' "$input" | jq -r '.cwd // empty | strings' 2>/dev/null || true
}
