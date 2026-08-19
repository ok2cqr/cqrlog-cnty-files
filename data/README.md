# The data

## Provenance

These files are the CQRLOG country file set, maintained by **Martin, OK1RR**
(`martin@ok1rr.com`). They are not authored here. This repository redistributes
them and documents their format; corrections to the *data* belong upstream with
OK1RR, not in a pull request here.

Upstream distributes the set as a dated tarball, `cqrlog-cty<YYMMDD>.tar.gz` —
the number is both the version and the release date. CQRLOG fetches it from
`https://www.ok2cqr.com/linux/cqrlog/ctyfiles/`, checking `ver.dat` at startup.

The copy here was taken from the CQRLOG working tree in August 2026; the newest
files in it are dated February 2026.

## Licence

There is no licence text in the upstream set — only the maintainer's contact
address. It has been redistributed with CQRLOG (GPL v2) for two decades with
OK1RR's knowledge and credited in CQRLOG's README as "country tables developed
by OK1RR".

**The `LICENSE` file at the root of this repository covers the code, not this
directory.** If you redistribute the data, credit OK1RR.

## Layout

### `dxcc/` — what the parser reads

| File | Contents |
|---|---|
| `Country.tab` | the main DXCC entity list |
| `CallResolution.tbl` | exact-callsign exceptions |
| `AreaOK1RR.tbl` | call areas, provinces, districts |
| `CountryDel.tab` | deleted entities |
| `Exceptions.tab` | two-character suffixes to ignore (`DL1ABC/LH` is still Germany) |
| `Ambiguous.tbl` | prefixes that cannot be resolved from the prefix alone |
| `us_states.tab` | US call area → state |

The first three are concatenated into one table before any lookup happens, in
that order — see [../spec/ALGORITHM.md](../spec/ALGORITHM.md). `us_states.tab`
belongs to DXCC resolution but the reference parser does not read it yet.

Note the upstream README calls `Exceptions.tab` "Exceptions.tbl". The file on
disk has always been `.tab`; the README is wrong, not the file.

### `extra/` — CQRLOG reads these, the parser does not

| File | Contents |
|---|---|
| `iota.tbl` | the IOTA island list (CQRLOG loads it into MySQL) |
| `sat_name.tab` | satellite short name → full name |
| `prop_mode.tab` | ADIF propagation modes |
| `ContestName.tab` | ADIF contest id → human name |

`ContestName.tab` is not mentioned in the upstream README at all, and CQRLOG
only installs it after a manual country-file import.

### Not in this repository

`lotw1.txt` (LoTW users), `eqsl.txt` (eQSL AG users), `MASTER.SCP` (super check
partials) and `qslmgr.csv` (QSL managers) are part of the upstream set but play
no part in resolving a callsign to a country. They are also large and highly
volatile — a single refresh rewrites tens of thousands of lines. They stay with
CQRLOG.

Storing them is not the only way to ship them, though.
`../tools/build-cty-archive.sh` fetches the first three from their live sources
when it assembles a distributable `cqrlog-cty.tar.gz`, so a complete archive can
be produced without any of that churn landing in git history. `qslmgr.csv` has
no such source here and is simply absent.

## Refreshing

Unpack the upstream tarball and copy the files in. That is the whole procedure:
nothing is generated, transformed or normalised, so the files here stay byte
identical to what OK1RR shipped.

```sh
tar xzf cqrlog-cty260205.tar.gz -C /tmp/cty
cp /tmp/cty/{Country.tab,CallResolution.tbl,AreaOK1RR.tbl,CountryDel.tab,\
Exceptions.tab,Ambiguous.tbl,us_states.tab} data/dxcc/
cp /tmp/cty/{iota.tbl,sat_name.tab,prop_mode.tab,ContestName.tab} data/extra/
chmod 0644 data/dxcc/* data/extra/*
```

Then, in this order:

```sh
cd parsers/pascal && make test
```

`tSmoke` pins the number of marks the tables load to, so a refresh that
silently loses half a file fails there. Beyond that the suite tests behaviour,
not data, so it will not tell you which callsigns changed meaning.

If you want to know that, diff the resolutions before and after:

```sh
# before replacing the files
tools/dxcclookup --csv calls.csv > /tmp/before.csv
# after
tools/dxcclookup --csv calls.csv > /tmp/after.csv
diff /tmp/before.csv /tmp/after.csv
```

where `calls.csv` is a `date,callsign` export from a log. Worth doing for a big
refresh, and worth skipping for a routine one.

`chmod 0644` is not cosmetic: the upstream tarball unpacks with the executable
bit set on plain data files.

**Replace all files at once.** The upstream README is emphatic about this, and
it is right: the tables cross-reference each other, and mixing versions
desynchronises them.

## Notes carried over from upstream

- Geographic coordinates use **WGS 84 in decimal notation**, not
  minutes/seconds.
- Several operations are deliberately not creditable for DXCC — stations aboard
  ships and museum ships, drifting ice, arctic ski expeditions. These carry
  `=0` as their ADIF.
- Do not hand-author country files. The upstream README warns that malformed
  ones cause crashes and wrong statistics; the parser here is more robust about
  it, but the statistics are still wrong.
- After updating country files in CQRLOG, run "Rebuild DXCC statistics".

## A known data issue

Czech call areas are unreachable between 1993-01-01 and 2005-04-30: a plain OK
callsign resolves to "Czech Rep., Special & Contest Station" rather than Bohemia
or Morava & Silesia. The ADIF is correct either way, so DXCC standings are
unaffected; the country string is not.

This is a data problem, not a parser one — the original CQRLOG engine does it
identically. Written up with a verified two-line change in
[../docs/proposals/ctyfiles-ok-license-gap-1993-2005.md](../docs/proposals/ctyfiles-ok-license-gap-1993-2005.md).
**Not applied**, because it belongs upstream.
