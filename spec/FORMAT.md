# File format

Everything a parser needs to read the files in `data/dxcc/`. Written from the
files themselves rather than from any one implementation, so it can be
implemented in any language. Where the format has a quirk that looks like a bug,
it is called out — those quirks decide which country a callsign resolves to, so
reproducing them is not optional.

Companion document: [ALGORITHM.md](ALGORITHM.md), which covers how the files are
merged and how a lookup actually runs.

## Encoding and line endings

Files are byte-oriented. Most are ASCII; `Country.tab` and `iota.tbl` contain a
few UTF-8 characters (`Rēkohu`, a typographic apostrophe). Some files ship with
CRLF, others with LF, and this varies between releases of the set.

**A parser must drop every byte below 32 while reading.** That is what makes the
CRLF files load identically to the LF ones, and it is the rule the original
engine used. Do not special-case CR: bytes 0–31 all go.

## Line shape

Every line in the three country files is:

```
marks|description
```

- **marks** — one or more patterns, separated by spaces. Every mark on the line
  gets its own entry in the index, all sharing the same description. A line with
  no `|` is discarded entirely.
- **description** — the 12 pipe-separated fields below.

A mark longer than **40 characters is truncated** to 40. This is not
hypothetical: the current `CallResolution.tbl` contains a 42-character token. A
description longer than **250 characters is truncated** to 250.

### Marks

| Element | Meaning |
|---|---|
| `A`–`Z`, `0`–`9`, `/` | literal |
| `#` | any single digit |
| `?` | any single letter |
| `%` | any single alphanumeric |
| `[ABC]` | any one of the listed characters |
| `[A-F]` | any character in the range |
| `[A-CX-Z]` | ranges and singles may be combined in one class |
| `=` prefix | the whole callsign must match, not just its start |

A leading `=` marks an **exact** entry: `=2O12L` matches only `2O12L`, while
`OK1` matches `OK1ABC` as a prefix. The `=` is part of the stored mark but is
stripped before the sort key is computed, so `=OK1ABC` and `OK1ABC` compete for
the same position in the index.

## The 12 description fields

Pipe-separated, in this order:

| # | Field | Example | Notes |
|---|---|---|---|
| 0 | country | `Czech Republic, Bohemia` | the string the log displays |
| 1 | continent | `EU` | |
| 2 | UTC offset | `-1` | hours; sign as written |
| 3 | latitude | `49.75N` | WGS84 decimal degrees, **not** min/sec |
| 4 | longitude | `13.38E` | |
| 5 | ITU zone | `28` | may be empty |
| 6 | CQ (WAZ) zone | `15` | may be empty |
| 7 | ADIF column | `503` | often empty; see below |
| 8 | flag | `R` or `D` | `D` marks a deleted entity |
| 9 | validity + ADIF | `1993/01/01-2005/04/30=503` | see below |

Fields 10 and 11 (`ValidFrom`, `ValidTo`) are not stored in the file — they are
parsed out of field 9. Implementations usually expose all twelve.

### Field 9: validity window and ADIF

The last field carries up to three things:

```
1993/01/01-2005/04/30=503
^^^^^^^^^^ ^^^^^^^^^^ ^^^
from       to         ADIF entity number
```

Rules:

- Either end may be omitted: `1989/01/01-` is open-ended, `-1975/07/01` has no
  start.
- A missing start defaults to **1945/01/01**, a missing end to **2050/01/01**.
- `*` means always valid; `!` means never valid.
- Dates compare **lexicographically**, which is why the `YYYY/MM/DD` form
  matters. No date arithmetic is involved or required.
- **Two space-separated windows on one line become two separate records**, each
  with the same description but a different validity.
- If the line has no `=ADIF`, one is **synthesised from field 7**, the ADIF
  column. 340 lines in the current set rely on this.
- `=0` means the entity is explicitly not creditable for DXCC.

## The files

### `Country.tab`

The DXCC entity list — the base layer of the merged table. 340 lines.

```
1A|Sovereign Military Order of Malta|EU|-1|41.9055N|12.4808E|28|15|246||
3D2(C)|Conway Reef (Ceva-I-Ra)|OC|-12|21.7389S|174.6397E|56|32|489||1989/01/01-
```

### `CallResolution.tbl`

Exact-callsign exceptions — operations that do not follow their prefix. Almost
every line starts with `=`, and aliases are space-separated.

```
=1A0KM/IBYO =IBYO/1A0KM|Sovereign Military Order of Malta (no DXCC credit!)|EU|-1|41.9055N|12.4808E|28|15||R|=0
=2O12L|England (London, Eltham Palace), Olympic Games…|EU|0|51.53N|0.12W|27|14||R|2012/07/20-2012/09/09=223
```

This file is **never read on its own**. It is merged into the country table,
which is why an exact `=OK1ABC` and an area pattern `OK#` end up competing
inside one index.

### `AreaOK1RR.tbl`

Call areas, provinces and districts — the finest layer, and the largest file.

```
8J0 8[K-N]0|Japan (Shin'etsu), Special & Event Station|AS|-9|…|R|=339
%%%%/B[A-LRSTYZ]0[A-F]%|China, Xin Jiang (Urumqi City), Guest Operators|AS|-6|…|R|=318
```

204 lines begin with `%`. These need special handling — see the expansion rule
in [ALGORITHM.md](ALGORITHM.md).

### `CountryDel.tab`

Deleted entities, same layout plus the `D` flag. Ships with CRLF. **Searched
before the valid table**, which is how a 1992 Czech callsign resolves to
Czechoslovakia.

```
1B9|Blenheim Reef|AF|-5|5.21S|72.28E|41|39|23|D|-1975/07/01
4W1 4W[02-9]|Yemen Arab Republic|AS|-3|15N|44E|39|21|154|D|-1990/05/21
```

### `Exceptions.tab`

One token per line, no description. A list of two-character suffixes that carry
no location, so `DL1ABC/LH` (a lighthouse) stays Germany rather than becoming
whatever `LH` looks like.

```
1C
1D
1E
```

### `Ambiguous.tbl`

One prefix per line. Prefixes that cannot be resolved from the prefix alone.

```
3D2
3Y0
```

Loaded by the splitting layer. Note that the reference implementation loads this
file but does not yet consume it — see the open item in the top-level README.

### `us_states.tab`

US call area to state mapping, comma-separated, a different shape from the rest:

```
W0|USA, Colorado|CO|NA|+7|7|4|39.0646N|105.3272W|291
```

Present in `data/dxcc/` because it belongs to DXCC resolution, but the reference
parser does not read it yet (the US-state override is not ported).

## Files deliberately not here

`lotw1.txt`, `eqsl.txt`, `MASTER.SCP` and `qslmgr.csv` are part of the CQRLOG
data set but play no part in resolving a callsign to a country — they are LoTW
and eQSL membership lists, a super-check-partial list and a QSL manager
database. They are not in this repository. `data/extra/` holds the small
lookup tables that CQRLOG needs and the parser does not.
