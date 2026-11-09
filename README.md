# tldr

A Claude Code plugin that ends long answers with a skimmable TLDR: the outcome, and what needs you. The full answer stays. Short answers stay short. When Claude needs a decision, every option gets a key from your home row, Vimium style, and you answer with the keys. It keeps working in long sessions and after compaction because the rule is re-injected by a hook on every prompt instead of living in conversation history.

## Why

Long agent replies bury the two things you actually need: what happened, and whether you have to do anything. Asking for a summary once works for a few turns, then drifts. The Claude Code docs say this directly: a skill's content is added once when invoked and "can keep only the start of an invoked skill" after compaction, and a rule that must hold every time belongs in a hook ([skills: Claude stops following a skill](https://code.claude.com/docs/en/skills)).

## Before / after

Before (end of a 40 line reply):

```
...so I updated the retry logic in fetcher.ts, adjusted the backoff, and also
looked at the tests. Let me know if you'd like me to make further changes!
```

After:

```
...(full answer unchanged above)

TLDR:
- Retry storm fixed: backoff now 250ms x2^n capped at 8s; p95 fetch 4.1s -> 1.3s on the replay set.
- Needs you: approve dropping the legacy `retries=10` flag (2 callers in billing/).
```

## Choice keys

When Claude needs decisions from you, the reply ends with a Pick block. One option per line, each with its own key, unique across the whole reply:

```
TLDR:
- Caveman removed, settings valid.

**Pick:**

Output style
- `a` remove (recommended)
- `s` keep both

Status line
- `d` simple (recommended)
- `f` none

Reply with keys, or `.` for all recommended.
```

Reply `ad` and press Enter, or `.` alone to take every option marked recommended. Order, case, spaces and commas don't matter. Keys are drawn as inline code, so they stand out in your theme's code color.

Set your own keys once, e.g. the Dvorak home row: `/tldr:tldr keys aoeuhtns`. The default is `asdfjkl`. Keys are personal, so they are read from your user config only, never from a project file.

When your whole message is option keys, the hook reads Claude's last reply from the session transcript, finds the Pick block, and tells Claude what you picked in words: `They picked: Output style = remove (recommended); Status line = simple (recommended).` It also flags two picks for the same decision, keys that labeled more than one option, and decisions you left unanswered, so a two-letter reply can't be misread. Only the block the reply ends on counts (option lines ``- `k` text``, empty lines, and a name line directly above an option), outside code blocks, so examples and earlier lists are ignored. A message that is not all shown keys (`hello`, `a but keep the backup`) passes through untouched.

You still press Enter: a hook cannot take a single keypress in the prompt.

## Install

From a local checkout (no marketplace, current session only):

```bash
claude --plugin-dir /path/to/claude-tldr
```

As a marketplace (this repo is both the marketplace and the plugin):

```
/plugin marketplace add murph12F/claude-tldr      # or a local path: /path/to/claude-tldr
/plugin install tldr@tldr
```

Requires `bash` and `jq`. If `jq` is missing, the hooks print a one-line error to stderr and exit 0 with no output, so the session is never broken; you just get no TLDR rules.

## Use

Type `/tldr` to see the commands:

| Command | What it does |
| :- | :- |
| `/tldr:settings` | Every setting as a table: value, what it does, the command that changes it |
| `/tldr:on` / `/tldr:off` | TLDR on long replies / never |
| `/tldr:keys` | Show your Pick keys; `/tldr:keys aoeuhtns` sets them |
| `/tldr:tldr <command>` | Everything else; `/tldr:tldr help` lists it all |

`/tldr:tldr` commands: `always`, `top`, `bottom`, `short [N]`, `full`, `lines N`, `bullets N`, `include +risks -running` (or `include outcome,risks`), `strict on|off`, `choices on|off`, `info short|full`, `set KEY VALUE`, `unset KEY`, `reset`, and `--project` on any change to write `<project>/.claude/tldr.json` instead of yours.

Output is markdown, so Claude Code draws the settings and help as tables. Settings show where each value comes from (yours, project, or default) and flag invalid or unknown keys in either file without echoing their contents. Changes are written atomically, rejected as a whole with a message naming the allowed values if anything is invalid, and apply from your next prompt. If a project file overrides a key you just changed in your user config, the command says so.

## Config

`~/.claude/tldr.json`, overridden per key by `<project>/.claude/tldr.json`. Invalid or unknown values are ignored per key (the lower layer or default is used). A malformed file is ignored entirely.

| Key | Values | Default | Meaning |
| :- | :- | :- | :- |
| `when` | `"long"`, `"always"`, `"off"` | `"long"` | `long`: TLDR only when the reply exceeds `long_lines`. `off`: nothing is injected |
| `long_lines` | integer 1-500 | `8` | Threshold for `when: "long"` and for strict mode |
| `position` | `"bottom"`, `"top"` | `"bottom"` | Where the TLDR block goes |
| `body` | `"full"`, `"short"` | `"full"` | `short`: whole reply capped at `short_lines`. Code, commands, and security/data-loss warnings are never truncated |
| `short_lines` | integer 1-100 | `5` | Cap for `body: "short"` |
| `include` | subset of `["outcome","needs_you","running","risks"]` | `["outcome","needs_you"]` | Bullets in the TLDR. `Needs you:` is always present when included (says `nothing` if nothing) |
| `max_bullets` | integer 1-5 | `3` | Bullet cap |
| `strict` | `true`, `false` | `false` | Stop hook enforces the TLDR on long replies (see below) |
| `choices` | `"keys"`, `"off"` | `"keys"` | Label decision options with keys and decode keys-only replies (see [Choice keys](#choice-keys)) |
| `pick_info` | `"short"`, `"full"` | `"short"` | `full`: each Pick option also says what it does and its main cost or risk, on the same line |
| `hint_keys` | 2-26 distinct `a-z`/`0-9` | `"asdfjkl"` | Option keys, in the order Claude uses them. User config only; ignored in a project file |

Example project override:

```json
{ "position": "top", "include": ["outcome", "needs_you", "risks"] }
```

## How it works

- **`UserPromptSubmit` hook** (`scripts/tldr-inject.sh`): reads the merged config and returns `hookSpecificOutput.additionalContext` with a ~60 word rule block. Because it runs on every prompt, toggles take effect immediately and the rules return after compaction without a `SessionStart` hook. The injected text is marked "newest wins" so earlier blocks still in context don't conflict. Docs: [UserPromptSubmit decision control](https://code.claude.com/docs/en/hooks), 10,000 character cap on `additionalContext`, 30 s default timeout on this event (this plugin sets 5 s).
- **Fixed quality rules** in every injection: outcome first with concrete numbers and decisions, not process narration; `Needs you:` always present when included; never restate the question; no "I did X" recaps; short replies get no TLDR when `when` is `long`; never truncate code, commands, or security/data-loss warnings; no em dash character.
- **Optional `Stop` hook** (`scripts/tldr-stop.sh`): only when `strict: true`. If `last_assistant_message` has more than `long_lines` non-blank lines (or any, with `when: "always"`) and no `TLDR` line, it returns `{"decision":"block","reason":...}` asking Claude to append only the TLDR. It does nothing when `stop_hook_active` is true, so it blocks at most once per stop. Docs: [Stop input and decision control](https://code.claude.com/docs/en/hooks).
- **Skills** `/tldr:tldr`, `/tldr:settings`, `/tldr:on`, `/tldr:off`, `/tldr:keys` (`skills/*/SKILL.md`), all running the one script: `disable-model-invocation: true`, pre-allowed to run only `${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh`. Skills are the documented format for new plugin commands ([plugin components](https://code.claude.com/docs/en/plugins/components), [skills](https://code.claude.com/docs/en/skills)).
- Hook commands reference scripts through `${CLAUDE_PLUGIN_ROOT}`, quoted, as the [manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference) recommends for shell-form hooks.

Cost: about 160 tokens of context per prompt while enabled (about 80 with `choices: "off"`). `when: "off"` injects nothing. Decoding a keys reply reads the last 400 lines of the transcript, about 50 ms on a 1.7 MB session.

- **Choice decoding** (same hook): only when the prompt is one to twelve shown keys, or `.`. It reads `transcript_path` from the hook input, takes Claude's last text reply, and appends a `[tldr picks]` line naming the chosen options to the same `additionalContext`. Option text is cut to 120 characters and the whole line to 1500. It only repeats text Claude itself wrote in the previous reply.

### Security

Config files are untrusted input (a cloned repo can ship `.claude/tldr.json`). Values are never eval'd or interpolated into shell commands: files are parsed by `jq`, every key is checked against a fixed whitelist inside `jq`, and the injected text is built from fixed strings plus validated integers, so a project config cannot inject free text into Claude's context. Files over 64 KB are ignored. No network calls. `/tldr:tldr` arguments are matched against literal command names and passed to `jq` only as `--arg` strings; `status` reports invalid or unknown project keys by count and name of the known key, never by value.

## Compared to

- **[caveman](https://github.com/JuliusBrussee/caveman)**: compresses the whole reply. tldr keeps the full answer and adds a skim layer (or caps it with `body: "short"`).
- **[claude-code-tldr](https://github.com/rodrigooler/claude-code-tldr)**: a skill toggle that caps every reply to 5 lines; it lives in conversation context, so it drifts in long sessions and after compaction.
- **tldr**: hook-injected every turn, so it does not drift; per-project config; optional strict enforcement.

## Tests

```bash
./tests/run.sh
claude plugin validate .
```

`tests/run.sh` feeds sample hook JSON to the scripts in a throwaway `HOME` and checks: defaults, project override, `when: "off"`, short mode, strict block, the `stop_hook_active` guard, short replies, malformed config, hostile config values, missing `jq`, and every `/tldr` command (shortcuts, `set`/`unset`, `include` ops, `--project`, error paths with hostile arguments, and a status that never echoes config contents).

## Uninstall

```
/plugin uninstall tldr@tldr
/plugin marketplace remove tldr
rm ~/.claude/tldr.json            # optional: your saved settings
```

## Docs used

- Hooks reference: https://code.claude.com/docs/en/hooks
- Plugin manifest reference: https://code.claude.com/docs/en/plugins/manifest-reference
- Plugin components: https://code.claude.com/docs/en/plugins/components
- Create a marketplace: https://code.claude.com/docs/en/plugins/create-marketplace
- Marketplace reference: https://code.claude.com/docs/en/plugins/marketplace-reference
- Skills: https://code.claude.com/docs/en/skills

## License

MIT
