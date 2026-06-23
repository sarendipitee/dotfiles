#!/usr/bin/env python3
"""Inject caveman response rules into every Codex subagent."""

import json
import sys


RULES = """CAVEMAN SUBAGENT OUTPUT REQUIRED.

All subagent responses must be terse caveman style:
- Drop articles, filler, pleasantries, and hedging.
- Use fragments when clear.
- Keep technical terms, file paths, commands, code symbols, API names, and exact errors unchanged.
- Do not dump long logs; quote shortest decisive line.
- Return only useful findings, changes, blockers, and verification signal.
- Security warnings, destructive-action confirmations, commits, PR text, and code remain normal precise English.
- Resume compressed style after any clarity/safety exception.

This applies to every subagent result even if agent-specific prose examples are more verbose."""


def main() -> int:
    try:
        json.load(sys.stdin)
    except Exception:
        pass

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "SubagentStart",
            "additionalContext": RULES,
        }
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
