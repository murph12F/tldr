---
name: off
description: Turn tldr off: no TLDR rules are injected.
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh *)
---

1. Run this single Bash command, exactly, ignoring any arguments:

   `${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh 'off'`

2. Reply with only the command's output, verbatim, as markdown (not inside a code block), so tables render. No TLDR, no Pick block, no commentary.
