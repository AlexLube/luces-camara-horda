#!/usr/bin/env python3
"""Summarise balance sweep output (lines starting with BAL)."""
import json, sys, statistics as S
rows = [json.loads(l[4:]) for f in sys.argv[1:] for l in open(f) if l.startswith("BAL ")]
print(f"{len(rows)} runs")
print(f"{'stage':24} {'char':10} {'cl':3} {'min':>5} {'done':>4} {'lvl':>4} {'kills':>6} {'earn':>5} {'evo':>3} {'L5':>3} {'L10':>3} {'L20':>3}")
for r in sorted(rows, key=lambda r: (r['stage'], r['char'], r['clauses'])):
    m = r['marks']
    g = lambda k: m.get(k, {}).get('lvl', '')
    print(f"{r['stage'][:24]:24} {r['char'][:10]:10} {r['clauses'][:3]:3} {r['time']/60:5.1f} {('yes' if r['done'] else ''):>4} {r['level']:4} {r['kills']:6} {r['earned']:5} {r['evo']:3} {g('5'):>3} {g('10'):>3} {g('20'):>3}")
for cl in sorted({r['clauses'] for r in rows}):
    rs = [r for r in rows if r['clauses'] == cl]
    print(f"clauses={cl}: survive {S.median(r['time'] for r in rs)/60:.1f} min median, {sum(r['done'] for r in rs)}/{len(rs)} complete, earned median {S.median(r['earned'] for r in rs):.0f}")
