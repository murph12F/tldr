#!/usr/bin/env bash
# UserPromptSubmit hook: inject the current TLDR rules as additionalContext.
# Runs every turn, so /tldr toggles apply on the next prompt and the rules
# come back after compaction. Must never break the session: always exit 0.
#
# Choice keys: when the prompt is only hint keys (e.g. "ae") or ".", the
# labeled options in Claude's last reply are decoded from the transcript and
# named back, so a two-letter reply cannot be misread.

src=${BASH_SOURCE[0]}
case "$src" in */*) here=${src%/*} ;; *) here=. ;; esac
# shellcheck source=lib.sh
. "$here/lib.sh" || exit 0

if ! tldr_have_jq; then
  echo "tldr plugin: jq not found on PATH; TLDR rules not injected. Install jq (brew install jq / apt install jq)." >&2
  exit 0
fi

input=$(cat 2>/dev/null) || input=''
proj=$(tldr_project_dir "$input")
cfg=$(tldr_config "$proj" 2>/dev/null) || exit 0

# Decode a keys-only reply against the options in Claude's last reply.
picks=''
reply=$(printf '%s' "$input" | jq -r '.prompt // empty | strings | ascii_downcase | gsub("[\\s,]"; "")' 2>/dev/null)
tpath=$(printf '%s' "$input" | jq -r '.transcript_path // empty | strings' 2>/dev/null)
if printf '%s' "$cfg" | jq -e '.choices == "keys" and .when != "off"' >/dev/null 2>&1 \
   && printf '%s' "$reply" | grep -Eq '^([a-z0-9]{1,12}|\.)$' \
   && [ -n "$tpath" ] && [ -f "$tpath" ] && [ -r "$tpath" ]; then
  last=$(tail -n 400 "$tpath" 2>/dev/null | jq -R -s -r '
    [ split("\n")[] | fromjson?
      # Claude Code transcript lines, then Codex rollout lines.
      | if .type == "user" and (.message.content | type) == "string" then {k: "p"}
        elif .type == "assistant" and (.message.content | type) == "array"
          then .message.content[] | select(.type == "text") | {k: "a", t: .text}
        elif .type == "response_item" and .payload.type == "message" and .payload.role == "user" then {k: "p"}
        elif .type == "response_item" and .payload.type == "message" and .payload.role == "assistant"
             and (.payload.content | type) == "array"
          then .payload.content[] | select(.type == "output_text") | {k: "a", t: .text}
        else empty end ]
    | (if length > 0 and .[-1].k == "p" then .[:-1] else . end)
    | map(select(.k == "a")) | last | .t // ""' 2>/dev/null)
  picks=$(jq -nr --arg text "$last" --arg reply "$reply" --argjson c "$cfg" '
    def clean: gsub("[`*_]"; "") | gsub("^[\\s>|:-]+|[\\s>|:,;/-]+$"; "");
    ($c.hint_keys | split("")) as $ks
    # Option line: "- `a` option text" (or "- [a] option text"), one option per
    # line, under a decision name line ("Reply format").
    | def opt: [capture("^\\s*[-*+]?\\s*(`(?<a>[a-z0-9])`|\\[(?<b>[a-z0-9])\\])\\s+(?<t>\\S.*)$")]
        | if length == 0 then null else .[0] | {key: (.a // .b), text: .t} end;
      def is_opt: opt as $o | $o != null and ($ks | index($o.key)) != null;
    # Lines outside fenced code blocks.
    ( reduce ($text | split("\n")[]) as $ln ({fence: false, out: []};
        if $ln | test("^\\s*(```|~~~)") then .fence |= not
        elif .fence then .
        else .out += [$ln] end) | .out ) as $lines
    | [ $lines[] | if is_opt then "o" elif test("^\\s*$") then "b" else "t" end ] as $cls
    # Only the last block the reply ends on: option lines, blank lines, and a
    # name line directly above an option. Anything else above it ends the block,
    # so examples and prose earlier in the reply are never read as options.
    | ( [ $cls | to_entries[] | select(.value == "o") | .key ] | last ) as $end
    | ( if $end == null then []
        else ( first( range($end; -1; -1) as $i
                      | select($cls[$i] == "t" and $cls[$i + 1] != "o") | $i ) // -1 ) as $stop
             | [ range($stop + 1; $end + 1) as $i | {cls: $cls[$i], line: $lines[$i]} ]
        end ) as $block
    | ( reduce $block[] as $b ([];
          if $b.cls == "t" then . + [{name: ($b.line | clean | .[:80]), opts: []}]
          elif $b.cls == "o" then
            (if length == 0 then [{name: "", opts: []}] else . end)
            | .[-1].opts += [ $b.line | opt | {key, text: (.text | clean | .[:200])} ]
          else . end) )
    | to_entries | map(.value + {d: .key}) as $ds
    | [ $ds[] as $d | $d.opts[] | . + {d: $d.d} ] as $all
    | def optname($o): ($ds[$o.d].name) as $n
        | if $n == "" then $o.text else "\($n) = \($o.text)" end;
      if ($all | length) == 0 then empty
      elif $reply == "." then
        [ $ds[] | . as $d | [ .opts[] | select(.text | test("(?i)recommended")) ][0]
          | if . then optname(. + {d: $d.d}) else empty end ] as $rec
        | [ $ds[] | select([.opts[] | select(.text | test("(?i)recommended"))] | length == 0)
          | .name | select(. != "") ] as $norec
        | if ($rec | length) == 0
          then "[tldr picks] The user replied `.` (accept every recommended option), but your last reply marked none as recommended: ask which options they want."
          else "[tldr picks] The user replied `.`: accept every recommended option: \($rec | join("; "))."
               + (if ($norec | length) > 0 then " No recommended option, still open: \($norec | join("; "))." else "" end) end
      else
        ($reply | split("")) as $typed
        | if all($typed[]; . as $t | $all | any(.key == $t)) | not then empty
          else
            [ $typed | unique[] as $t | $all | map(select(.key == $t)) | select(length > 1) | .[0].key ] as $dup
            | [ $typed | unique[] as $t | $all[] | select(.key == $t) ] | sort_by(.d) | . as $sel
            | [ $sel | group_by(.d)[] | select(length > 1) | (.[0].d) as $d | $ds[$d].name ] as $conf
            | [ $ds[] | select(.d as $d | $sel | any(.d == $d) | not) | .name | select(. != "") ] as $open
            | "[tldr picks] The user replied `\($reply)` using the option keys from your last reply. They picked: \([$sel[] | optname(.)] | join("; "))."
              + (if ($dup | length) > 0 then " Keys \($dup | join(", ")) labeled more than one option: ask which they meant." else "" end)
              + (if ($conf | length) > 0 then " Two picks for the same decision (\($conf | join(", "))): ask which one." else "" end)
              + (if ($open | length) > 0 then " Not answered: \($open | join("; "))." else "" end)
          end
      end' 2>/dev/null)
  picks=${picks:0:1500}
fi

jq -nc --argjson c "$cfg" --arg picks "$picks" '
  $c as $c
  | if $c.when == "off" then empty else
    {
      outcome:   "outcome first (concrete numbers/decisions, not process)",
      needs_you: (if $c.choices == "keys"
                   then "`Needs you:` non-pick actions only (omit if the Pick block covers it; `nothing` if nothing)"
                   else "`Needs you:` (always; `nothing` if nothing)" end),
      running:   "`Running:` what is still in progress (omit if none)",
      risks:     "`Risks:` real risks only (omit if none)"
    } as $item
    | ([$c.include[] | $item[.]] | join("; ")) as $items
    | (if $c.position == "top" then "start it with" else "end it with" end) as $where
    | (if $c.when == "always"
         then "Always \($where)"
         else "If the reply exceeds \($c.long_lines) lines, \($where)" end) as $trigger
    | [
          "[tldr rules, newest wins]",
          (if $c.body == "short"
             then "Keep the whole reply to at most \($c.short_lines) lines (code, commands, security/data-loss warnings exempt)."
             else empty end),
          "\($trigger) a `TLDR:` line and at most \($c.max_bullets) bullets: \($items).",
          (if $c.position == "top" then "Then a blank line, then the answer." else empty end),
          (if $c.when == "long" then "Shorter replies: no TLDR." else empty end),
          (if $c.choices == "keys" then
            "Decisions for the user: end the reply with a `**Pick:**` block; per decision a short name line, then one option per line, ``- `k` option``, keys from `\($c.hint_keys)` in order, each used once per reply, recommended first and marked (recommended), an empty line between decisions\(if $c.pick_info == "full" then "; after each option, on the same line, `: ` then what it does and its main cost or risk (under 15 words)" else "" end); last line: Reply with keys, or `.` for all recommended."
           else empty end),
          "Never restate the question or recap \"I did X\". Never truncate code, commands, or security/data-loss warnings. No em dash character.",
        (if $picks == "" then empty else $picks end)
      ]
    | join(" ")
    | {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: .}}
    end
' 2>/dev/null

exit 0
