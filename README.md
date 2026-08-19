# cqrlog-cnty-files

DXCC country files and the parser that reads them.

The data is Martin **OK1RR**'s country file set, which has driven CQRLOG's DXCC
resolution for twenty years. The parser is a modernised implementation of the
engine that consumes it, proven to resolve callsigns identically to the original
before being separated out.

The point of keeping them together is that neither is much use without the
other, and both are useful outside CQRLOG.

```
data/          the country files
  dxcc/          what the parser reads
  extra/         small tables CQRLOG needs and the parser does not
spec/          the format and the algorithm, language-neutral
parsers/
  pascal/        the reference implementation (Free Pascal)
tools/         build-tables.sh, for feeding CQRLOG itself
docs/          how the equivalence was established, and open data issues
```

## Quick start

You need `fpc` (Free Pascal 3.2+). No Lazarus, no LCL, no database, and **no
data preparation step**.

```sh
cd parsers/pascal
make test          # 125 tests, ~6 s
make lookup        # build the command-line tool
```

## Examples

### Resolve one callsign

```
$ tools/dxcclookup --call OK1AYY --date 1992-12-12 --explain
callsign : OK1AYY
date     : 1992/12/12
country  : Czechoslovakia
adif     : 218
status   : deleted entity
key      : OK1AYY
pattern  : OK
continent: EU
cq/itu   : 15 / 28
lat/lon  : 49N 20E
valid    : 1945/01/01 - 1992/12/31
table    : country_del.tab
```

The same callsign today is a different entity, which is the whole reason the
date is not optional:

```
$ tools/dxcclookup --call OK1AYY --date 2026-08-19
country  : Czech Republic, Full License
adif     : 503
```

Argentine provinces live in the fourth character of the callsign, and a trailing
letter moves them — `/F` is Santa Fe, applied by rewriting character 4:

```
$ tools/dxcclookup --call LU1AAA/F --date 2020-01-01 --explain
country  : Argentina, Santa Fe (SF)
adif     : 100
key      : LU1FAA
pattern  : LU#F
```

### Resolve a whole log

```
$ tools/dxcclookup --csv qsos.csv
date,callsign,key,adif,country
2020/01/15,OK1ABC,OK1ABC,503,"Czech Republic, Full License"
1992/12/12,OK1AYY,OK1AYY,218,Czechoslovakia
2020/01/01,LU1AAA/F,LU1FAA,100,"Argentina, Santa Fe (SF)"
2020/01/01,OK1ABC/MM,?,,
SUMMARY rows=4 nocountry=1 unparseable=0
```

Input is `date,callsign` with an optional header — the shape you get exporting
`qsodate` and `callsign` from a CQRLOG log. The `?` key on the last row is
maritime mobile: no country, by design. The summary goes to stderr, so the CSV
on stdout stays pipeable.

### Use it from Pascal

The whole API, end to end. Note that there is no file to generate first:
`BuildCountryTable` reads the OK1RR files and merges them in memory.

```pascal
uses uDxccTable, uDxccEntry, uDxccResolver, uDxccSuffixRules, uDxccSource;

var
  Valid, Deleted: TDxccTable;
  Rules: TDxccSuffixRules;
  Resolver: TDxccResolver;
  Key: string;
  Resolved: Boolean;
  Adif, Idx: Integer;
begin
  Valid := TDxccTable.Create;
  Valid.LoadFromString(BuildCountryTable('data/dxcc'));
  Deleted := TDxccTable.Create;
  Deleted.LoadFromString(BuildDeletedTable('data/dxcc'));

  Rules := TDxccSuffixRules.Create;
  Rules.LoadExceptions('data/dxcc/Exceptions.tab');
  Rules.LoadAmbiguous('data/dxcc/Ambiguous.tbl');
  Resolver := TDxccResolver.Create(Valid, Deleted, Rules);

  { OK1ABC/P -> OK1ABC; KL7AA/1 -> W1; LU1AAA/F -> LU1FAA }
  Key := Resolver.EffectiveCallsign('OK1ABC/P', '2020/01/01', Resolved, Adif);

  { Deleted entities are searched first. }
  Idx := Deleted.Find(Key, '2020/01/01', dmPrefix);
  if Idx = -1 then
    Idx := Valid.Find(Key, '2020/01/01', dmPrefix);
  if Idx <> -1 then
    Writeln(Valid.Entry(Idx).Country);
end;
```

`TDxccTable` is immutable once loaded, so any number of threads may call `Find`
on one concurrently. To reload, build a new instance and swap the reference.

### Reading a line by hand

Line 4476 of `AreaOK1RR.tbl`, verbatim:

```
OK1[A-Z]% OK1[A-JL-NPQS-Z]%% OK[2-7][A-Z]% OK[2-7][A-JL-NPQS-Z]%%|Czech Republic, Full License|EU|-1|50.07N|14.42E|28|15||R|2005/05/01-=503
```

Everything before the first `|` is **marks** — four of them here, space
separated. Each becomes its own entry in the index, all sharing one
description. `OK1[A-JL-NPQS-Z]%%` matches `OK1`, then one letter from those
ranges, then two more alphanumerics: so `OK1AYY`, but not `OK1KYY`.

Everything after is the description:

| Field | Value | Note |
|---|---|---|
| country | `Czech Republic, Full License` | what the log displays |
| continent | `EU` | |
| UTC offset | `-1` | |
| latitude | `50.07N` | WGS84 decimal degrees, not min/sec |
| longitude | `14.42E` | |
| ITU zone | `28` | |
| CQ zone | `15` | |
| ADIF column | *(empty)* | supplied by the `=503` below instead |
| flag | `R` | `D` here would mean a deleted entity |
| validity | `2005/05/01-` | open-ended; the default end is 2050/01/01 |
| ADIF | `503` | from the `=503` suffix |

That `2005/05/01` start is why `OK1AYY` resolves differently either side of it,
and — because a shorter wildcard mark outranks the finer ones before that date —
it is also the cause of the open data issue listed under Status.

Full detail in [spec/FORMAT.md](spec/FORMAT.md).

## Writing a parser in another language

This is what the repository is arranged for. Python and PHP ports are the
intended next ones.

1. Read [spec/FORMAT.md](spec/FORMAT.md) and [spec/ALGORITHM.md](spec/ALGORITHM.md).
   Between them they specify the whole thing, with no reference to Pascal.
2. Implement it, reading `data/dxcc/` directly. Assembling the tables is about
   twenty lines — concatenate three files in a fixed order, optionally expand
   the `%`-leading lines, drop bytes below 32. There is deliberately no
   preprocessing step to depend on.
3. Check it against the Pascal one. `tools/dxcclookup --csv` takes a
   `date,callsign` file and prints what it resolved, so running the same input
   through both and diffing the output is the whole comparison. A log export
   makes a good input; so does a list of callsigns built from the table's own
   patterns.

A sketch of step 2, to show the spec is implementable without reading any
Pascal:

```python
from pathlib import Path

def build_country_table(d: Path, expand: bool = True) -> list[str]:
    lines = []
    # The order matters: the sort is stable and ties go to the first entry.
    for name in ("Country.tab", "CallResolution.tbl", "AreaOK1RR.tbl"):
        raw = (d / name).read_bytes()
        # Drop every byte below 32 -- this is what makes the CRLF files load
        # the same as the LF ones.
        text = bytes(b for b in raw if b >= 32 or b == 0x0A).decode("utf-8", "replace")
        lines.extend(text.splitlines())

    if expand:
        # A '%'-leading mark sorts above every alphanumeric and can never be
        # reached by a lookup keyed on the callsign's first character, so each
        # is republished under every letter. Generated lines are not re-expanded.
        lines += [c + ln[1:] for ln in lines if ln.startswith("%")
                             for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
    return lines
```

To check your merge is right, compare against `tools/build-tables.sh`, which
writes the same content out as files.

## The data

`data/dxcc/` is Martin OK1RR's set, dropped in verbatim — same bytes, same line
endings. Refreshing it is a plain copy. See [data/README.md](data/README.md) for
provenance, per-file notes and the rule about replacing all files at once.

`data/extra/` holds `sat_name.tab`, `prop_mode.tab`, `ContestName.tab` and
`iota.tbl`: CQRLOG reads them, the parser does not.

Not included: `lotw1.txt`, `eqsl.txt`, `MASTER.SCP` and `qslmgr.csv`. They are
LoTW/eQSL membership lists, a super-check-partial list and a QSL manager
database — none of them take part in resolving a callsign, and each churns tens
of thousands of lines per refresh. They stay with CQRLOG.

## Status

The Pascal implementation is complete and tested but **not yet wired into
CQRLOG**, which still runs its original engine. Known gaps, carried over
deliberately:

- The **US-state override** is not ported; `us_states.tab` ships but is unread.
- `Ambiguous.tbl` is loaded but not yet consumed by the resolver.
- Czech call areas are unreachable between 1993-01-01 and 2005-04-30. This is a
  data problem, present in the original engine too, and it is written up with a
  verified fix in
  [docs/proposals/](docs/proposals/ctyfiles-ok-license-gap-1993-2005.md). It has
  not been applied, because the fix belongs upstream with OK1RR.

## Licence

The **code** is GPL v2 — see [LICENSE](LICENSE).

The **data** in `data/` is Martin OK1RR's work, redistributed as CQRLOG has
always redistributed it. It is not covered by the code licence. See
[data/README.md](data/README.md).
