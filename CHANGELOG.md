# Changelog

## 0.3.0 (2026-11-09)

- Choice keys: decisions go in a `**Pick:**` block at the end of the reply, a name line per decision and one option per line (``- `k` option``), keys unique across the reply, recommended option first. Reply with the keys (e.g. `ae`) or `.` for every recommended option. `Needs you:` keeps only what is not a pick.
- The UserPromptSubmit hook decodes a keys-only reply against Claude's last reply in the transcript and names the picks back, flagging double picks, reused keys and unanswered decisions. Code blocks and earlier prose are ignored.
- New keys: `choices` (`keys`/`off`, default `keys`) and `hint_keys` (default `asdfjkl`; user config only, a project file cannot set it). Commands: `/tldr:tldr keys CHARS`, `/tldr:tldr choices on|off`.

## 0.2.0 (2026-11-06)

- `/tldr:tldr status` (the default) is a table: value, source (`default`/`user`/`project`), and allowed values per key; flags malformed files and invalid or unknown keys without echoing their contents.
- Every key is settable: `set KEY VALUE`, `unset KEY`, plus `always`, `short N`, `lines N`, `bullets N`, `include +x -y` / `include a,b`.
- `--project` writes `<project>/.claude/tldr.json` instead of the user config; `reset --project` clears it.
- Invalid input is rejected with a message naming the allowed values (exit 2, nothing written) instead of silently falling back to `status`.
- `help` lists every command. Changes report the new effective value and warn when a project file overrides it.

## 0.1.0 (2026-11-06)

- `UserPromptSubmit` hook injects TLDR rules every prompt via `additionalContext`.
- Config in `~/.claude/tldr.json` with per-key project override: `when`, `long_lines`, `position`, `body`, `short_lines`, `include`, `max_bullets`, `strict`.
- Optional strict `Stop` hook with `stop_hook_active` guard.
- `/tldr:tldr` skill: `on`, `off`, `top`, `bottom`, `short`, `full`, `strict on`, `strict off`, `status`, `reset`.
- `tests/run.sh` covering hooks, config merge, malformed and hostile config, missing jq, and the toggle command.
