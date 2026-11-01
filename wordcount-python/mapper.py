#!/usr/bin/env python3
"""Streaming mapper: emit "word<TAB>1" per run of letters a-z, lowercased (same rule as TokenizerMapper.java)."""
import re
import sys

WORD = re.compile(r"[a-z]+")

sys.stdin.reconfigure(encoding="utf-8", errors="replace")
for line in sys.stdin:
    for word in WORD.findall(line.lower()):
        sys.stdout.write(f"{word}\t1\n")
