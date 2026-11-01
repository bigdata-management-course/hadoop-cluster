#!/usr/bin/env python3
"""Streaming reducer (and combiner): input arrives sorted by key, so equal words are adjacent."""
import sys
from itertools import groupby

pairs = (line.rstrip("\n").split("\t", 1) for line in sys.stdin)
for word, group in groupby(pairs, key=lambda kv: kv[0]):
    sys.stdout.write(f"{word}\t{sum(int(count) for _, count in group)}\n")
