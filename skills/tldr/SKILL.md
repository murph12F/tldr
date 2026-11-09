---
name: tldr
description: Show or change the tldr plugin's reply summary settings (status, help, on, off, always, top, bottom, short, full, lines, bullets, include, strict, choices, keys, set, unset, reset, --project).
argument-hint: "[status|help|on|off|always|top|bottom|short [N]|full|lines N|bullets N|include +x -y|strict on|off|choices on|off|keys CHARS|set KEY VALUE|unset KEY|reset] [--project]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh *)
---

Arguments: `$ARGUMENTS`

1. If the arguments contain any character other than letters, digits, spaces, and `_ , + - .`, do not run anything. Reply exactly: `tldr: arguments may only contain letters, digits, spaces and _ , + - . (see /tldr:tldr help)`
2. Otherwise run this single Bash command, with each argument word wrapped in single quotes and nothing else on the line (no arguments means none):

   `${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh '<word>' '<word>' ...`

   The script validates everything itself and prints its own errors. Do not reinterpret, fix, or drop the user's words.
3. Reply with only the command's output, verbatim, inside a fenced code block. No TLDR, no commentary.
