#!/usr/bin/env python3
"""Word and character frequencies of rime-frost (白霜拼音, GPL-3.0) as evidence for pinyin weights.

DataSources/rime-frost/frequencies.tsv.xz holds text, toneless pinyin and corpus frequency
from cn_dicts/8105, base and ext of https://github.com/gaboolic/rime-frost (see SOURCE.json).
"""
import collections
import lzma
import os
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "DataSources/rime-frost/frequencies.tsv.xz"
# How far a weight moves towards the place rime-frost gives the word (0 keeps it, 1 takes it).
SHARE = float(os.environ.get("FROST_SHARE", "0.5"))  # measured: 0.3, 0.7 and 1.0 worse


def frequencies():
    table = {}
    for line in lzma.decompress(SOURCE.read_bytes()).decode().splitlines():
        text, letters, frequency = line.split("\t")
        table[(text, letters.replace(" ", ""))] = int(frequency)
    return table


def letters_of(code):
    return re.sub("[1-5 ]", "", code)


def frost_weights(weights, fixed, report):
    """Orders the words of each length as rime-frost does, on the scale the weights already have.

    Words are grouped by (Simplified text, toneless letters). Of the groups rime-frost lists,
    those of one length (1, 2, 3, 4+ characters) keep their set of weights, handed out again in
    the order of the rime-frost frequencies: the scale between lengths, which the sentence
    model was tuned on, stays. A group moves SHARE of the way to its new place, every reading
    of it by the same amount. Reviewed rows
    and names (`fixed`) are left alone."""
    table = frequencies()
    top = {}
    for key, weight in weights.items():
        if key in fixed: continue
        group = (key[1], letters_of(key[2]))
        if group in table and (group not in top or top[group] < weight): top[group] = weight
    by_length = collections.defaultdict(list)
    for group, weight in top.items(): by_length[min(len(group[0]), 4)].append(group)
    shift = {}
    for length, groups in by_length.items():
        scale = sorted((top[g] for g in groups), reverse=True)
        ordered = sorted(groups, key=lambda g: (-table[g], -top[g], g))
        for target, group in zip(scale, ordered): shift[group] = SHARE * (target - top[group])
    report["frost_groups_reweighted"] = len(shift)
    result = {}
    for key, weight in weights.items():
        group = (key[1], letters_of(key[2]))
        result[key] = max(1, min(10000, round(weight + shift[group]))) if group in shift and key not in fixed else weight
    return result


# Words rime-frost lists at least this often are added when the lexicon lacks them.
ADD_MIN = int(os.environ.get("FROST_ADD_MIN", "300"))
ABBREVIATE_MIN = 3000  # of the added words, these also get their initials keys


def frost_additions(weights, converter, report):
    """Words and set phrases (的时候, 是一个, 公众号) the lexicon lacks, for the pinyin index.

    Returns (hant, hans, toned code, weight, frequency) rows. The tones are those of the most
    likely reading each character has in the lexicon for the same letters; the weight is that
    of lexicon words of the same length which rime-frost lists about as often."""
    import bisect
    import subprocess
    table = frequencies()
    have = {key[1] for key in weights}
    tone = {}
    for (hant, hans, code), weight in weights.items():
        if len(hans) == 1:
            group = (hans, letters_of(code))
            if group not in tone or tone[group][0] < weight: tone[group] = (weight, code)
    # frequency -> weight, from the words both have
    scale = collections.defaultdict(list)
    top = {}
    for key, weight in weights.items():
        group = (key[1], letters_of(key[2]))
        if group in table and len(key[1]) > 1: top[group] = max(top.get(group, 0), weight)
    for group, weight in top.items(): scale[min(len(group[0]), 4)].append((table[group], weight))
    curve = {}
    for length, points in scale.items():
        points.sort()
        freqs = [f for f, _ in points]; ws = [w for _, w in points]
        curve[length] = (freqs, ws)
    def weight_for(length, frequency):
        freqs, ws = curve[min(length, 4)]
        at = bisect.bisect_left(freqs, frequency)
        window = sorted(ws[max(0, at - 100):at + 101])
        return window[len(window) // 2]  # median of the 201 words around this frequency
    source = lzma.decompress(SOURCE.read_bytes()).decode().splitlines()
    picked = {}
    for line in source:
        text, letters, frequency = line.split("\t")
        frequency = int(frequency)
        if len(text) < 2 or frequency < ADD_MIN or text in have: continue
        syllables = letters.split()
        codes = [tone.get((ch, syl)) for ch, syl in zip(text, syllables)]
        if any(c is None for c in codes): continue
        code = " ".join(c[1] for c in codes)
        if text not in picked or picked[text][1] < frequency: picked[text] = (code, frequency)
    texts = sorted(picked)
    converted = subprocess.run([converter, "--traditional"], input="\n".join(texts) + "\n", text=True, capture_output=True, check=True).stdout.splitlines()
    if len(converted) != len(texts): raise ValueError("Traditional conversion mismatch (rime-frost additions)")
    rows = [(hant, hans, picked[hans][0], weight_for(len(hans), picked[hans][1]), picked[hans][1]) for hans, hant in zip(texts, converted)]
    report["frost_words_added"] = len(rows)
    return rows
