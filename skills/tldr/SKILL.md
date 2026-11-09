---
name: tldr
description: Change any tldr setting (help lists all commands; quick ones are /tldr:settings, /tldr:on, /tldr:off, /tldr:keys).
argument-hint: "[status|help|on|off|always|top|bottom|short [N]|full|lines N|bullets N|include +x -y|strict on|off|choices on|off|info short|full|keys CHARS|set KEY VALUE|unset KEY|reset] [--project]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh *)
---

Arguments: `$ARGUMENTS`

1. If the arguments contain any character other than letters, digits, spaces, and `_ , + - . = ; : ~ ^ *`, do not run anything. Reply exactly: `tldr: arguments may only contain letters, digits, spaces and _ , + - . = ; : ~ ^ * (see /tldr:tldr help)`
2. Otherwise run this single Bash command, with each argument word wrapped in single quotes and nothing else on the line (no arguments means none):

   `${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh '<word>' '<word>' ...`

   The script validates everything itself and prints its own errors. Do not reinterpret, fix, or drop the user's words.
3. Reply with only the command's output, verbatim, as markdown (not inside a code block), so tables render. No TLDR, no Pick block, no commentary.
