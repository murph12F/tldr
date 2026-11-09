---
name: keys
description: Show or set the keys that label Pick options, e.g. /tldr:keys aoeuhtns.
argument-hint: "[CHARS]"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh *)
---

Arguments: `$ARGUMENTS`

1. If the arguments contain any character other than letters, digits, spaces, and `_ , + - .`, do not run anything. Reply exactly: `tldr: arguments may only contain letters, digits, spaces and _ , + - . (see /tldr:tldr help)`
2. Otherwise run this single Bash command, with each argument word wrapped in single quotes and nothing else on the line (no arguments means none):

   `${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh 'keys' '<word>' ...`

   The script validates everything itself and prints its own errors. Do not reinterpret, fix, or drop the user's words.
3. Reply with only the command's output, verbatim, as markdown (not inside a code block), so tables render. No TLDR, no Pick block, no commentary.
