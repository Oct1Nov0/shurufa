#!/usr/bin/env python3
"""Decodes a librime-octagram .gram file (a Darts double array) into lines of text and value.

  python3 scripts/decode_gram.py zh-moqi.gram grams.tsv
"""
import struct, sys, numpy as np
data = open(sys.argv[1], "rb").read()
fmt = data[:32].split(b"\0")[0]
checksum, size, off = struct.unpack_from("<IIi", data, 32)
start = 40 + off
arr = np.frombuffer(data, dtype="<u4", count=size, offset=start)
print(fmt, size, start, len(data), file=sys.stderr)
labels = (arr & np.uint32(0x800000FF)).astype(np.int64)
cs = np.arange(1, 256, dtype=np.int64)
def offset(u): return (u >> 10) << ((u & 512) >> 6)
def decode(b):
    out = []; i = 0
    while i < len(b):
        c = b[i]
        if c < 0x80: out.append(chr(c)); i += 1
        elif c & 0xF0 == 0xE0:
            n = c & 0x0F
            if c == 0xE0: out.append("\0"); i += 1
            elif c == 0xE1: out.append(chr((b[i+1] - 0x40) << 8)); i += 2
            else:
                u = 0
                for k in range(n): u = (u << 7) | (b[i+1+k] & 0x7F)
                out.append(chr(u)); i += 1 + n
        else: out.append(chr(((c - 0x40) << 8) | b[i+1])); i += 2
    return "".join(out)
out = open(sys.argv[2], "w")
stack = [(0, b"")]
n = 0
while stack:
    pos, key = stack.pop()
    u = int(arr[pos]); base = pos ^ offset(u)
    if (u >> 8) & 1:
        out.write(f"{decode(key)}\t{int(arr[base]) & 0x7FFFFFFF}\n"); n += 1
    child = base ^ cs
    ok = child < size
    idx = child[ok]; c = cs[ok]
    hit = labels[idx] == c
    for i, ch in zip(idx[hit].tolist(), c[hit].tolist()): stack.append((i, key + bytes([ch])))
print(n, file=sys.stderr)
