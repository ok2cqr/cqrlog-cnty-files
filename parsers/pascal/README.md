# Pascal parser (reference implementation)

Free Pascal implementation of the DXCC resolution engine specified in
[`../../spec/`](../../spec/). It is the reference implementation.

Needs **`fpc` only** — no Lazarus, no LCL, no database, and no data preparation
step. Deliberately: a build that needs none of those is one any contributor can
run.

```sh
make            # build the test runner
make test       # run it -- 125 tests, ~6 s
make lookup     # build tools/dxcclookup
make clean
```

## Layout

| Path | |
|---|---|
| `src/uDxccCollation.pas` | the custom sort order the index is built on |
| `src/uDxccPattern.pas` | pattern matching, pattern length, specificity |
| `src/uDxccEntry.pas` | the 12 description fields, and date validity |
| `src/uDxccTable.pas` | a loaded table: `LoadFromString`, `Find`, `Entry` |
| `src/uDxccSuffixRules.pas` | `Exceptions.tab` / `Ambiguous.tbl` |
| `src/uDxccResolver.pas` | callsign → lookup key, and lookup |
| `src/uDxccSource.pas` | assembles the tables out of `data/dxcc` |
| `src/uDxccLimits.pas` | the two length limits, with measured maxima |
| `tests/` | the suite |
| `tools/dxcclookup.lpr` | command-line resolver |

The units have no dependencies outside FPC's RTL and FCL, and none on each
other beyond what the table above implies.

## Where to start reading

`uDxccResolver` is the entry point for "callsign → entity", but note there is no
single call that does the whole job — that is intentional, because CQRLOG's own
`id_country` does it in two steps and discards some of what the first step
returns. The composition is:

```pascal
Key := Resolver.EffectiveCallsign(Call, ADate, Resolved, Adif);
Idx := Deleted.Find(Key, ADate, dmPrefix);        { deleted table first }
if Idx = -1 then
  Idx := Valid.Find(Key, ADate, dmPrefix);
Entry := Valid.Entry(Idx);
```

`tools/dxcclookup.lpr` is a working example of exactly this, and the top-level
[README](../../README.md) has a shorter one.

## Threading

`TDxccTable` is immutable once `LoadFromString` returns, so any number of
threads may call `Find` on one instance concurrently. Reloading is *not*
concurrency-safe: build a new instance and swap the reference rather than
reloading in place.

(This is worth knowing because CQRLOG's `ReloadDXCCTables` does dispose+init
without a lock while cluster and RBN worker threads are reading the same
tables.)

## About the tests

125 tests. They were originally written **differentially**, against the original
CQRLOG engine compiled into the same binary, so that every assertion ran twice
and the two answers were compared. That engine is not carried into this
repository, which changes what some of the tests look like:

- Values the original produced are now **literals**, captured from it while it
  was still on hand. Where a comment says "the original produced X", X was
  measured.
- The bulk sweeps that compared engine against engine are gone. What they
  established is recorded in [`../../docs/EQUIVALENCE.md`](../../docs/EQUIVALENCE.md)
  rather than re-run, since there is no longer a second engine to compare with.
- `uDxccTestBase.NewTable` is still a virtual even though only one engine
  remains. It is the seam a port in another language would be driven through:
  wrap it behind `IDxccTable` and it inherits every published test here.

The evidence behind the frozen verdict is in
[`../../docs/EQUIVALENCE.md`](../../docs/EQUIVALENCE.md) — 169 903 461
comparisons, zero disagreements.

| Suite | Tests | |
|---|---:|---|
| `tSmoke` | 7 | data present, tables load, merge order |
| `tPattern` | 31 | matching, modes, winner selection |
| `tDates` | 18 | validity windows |
| `tFields` | 13 | all twelve fields, against an independent parser |
| `tLoading` | 11 | loading, truncation, CRLF, the two variants |
| `tRobustness` | 8 | hostile input, prefix sweeps |
| `tCollation` | 12 | the 256-byte mapping, byte for byte |
| `tArgentina` | 11 | provinces in character 4 |
| `tSplitting` | 14 | callsign → key |

`tests/uRefParser.pas` deserves a mention: it is a second, independent
implementation of the file format, written from the format rather than from the
code. `tFields` compares the engine against it over every entry of every table,
which is what catches a field-parsing change that a hand-written fixture would
not.

## Not done

- The **US-state override** is not ported. `us_states.tab` ships in
  `data/dxcc/` but nothing reads it.
- `Ambiguous.tbl` is loaded into `TDxccSuffixRules` but the resolver does not
  consume it yet.
- Nothing here is wired into CQRLOG. That is a separate piece of work.
