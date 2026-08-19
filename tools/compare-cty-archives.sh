#!/bin/sh
# Compares two country file archives and refuses the new one if a refreshed
# member shrank implausibly.
#
# Why this exists: every structural check in build-cty-archive.sh passes on a
# well-formed but STALE or PARTIAL response -- eQSL serving yesterday's
# half-written export, say, or a CDN handing back a truncated-then-cached copy.
# Such a body has the right header, the right line endings and the right shape.
# The only thing that gives it away is that it is much smaller than the one
# that shipped last time. This is the check that notices.
#
# Usage:
#   tools/compare-cty-archives.sh OLD NEW
#
# OLD and NEW may each be a .tar.gz or an already-unpacked directory, so this
# runs offline against a previously released archive.
#
# Exit 0 when the new archive is acceptable, 1 when it is not. Set FORCE=1 to
# downgrade every hard failure to a warning.
#
# Environment: TAR=gtar overrides tar.

set -eu

LC_ALL=C
export LC_ALL

TAR="${TAR:-tar}"
FORCE="${FORCE:-0}"

# A refreshed member may lose this much before it stops looking like organic
# churn. 5% of LoTW is roughly a decade of growth run backwards.
MAX_LINE_LOSS_PCT=5
MAX_BYTE_LOSS_PCT=10

REFRESHED='lotw1.txt eqsl.txt MASTER.SCP'
CARRIED='Country.tab CallResolution.tbl AreaOK1RR.tbl CountryDel.tab Exceptions.tab Ambiguous.tbl us_states.tab iota.tbl sat_name.tab prop_mode.tab ContestName.tab'

failures=0
warnings=0

fail() {
    if [ "$FORCE" = 1 ]; then
        warnings=$((warnings + 1))
        printf 'FORCED PAST: %s\n' "$*" >&2
        [ -n "${GITHUB_ACTIONS:-}" ] && printf '::warning::forced past: %s\n' "$*" || true
    else
        failures=$((failures + 1))
        printf 'FAIL: %s\n' "$*" >&2
        [ -n "${GITHUB_ACTIONS:-}" ] && printf '::error::%s\n' "$*" || true
    fi
}
warn() {
    warnings=$((warnings + 1))
    printf 'warn: %s\n' "$*" >&2
    [ -n "${GITHUB_ACTIONS:-}" ] && printf '::warning::%s\n' "$*" || true
}
note() { printf '  %s\n' "$*"; }

[ $# -eq 2 ] || { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/cty-compare.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

unpack() { # path dest -> prints dest
    _p=$1; _d=$2
    if [ -d "$_p" ]; then
        printf '%s' "$_p"
    else
        [ -f "$_p" ] || { printf 'compare-cty-archives: no such archive: %s\n' "$_p" >&2; exit 2; }
        mkdir -p "$_d"
        "$TAR" xzf "$_p" -C "$_d"
        printf '%s' "$_d"
    fi
}

old=$(unpack "$1" "$work/old")
new=$(unpack "$2" "$work/new")

lines() { wc -l < "$1" | tr -d ' '; }
bytes() { wc -c < "$1" | tr -d ' '; }

echo 'Refreshed members'
for f in $REFRESHED; do
    if [ ! -f "$new/$f" ]; then
        fail "$f is missing from the new archive"
        continue
    fi
    if [ ! -f "$old/$f" ]; then
        note "$f: not in the old archive, nothing to compare"
        continue
    fi

    on=$(lines "$old/$f"); nn=$(lines "$new/$f")
    ob=$(bytes "$old/$f"); nb=$(bytes "$new/$f")

    if cmp -s "$old/$f" "$new/$f"; then
        warn "$f is byte-identical to the previous release (stale mirror, or a same-day rebuild)"
        note "$f: $nn lines, $nb bytes (unchanged)"
        continue
    fi

    # Integer comparison, no bc: a*100 < b*(100-pct).
    if [ $((nn * 100)) -lt $((on * (100 - MAX_LINE_LOSS_PCT))) ]; then
        fail "$f lost more than $MAX_LINE_LOSS_PCT% of its lines: $on -> $nn"
    elif [ "$nn" -lt "$on" ]; then
        warn "$f shrank: $on -> $nn lines"
    fi
    if [ $((nb * 100)) -lt $((ob * (100 - MAX_BYTE_LOSS_PCT))) ]; then
        fail "$f lost more than $MAX_BYTE_LOSS_PCT% of its bytes: $ob -> $nb"
    fi

    note "$f: $on -> $nn lines, $ob -> $nb bytes"
done

echo 'Carried-over data files'
differing=''
for f in $CARRIED; do
    if [ ! -f "$new/$f" ]; then
        fail "$f is missing from the new archive"
        continue
    fi
    [ -f "$old/$f" ] || continue
    cmp -s "$old/$f" "$new/$f" || differing="$differing $f"
done
if [ -n "$differing" ]; then
    # A legitimate data/ refresh lands here. It must not block a release.
    warn "data files changed since the previous release:$differing"
else
    note 'all unchanged'
fi

echo
if [ "$failures" -gt 0 ]; then
    printf '%s failure(s), %s warning(s) -- new archive rejected\n' "$failures" "$warnings"
    printf 'Re-run with the force input if the shrinkage is genuine.\n'
    exit 1
fi
printf 'OK: %s warning(s)\n' "$warnings"
