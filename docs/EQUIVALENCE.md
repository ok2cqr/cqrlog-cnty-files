# Equivalence with the original CQRLOG engine

Why this parser can be trusted to resolve callsigns the way CQRLOG has for
twenty years, given that the engine which did so is not the one here.

## What was replaced

CQRLOG resolved DXCC prefixes with `src/odbec.pas` (91 lines) and
`src/znacmech.pas` (982 lines), inherited from the original CQRLOG: Turbo Pascal
`object` types, Czech identifiers, shortstrings, a hand-rolled hash table, merge
sort and manual memory management, and no tests. Everything depended on it — QSO
entry, ADIF import, DX cluster, RBN, statistics, exports.

The implementation in `parsers/pascal/` replaces it. The rule during that work
was **equivalence, not repair**: historical oddities were reproduced on purpose,
because each of them can change which country a callsign resolves to, and
hundreds of thousands of logged QSOs already carry those answers. They are
listed in [../spec/ALGORITHM.md](../spec/ALGORITHM.md).

The old engine is not carried into this repository. What follows is the evidence
that was gathered while it was still on hand.

## How it was checked

Both engines were built into one test binary behind a common interface, so every
assertion ran twice, and then compared exhaustively.

**Against a synthetic corpus.** 93 271 callsigns derived from the tables' own
patterns — one per mark, filled in several ways, plus one-character-longer and
shorter variants — crossed with 8 dates, 3 match modes and both `country.tab`
variants. Roughly 2.9 million lookups per engine, comparing the matched pattern
and all twelve fields.

> Last full run: **12 min 54 s, zero disagreements.**

**Against a real log.** The same comparison following the whole `id_country`
path, splitter included, over 58 184 (date, callsign) pairs from Petr's log,
1998–2026 — 21 083 distinct callsigns, 2 281 of them slashed. Run against all
three table sets a user can have: generated expanded, generated plain, and an
installed `~/.config/cqrlog/dxcc_data`.

> **Zero differences of any class**, ~3 s per run.

**Across the date axis.** A log only covers the dates its owner was on the air,
and **789 of the tables' 2 277 validity boundaries lie before the first QSO** in
that log. Worse, the splitter had only ever been compared at a single date,
`2020/01/01`. So the log's callsigns were replayed at every `ValidFrom` and
`ValidTo` and the day either side — 5 516 dates, back to 1939 — and the slash
matrix was pinned at 20 dates on real transitions (German unification, the
dissolution of the USSR, the OK/OM split, Montenegro, South Sudan, Kosovo) plus
both edges of the date format.

| Sweep | Comparisons | Differences |
|---|---:|---:|
| expanded × 5 516 dates | 116 288 312 | 0 |
| plain, every 5th | 23 260 972 | 0 |
| installed `dxcc_data`, every 5th × 4 977 dates | 20 988 009 | 0 |
| expanded, slashed callsigns only | 9 366 168 | 0 |
| **total** | **169 903 461** | **0** |

## The one intentional difference

Argentine province suffixes. The original restricted the character-4 rewrite to
a set of suffix letters that omitted F, G, I, K and W, and its `/M` and `/P`
shortcut tested only for the literal prefix `LU`. The result was that
`LU1AAA/F` and the ten companion prefixes lost their province.

This implementation fixes both. Full reasoning in
[../spec/ALGORITHM.md](../spec/ALGORITHM.md) §7.

The fix **moves no DXCC entity**: every Argentine province shares ADIF 100, so
what changes is the province string. Verified over the 58 184-QSO log — zero
ADIF differences.

A claim that circulated during this work and was wrong: that `LU1AAA/F` used to
resolve as *France*. It did not. The generic branch sets the key to the bare
suffix, but the next statement probes `prefix[1..2] + '/' + suffix` — `LU/F` —
in prefix mode, and `LU` is itself a mark, so the probe hit and the old answer
was plain **Argentina**. The same mechanism makes `DL1ABC/F` resolve as Germany.
It is recorded here because the corrected version is what the tests assert.

## Findings that are not engine differences

**14 callsigns in a 58 184-QSO log resolve to no country in either engine**:
`03UA`, `403RB`, `404A`, `7NVOK7NV`, `DIRK1YZW`, `L632A`, `MQ3QYL`, `MQ5ZZ`,
`MQ6X`, `PJ3T`, `RN1KA`, `RN1KW`, `RV6SV`, `UH2U`. Against older installed files
it was 16 — `A8OK` and `MR5W` are fixed by newer data. A data gap, not a parser
one.

**Czech call areas were unreachable between 1993-01-01 and 2005-04-30.** Both
engines did this identically, on the data as OK1RR ships it — which is what
makes it a data finding rather than an engine difference. Written up in
[proposals/ctyfiles-ok-license-gap-1993-2005.md](proposals/ctyfiles-ok-license-gap-1993-2005.md)
and since applied to `data/dxcc/AreaOK1RR.tbl` as a local patch.

Note what this means for the equivalence figures above: they were measured on
the **unpatched** data, and they still stand for it. The patch adds two marks
that outrank an existing one inside that window, so on the patched data the two
engines still agree with each other: the proposal records a full-log run on a
patched copy of the tables, `rows=58184 dxcc=0 fields=0 key=0 pattern=0`, made
while both engines were still available. What does change is the answer itself
— 890 QSOs in the reference log resolve to a different country string than they
did before, deliberately.

## What was not compared

- The US-state override — not ported, and `us_states.tab` is still unread.
- `DXCCRefArray[adif].pref`, which comes from MySQL rather than from these
  files.

## Bugs found in CQRLOG along the way

Recorded here because they are the reason some of this is worth re-checking when
the parser is eventually wired in, not because they belong to this repository:

- `dDXCluster.pas:725` — `id_country` returns an uninitialised result for an
  empty callsign, where `dDXCC.pas:700` returns 0.
- `dDXCluster.pas:560` — an extra `exit` makes the following lines unreachable,
  so `OK2CQR/XE1` resolves differently in the cluster than in the log.
- `dDXCluster.pas:431,451` — missing `UpperCase` on continent.
- `dDXCC.pas:747,751` — a dead branch.
- `dData.pas:1057` vs `fImportProgress.pas:344` — the two `country.tab` builders
  disagree, which is why both variants are specified here.
- `ReloadDXCCTables` swaps the tables with no lock while cluster and RBN worker
  threads are reading them. `TDxccTable` is immutable once loaded, which makes
  the safe fix available: build a new instance and swap the reference.
