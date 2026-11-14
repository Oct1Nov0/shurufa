#!/usr/bin/env python3
"""Word pairs from the n-gram model of rime-frost (zh-moqi.gram, GPL-3.0).

DataSources/rime-frost/grams.tsv.xz is the model decoded: a run of characters and
12 + ln P(last word | words before it), times 10000 (librime-octagram scores a
match as value - 12). The runs have no word marks. A run that is two words of the
lexicon, one after the other, gives P(right | left) for that pair; "$" is the end
of a clause. A run with more than one such split gives its value to each.
"""
import lzma
import math
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = pathlib.Path(os.environ.get("GRAM_FILE", ROOT / "DataSources/rime-frost/grams.tsv.xz"))
# The share of the model in the mixed estimate (0 leaves the counted pairs as they are).
# Measured on held-out clauses: 0.3 to 0.5 alike, 0.7 and 0.9 worse; runs of three words add nothing.
SHARE = float(os.environ.get("GRAM_SHARE", "0.4"))
END = 1


def pairs(lex):
    """{(left << 20) | right: P(right | left)} and, per left word, the share left for pairs not listed."""
    ids = lex.ids
    found = {}
    opener = lzma.open if SOURCE.suffix == ".xz" else open
    with opener(SOURCE, "rt", encoding="utf-8") as f:
        for line in f:
            run, value = line.rstrip("\n").split("\t")
            p = math.exp(int(value) / 10000 - 12)
            if run.endswith("$"):
                g = ids.get(run[:-1])
                if g is not None: found[(g << 20) | END] = p
                continue
            for cut in range(1, len(run)):
                g = ids.get(run[:cut])
                if g is None: continue
                w = ids.get(run[cut:])
                if w is None: continue
                code = (g << 20) | w
                if found.get(code, 0) < p: found[code] = p
    total = {}
    for code, p in found.items(): total[code >> 20] = total.get(code >> 20, 0.0) + p
    # A left word whose listed pairs sum past 0.9 is scaled to it: something is always left.
    rest = {}
    for g, t in total.items():
        rest[g] = max(1 - t, 0.1)
    for code in found:
        t = total[code >> 20]
        if t > 0.9: found[code] *= 0.9 / t
    return found, rest
