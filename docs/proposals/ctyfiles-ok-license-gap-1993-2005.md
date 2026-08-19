# Proposal: Czech call areas are unreachable between 1993-01-01 and 2005-04-30

**Status: APPLIED 2026-08-19** to `data/dxcc/AreaOK1RR.tbl`, as a **local
patch on top of OK1RR's set**.

That last part is the catch: `data/dxcc/` is a wholesale drop-in, so the next
refresh will silently drop this change. It has to be re-applied by hand until
OK1RR takes it upstream — see the "Local patches" section of
[../../data/README.md](../../data/README.md), which lists it, and `tSmoke`,
whose pinned mark count (21564) fails if it goes missing.

*Moved here from the CQRLOG repository, where the analysis was originally done
with `tools/logdiff` against the old and new engines side by side. That tool
does not exist here — the old engine is not carried into this repository — so
the reproduction steps below are rewritten for `tools/dxcclookup`. The findings
themselves are unchanged; see [../EQUIVALENCE.md](../EQUIVALENCE.md).*

## The problem

A plain Czech callsign worked between the split of Czechoslovakia and
2005-04-30 resolves to *"Czech Rep., Special & Contest Station"* instead of
*"Czech Republic, Bohemia"* or *"…, Morava & Silesia"*.

```
OK1AYY on 1998-06-15   ->  mark OK[1-7]%   "Czech Rep., Special & Contest Station"
OK1AYY on 2026-08-19   ->  mark OK1[A-JL-NPQS-Z]%%   "Czech Republic, Full License"
```

The ADIF is right either way (503), so DXCC standings are unaffected. What is
wrong is the country string, which is what the log shows and what any
per-area statistic reads.

Both the legacy engine (`znacmech.Tseznam`) and the new one (`TDxccTable`)
produce this, identically — it is not something the parser rewrite
introduced. It has been CQRLOG's behaviour since the entries were written.

## Why it happens

`TDxccTable.Find` (and `najdis_s2` before it) ranks candidate marks by
**`PatternLength`** — the number of pattern positions, where a whole `[…]`
class counts as one. `IsMoreSpecific` is only a tie-break between marks of
*equal* length. And in prefix mode a mark only has to match the *beginning* of
the callsign; whatever is left over is free.

So for `OK1AYY` on any date in the window:

| mark | window | positions | matches? |
|---|---|---|---|
| `OK1` | `1993/01/01-2005/04/30` | 3 | yes |
| `OK[1-7]%` | `1993/01/01-` | **4** | yes — consumes `OK1A`, ignores `YY` |
| `OK1[A-JL-NPQS-Z]%%` | `2005/05/01-` | 6 | not valid on this date |

`OK[1-7]%` wins on length. It was clearly written for four-character contest
calls, but nothing anchors its end, so it swallows every longer Czech call as
well — and before 2005-05-01 there is no longer mark to outrank it.

The area entries `OK1` (3) and `OK2` (3) are therefore **unreachable** in that
window for any callsign of four characters or more. Only a bare three-character
`OK1` reaches them:

```
OK1     1993-01-01  ->  OK1        Czech Republic, Bohemia
OK1A    1993-01-01  ->  OK[1-7]%   Czech Rep., Special & Contest Station
OK1AYY  1993-01-01  ->  OK[1-7]%   Czech Rep., Special & Contest Station
```

## What is NOT affected — checked, not assumed

- **Slovakia.** The OM entries were written with both a short contest form and
  a longer individual form, all from `1993/01/01`, so there is no cliff:
  `OM3EE`→`OM3[A-Z]%`, `OM3EEE`→`OM3[A-JL-QS-Z]%%`, both correct at any date.
- **Czech club stations.** `OK1K%% OK1O%% OK1R%%` is 6 positions with window
  `1993/01/01-2005/04/30`, so it already outranks `OK[1-7]%`.
  `OK1KAB`→`Czech Republic, Bohemia, Club Station` on 1998-06-15.
- **Genuine four-character contest calls.** `OK1A` stays *Special & Contest*,
  which is what it is.
- **Special stations.** `OK5XYZ`→`OK[5-7]%%%`, unchanged.
- **Everything before 1993.** Handled by `country_del.tab`
  (`OK O[L-M]|Czechoslovakia|…|218|D|-1992/12/31`).

## The change

Two lines, mirroring the structure the 2005+ entry already uses, scoped to the
earlier window. The character class `[A-JL-NPQS-Z]` deliberately excludes
K, O and R so club stations keep their own entries.

Insert after `AreaOK1RR.tbl:4476` (the `Czech Republic, Full License` line):

```
OK1[A-Z]% OK1[A-JL-NPQS-Z]%%|Czech Republic, Bohemia|EU|-1|50.07N|14.42E|28|15||R|1993/01/01-2005/04/30=503
OK2[A-Z]% OK2[A-JL-NPQS-Z]%%|Czech Republic, Morava & Silesia|EU|-1|49.20N|16.61E|28|15||R|1993/01/01-2005/04/30=503
```

Only OK1 and OK2 are covered, because those are the only areas the pre-2005
data names (`AreaOK1RR.tbl:4468` and `:4470`). OK3–OK4 had no area entry in
that period and OK5–OK7 are Special Station; inventing entries for them would
be a different decision, made without data.

## Evidence it does what it should

Built into a scratch copy of the table set and compared against the unpatched
one, over the whole 58 184-QSO reference log, one row at a time:

```
QSOs whose country string changed      890   (458 Bohemia, 432 Morava & Silesia)
QSOs whose ADIF changed                  0
dates touched                   1998-08-10 .. 2005-03-26   (inside the window)
anything else in the log changed        no
```

Boundary behaviour, on the patched tables:

```
OK1AYY  1998-06-15  OK1[A-JL-NPQS-Z]%%      Czech Republic, Bohemia
OK1AYY  2005-04-30  OK1[A-JL-NPQS-Z]%%      Czech Republic, Bohemia
OK1AYY  2005-05-01  OK1[A-JL-NPQS-Z]%%      Czech Republic, Full License
OK2ABC  2005-04-30  OK2[A-JL-NPQS-Z]%%      Czech Republic, Morava & Silesia
OK2ABC  2005-05-01  OK[2-7][A-JL-NPQS-Z]%%  Czech Republic, Full License
OK1KAB  1998-06-15  OK1K%%                  Czech Republic, Bohemia, Club Station
OK1A    1998-06-15  OK[1-7]%                Czech Rep., Special & Contest Station
```

Both engines still agree on the patched data over the whole log:
`SUMMARY rows=58184 dxcc=0 fields=0 key=0 pattern=0`.

## Before applying it, decide where

`data/dxcc/` is **not** maintained here — it is a drop-in of OK1RR's country
file set, shipped as `cqrlog-cty<date>.tar.gz` and replaced wholesale on every
refresh. A local edit to `AreaOK1RR.tbl` is overwritten by the next such update
and leaves no trace of why it was there.

So this belongs upstream with OK1RR. Applying it locally is reasonable as a
stopgap, but it needs to be re-applied after every country-file refresh —
which is exactly the kind of thing that gets forgotten.

## How to reproduce the check

```sh
cd parsers/pascal && make lookup

# what it does today
tools/dxcclookup --call OK1AYY --date 1998-06-15 --explain

# copy data/dxcc somewhere scratch, apply the patch there, then
tools/dxcclookup --call OK1AYY --date 1998-06-15 --explain --data /path/to/patched

# whole-log before/after: run --csv both ways and diff the output
```

Users only see the change after *Import DXCC data*, or on a fresh profile —
`country.tab` is built once and cached in `~/.config/cqrlog/dxcc_data/`.
