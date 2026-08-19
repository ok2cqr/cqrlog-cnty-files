# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Two things kept together because neither is much use alone:

- `data/dxcc/` — Martin OK1RR's DXCC country file set, a **verbatim** redistribution of
  an upstream tarball.
- `parsers/pascal/` — the reference implementation of the engine that reads it, a
  modernised port of CQRLOG's `odbec.pas` + `znacmech.pas`, proven equivalent to the
  original before that engine was dropped.

`spec/FORMAT.md` and `spec/ALGORITHM.md` are the **language-neutral contract**. They are
normative; the Pascal code is one conforming implementation. Ports in other languages
(Python, PHP intended) are meant to be written from the spec, reading `data/dxcc/`
directly.

## Commands

All Pascal work happens in `parsers/pascal/`. Needs `fpc` 3.2+ only — no Lazarus, no
LCL, no database, **and no data-preparation step** (tables are assembled in memory from
`data/dxcc/` by `uDxccSource` at load time).

```sh
cd parsers/pascal
make                 # build the test runner (tests/dxcctests)
make test            # run all 125 tests, ~4 s
make lookup          # build tools/dxcclookup
make clean
```

Running a subset — the runner is fpcunit's `consoletestrunner`, so `--suite=` takes
either a suite class or a single test name:

```sh
./tests/dxcctests --format=plain --suite=TPatternTests     # one suite
./tests/dxcctests --format=plain --suite=HashMatchesDigit  # one test
./tests/dxcctests -l                                       # list everything
```

Manual checking / differential comparison against a port:

```sh
tools/dxcclookup --call OK1AYY --date 1992-12-12 --explain
tools/dxcclookup --csv qsos.csv           # date,callsign in; resolutions out; summary on stderr
tools/dxcclookup --dump-tables DIR        # in-memory merge, written out
tools/build-tables.sh [outdir]            # the same merge as a shell script
```

`--dump-tables` and `build-tables.sh` must agree byte for byte; that is how a port's
merge gets verified.

Test binaries locate `data/dxcc` and `tests/data` by walking **up from the executable**
(`uTestData.FindUpwards`, max 5 levels), so cwd does not matter.

Packaging a distributable archive (needs **GNU tar** — on macOS `brew install gnu-tar`
and `TAR=gtar`):

```sh
tools/build-cty-archive.sh --out build/cty          # fetch, validate, pack
tools/build-cty-archive.sh --offline --sources DIR  # reuse saved downloads
tools/compare-cty-archives.sh OLD NEW               # shrinkage guard; takes .tar.gz or dirs
```

`.github/workflows/cty-archive.yml` is the same script on `workflow_dispatch`, plus a
release. Its `dry_run` input builds and validates without publishing.

## Architecture

### Resolution is two stages, deliberately not one call

There is no single "callsign → entity" function, because CQRLOG's `id_country` does it
in two steps and discards part of what the first returns. Callers compose:

```pascal
Key := Resolver.EffectiveCallsign(Call, ADate, Resolved, Adif);
Idx := Deleted.Find(Key, ADate, dmPrefix);   { deleted table FIRST }
if Idx = -1 then Idx := Valid.Find(Key, ADate, dmPrefix);
```

Deleted-first is what makes a 1992 `OK1AYY` resolve to Czechoslovakia. Every step of
stage 1 that probes the table passes the date, so splitting is date-sensitive throughout.

### Units, in dependency order

| Unit | Role |
|---|---|
| `uDxccLimits` | the two length limits (40 / 250), with measured maxima |
| `uDxccCollation` | the 256-byte sort order the index is built on |
| `uDxccPattern` | matching, pattern length, specificity |
| `uDxccEntry` | the 12 description fields, date validity |
| `uDxccTable` | `LoadFromString` / `Find` / `Entry` — immutable once loaded |
| `uDxccSuffixRules` | `Exceptions.tab`, `Ambiguous.tbl` |
| `uDxccResolver` | callsign → lookup key, and the deleted-then-valid lookup |
| `uDxccSource` | assembles both tables out of `data/dxcc` |

No dependencies outside FPC's RTL/FCL, and none between units beyond the above.

`TDxccTable` is immutable after load, so concurrent `Find` is safe; reloading is not —
build a new instance and swap the reference.

### The test seam

`tests/uDxccTableIntf.IDxccTable` + `uDxccTestBase.NewTable` (virtual) exist so a second
implementation can be driven through the whole suite. Only `uModernTable` implements it
now; keep the indirection. `tests/uRefParser.pas` is a **second, independent** parser of
the file format written from the format rather than the code — `tFields` compares the
engine against it over every entry of every table.

## Rules that are easy to get wrong

**Do not "fix" the quirks.** The port's rule was *equivalence, not repair*. Several
behaviours look like bugs and are; each changes which country a callsign resolves to,
and hundreds of thousands of logged QSOs already carry those answers. Each is specified
in `spec/ALGORITHM.md` and pinned by a test:

- concatenation order `Country.tab` → `CallResolution.tbl` → `AreaOK1RR.tbl` (the sort is
  stable, ties go to the first entry);
- the five metacharacters `[ ] % # ?` occupying five **consecutive** ranks above every
  alphanumeric — `Find` scans one contiguous range and relies on it;
- bytes 254 and 255 sharing rank 254 (an off-by-one in `odbec.pas`);
- the specificity walk being off by one at both ends (shortstring length byte compared as
  a character; last character never examined);
- 40-char mark / 250-char description truncation;
- winner selection: longest in *pattern positions* (a whole `[…]` class counts as one),
  then more specific, then first in table.

**Do reject the capacity ceilings.** The original capped descriptions at 10 000 (current
files need 9 056) and silently returned "no country" for everything after an overflow.
No ceilings here. Likewise a probe key sorting above everything in the table must return
"no match", not crash.

**Argentina is the one intentional behavioural difference** from the original (province
in character 4; `F, G, I, K` and the ten companion prefixes restored). It moves no DXCC
entity — all provinces share ADIF 100. Do not "restore" the original behaviour, and do
not touch the explicit `/W` and `/X` slash patterns in `AreaOK1RR.tbl`, which are
answered by the whole-string exact match before any rewriting.

**`data/` is upstream's, byte for byte.** Never edit, normalise or reformat it;
`.gitattributes` marks it `-text` so git cannot rewrite line endings. Refreshing = copy
all files at once from the upstream tarball (see `data/README.md`). Data corrections
belong upstream with OK1RR — that is why the verified Czech-call-area fix in
`docs/proposals/` is written down but **not applied**.

**Behaviour changes go in the spec too.** `spec/` is what other implementations are
written from; a change to matching, collation, merging or splitting that lands only in
Pascal has silently forked the contract.

## Packaging (`tools/build-cty-archive.sh`)

The archive holds 15 members: 11 copied out of `data/`, 3 fetched live, and `README`
rendered from `packaging/cty/README` (which carries an `@@VERSION_DATE@@` placeholder —
the committed file must keep it). Upstream's own archive has 14; ours adds
`ContestName.tab`. Generated files never land in `data/`; `build/` is gitignored.

Things that will silently produce a wrong archive if changed:

- **`eqsl.txt` is a byte-for-byte copy.** It contains non-UTF-8 bytes and a stray TAB.
  Never run it through `tr`, `sed` or `iconv` — in a UTF-8 locale `tr` aborts with
  "Illegal byte sequence" after processing a fraction of the file. Everything runs
  under `LC_ALL=C`.
- **`lotw1.txt` is field 1 plus CRLF, nothing else** — no sorting, no dedup, no case
  change; the source is already C-sorted and unique. Use `awk` with `ORS`, not
  `cut | sed 's/$/\r/'`.
- **`MASTER.SCP` is the SuperCheckPartial database on purpose**, not OK1RR's ~5 700-call
  CW list. Do not "restore" the old content.
- `ver.dat` has **no trailing newline** (upstream's is 10 bytes). `gzip -n` **without
  `-9`** — `-9` sets the XFL header byte to 02 where upstream has 00.
- `--sort=name` is a **no-op with `tar -T`**; the file list must be pre-sorted.
- Scripts must stay POSIX `sh`: `/bin/sh` on the runner is dash. No `$'\r'`, no `local`,
  no process substitution, and no `{n}` quantifiers in `awk` (mawk vs BWK awk).

## Known gaps (deliberate, carried over)

- The US-state override is not ported; `us_states.tab` ships but nothing reads it.
- `Ambiguous.tbl` is loaded into `TDxccSuffixRules` but the resolver does not consume it.
- Nothing here is wired into CQRLOG, which still runs its original engine.
- `parsers/pascal/tools/mkconformance` is a committed arm64 Mach-O binary (it emits
  `collation.csv` / `lookup.csv` / `splitting.csv` conformance corpora); its source is not
  in the repository.

## Licence split

Code is GPL v2 (`LICENSE`). `data/` is OK1RR's work under no explicit licence,
redistributed as CQRLOG has always redistributed it — the code licence does not cover it.
