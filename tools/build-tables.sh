#!/bin/sh
# Writes the merged table files that CQRLOG keeps in ~/.config/cqrlog/dxcc_data.
#
# NOTHING IN THIS REPOSITORY NEEDS THIS SCRIPT.  The parsers assemble the same
# content in memory when they load (see parsers/pascal/src/uDxccSource.pas and
# spec/ALGORITHM.md), which is why there is no build step before "make test".
#
# It is here for two other jobs:
#
#   * feeding a CQRLOG installation, which reads an already-merged country.tab
#     rather than the OK1RR files;
#   * checking a port -- if your implementation's merge does not produce these
#     bytes, it has the rules wrong.
#
# The two variants exist because CQRLOG builds country.tab in two places and
# they disagree:
#
#   dData.pas:1057   PrepareDXCCData, first run.  Plain concatenation.
#                    -> country-plain.tab
#   fImportProgress.pas:344-351   manual "Import DXCC data".  Same, then every
#                    '%'-leading line is appended again 26 times with that '%'
#                    replaced by 'A'..'Z'.  -> country-expanded.tab
#
# Both are in the field. The expanded one is the reference.
#
# Usage: tools/build-tables.sh [output-dir]     (default: ./build)

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
cty="$repo/data/dxcc"
out="${1:-$repo/build}"

mkdir -p "$out"

for f in Country.tab CallResolution.tbl AreaOK1RR.tbl CountryDel.tab \
         Exceptions.tab Ambiguous.tbl; do
    if [ ! -f "$cty/$f" ]; then
        echo "build-tables.sh: missing $cty/$f" >&2
        exit 1
    fi
done

# CR is dropped here so the output is stable regardless of which files in the
# set happen to ship with CRLF this month.  The parsers do the same, by
# ignoring every byte below 32.
strip_cr() { tr -d '\r' < "$1"; }

# --- country-plain.tab -------------------------------------------------
# The order is load-bearing: the index sort is stable and lookup keeps the
# first of two equally good candidates, so whichever file contributed a mark
# first wins a tie.
{
    strip_cr "$cty/Country.tab"
    strip_cr "$cty/CallResolution.tbl"
    strip_cr "$cty/AreaOK1RR.tbl"
} > "$out/country-plain.tab"

# --- country-expanded.tab ----------------------------------------------
# The Pascal loop this mirrors evaluates its upper bound once, so the lines it
# appends are never revisited: generated lines all land after the originals and
# are not themselves re-expanded.
{
    cat "$out/country-plain.tab"
    awk '/^%/ {
        rest = substr($0, 2)
        for (i = 65; i <= 90; i++) printf "%c%s\n", i, rest
    }' "$out/country-plain.tab"
} > "$out/country-expanded.tab"

# --- the three that are copied, not merged -----------------------------
strip_cr "$cty/CountryDel.tab" > "$out/country_del.tab"
strip_cr "$cty/Exceptions.tab" > "$out/exceptions.tab"
strip_cr "$cty/Ambiguous.tbl"  > "$out/ambiguous.tab"

for f in country-plain.tab country-expanded.tab country_del.tab \
         exceptions.tab ambiguous.tab; do
    printf '%-24s %8d lines  %10d bytes\n' \
        "$f" "$(wc -l < "$out/$f")" "$(wc -c < "$out/$f")"
done
