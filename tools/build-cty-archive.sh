#!/bin/sh
# Builds cqrlog-cty.tar.gz -- the CQRLOG country file set -- out of this
# repository plus three files refetched from their live sources.
#
# Eleven of the fifteen files are OK1RR's, copied byte for byte out of data/.
# The other three churn tens of thousands of lines per refresh and are
# deliberately NOT in the repository (see data/README.md), so they are fetched
# here instead:
#
#   lotw1.txt    derived from lotw.arrl.org/lotw-user-activity.csv
#                -- field 1 of each row, CRLF line endings.  Nothing else:
#                the source is already C-sorted and has no duplicates.
#   eqsl.txt     verbatim copy of eqsl.cc's AGMemberList.txt, header line and
#                all.  It carries non-UTF-8 bytes and a stray TAB, so it is
#                copied, never filtered.
#   MASTER.SCP   verbatim copy of supercheckpartial.com's MASTER.SCP.  NOTE
#                this is the full SCP database, not OK1RR's hand-curated CW
#                list -- a deliberate substitution, see packaging/cty/README.
#
# Everything runs under LC_ALL=C.  A single tr(1) in a UTF-8 locale aborts on
# eqsl.txt with "Illegal byte sequence" and silently processes a fraction of
# the file, which is exactly the class of bug this script exists to avoid.
#
# The archive is reproducible: same three source bodies plus the same
# --version-date give byte-identical output.
#
# Usage:
#   tools/build-cty-archive.sh [--version-date YYYY-MM-DD] [--out DIR]
#                              [--sources DIR] [--offline]
#
#   --version-date  version stamp; also every member's mtime and ver.dat's
#                   content.  Default: today, UTC.
#   --out           output directory.  Default: ./build/cty
#   --sources       reuse (or populate) raw downloads here instead of a temp
#                   dir.  Default: <out>/src
#   --offline       do not download; --sources must already hold the files.
#
# Environment: TAR=gtar and GZIP_BIN=... override the tools.  GNU tar is
# required; macOS ships bsdtar, so use `brew install gnu-tar` and TAR=gtar.

set -eu

LC_ALL=C
export LC_ALL

# --- configuration -----------------------------------------------------

LOTW_URL="${LOTW_URL:-https://lotw.arrl.org/lotw-user-activity.csv}"
EQSL_URL="${EQSL_URL:-https://www.eqsl.cc/qslcard/DownloadedFiles/AGMemberList.txt}"
SCP_URL="${SCP_URL:-https://www.supercheckpartial.com/downloads/MASTER.SCP}"

ARCHIVE_NAME=cqrlog-cty.tar.gz
USER_AGENT='cqrlog-cnty-files (+https://github.com/ok2cqr/cqrlog-cnty-files)'

# Minimum plausible sizes.  Set well below today's values -- these catch a
# truncated transfer or a stub page, not slow organic shrinkage.
LOTW_MIN_BYTES=2500000
LOTW_MIN_LINES=200000
EQSL_MIN_BYTES=1200000
EQSL_MIN_LINES=150000
SCP_MIN_BYTES=300000
SCP_MIN_LINES=40000

DXCC_FILES='Country.tab CallResolution.tbl AreaOK1RR.tbl CountryDel.tab Exceptions.tab Ambiguous.tbl us_states.tab'
EXTRA_FILES='iota.tbl sat_name.tab prop_mode.tab ContestName.tab'
MEMBER_COUNT=15

TAR="${TAR:-tar}"
GZIP_BIN="${GZIP_BIN:-gzip}"

# --- plumbing ----------------------------------------------------------

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

warnings=0

die()  { printf 'build-cty-archive: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }
warn() {
    warnings=$((warnings + 1))
    printf 'build-cty-archive: WARNING: %s\n' "$*" >&2
    [ -n "${GITHUB_ACTIONS:-}" ] && printf '::warning::%s\n' "$*" || true
}

lines()   { wc -l < "$1" | tr -d ' '; }
bytes()   { wc -c < "$1" | tr -d ' '; }
# A truncated transfer nearly always stops mid-line, so "ends with newline" is
# a cheap and surprisingly effective completeness check.
ends_nl() { [ "$(tail -c1 "$1" | wc -l | tr -d ' ')" = 1 ]; }
non_crlf() { awk '!/\r$/ { n++ } END { print n+0 }' "$1"; }
looks_html() {
    head -c 1024 "$1" | grep -qiE '<!doctype html|<html|<head|<title|<body'
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Epoch for a YYYY-MM-DD date, GNU and BSD date both handled.
epoch_of() {
    if date --version >/dev/null 2>&1; then
        date -u -d "$1T00:00:00Z" +%s
    else
        date -u -j -f '%Y-%m-%dT%H:%M:%S' "$1T00:00:00" +%s
    fi
}

today_utc() {
    if date --version >/dev/null 2>&1; then
        date -u +%F
    else
        date -u +%Y-%m-%d
    fi
}

# --- arguments ---------------------------------------------------------

VERSION_DATE=''
OUT=''
SOURCES=''
OFFLINE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version-date) VERSION_DATE="${2:-}"; shift 2 ;;
        --out)          OUT="${2:-}";          shift 2 ;;
        --sources)      SOURCES="${2:-}";      shift 2 ;;
        --offline)      OFFLINE=1;             shift   ;;
        -h|--help)      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)              die "unknown argument: $1" ;;
    esac
done

[ -n "$VERSION_DATE" ] || VERSION_DATE=$(today_utc)
case "$VERSION_DATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "--version-date must be YYYY-MM-DD, got '$VERSION_DATE'" ;;
esac
epoch=$(epoch_of "$VERSION_DATE") || die "--version-date '$VERSION_DATE' is not a real date"

[ -n "$OUT" ] || OUT="$repo/build/cty"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

[ -n "$SOURCES" ] || SOURCES="$OUT/src"
mkdir -p "$SOURCES"
SOURCES=$(cd "$SOURCES" && pwd)

"$TAR" --version 2>/dev/null | grep -q 'GNU tar' \
    || die "GNU tar required (set TAR=gtar; macOS: brew install gnu-tar)"

stage="$OUT/stage"
verify="$OUT/verify"
rm -rf "$stage" "$verify"
mkdir -p "$stage" "$verify"

printf 'Building %s version %s\n' "$ARCHIVE_NAME" "$VERSION_DATE"

# --- 1. fetch ----------------------------------------------------------

fetch() { # url dest label
    _url=$1; _dest=$2; _label=$3
    if [ "$OFFLINE" = 1 ]; then
        [ -f "$_dest" ] || die "--offline but $_dest is missing"
        note "$_label: reusing $(bytes "$_dest") bytes from $_dest"
        return 0
    fi
    _info=$(curl --location --fail --silent --show-error \
                 --retry 5 --retry-delay 5 --retry-all-errors \
                 --connect-timeout 20 --max-time 600 \
                 --user-agent "$USER_AGENT" \
                 --output "$_dest" \
                 --write-out '%{http_code} %{content_type} %{size_download}' \
                 "$_url") \
        || die "$_label: transfer from $_url failed"
    _code=${_info%% *}; _rest=${_info#* }
    _ctype=${_rest%% *}; _size=${_rest##* }
    [ "$_code" = 200 ] || die "$_label: HTTP $_code from $_url"
    case "$_ctype" in
        text/html*) die "$_label: $_url served HTML ($_ctype)" ;;
    esac
    [ "$_size" -gt 0 ] || die "$_label: empty body from $_url"
    note "$_label: $_size bytes, $_ctype"
}

echo 'Fetching sources'
fetch "$LOTW_URL" "$SOURCES/lotw-user-activity.csv" lotw
fetch "$EQSL_URL" "$SOURCES/AGMemberList.txt"       eqsl
fetch "$SCP_URL"  "$SOURCES/MASTER.SCP"             scp

# --- 2. validate the raw sources ---------------------------------------

echo 'Validating sources'

check_common() { # file label minbytes minlines
    _f=$1; _l=$2; _mb=$3; _ml=$4
    ! looks_html "$_f" || die "$_l: body looks like an HTML page"
    _b=$(bytes "$_f"); _n=$(lines "$_f")
    [ "$_b" -ge "$_mb" ] || die "$_l: only $_b bytes, expected at least $_mb"
    [ "$_n" -ge "$_ml" ] || die "$_l: only $_n lines, expected at least $_ml"
    ends_nl "$_f" || die "$_l: does not end with a newline (truncated transfer?)"
    note "$_l: $_n lines, $_b bytes"
}

check_common "$SOURCES/lotw-user-activity.csv" lotw "$LOTW_MIN_BYTES" "$LOTW_MIN_LINES"
check_common "$SOURCES/AGMemberList.txt"       eqsl "$EQSL_MIN_BYTES" "$EQSL_MIN_LINES"
check_common "$SOURCES/MASTER.SCP"             scp  "$SCP_MIN_BYTES"  "$SCP_MIN_LINES"

# LoTW: shape of every row.  Interval quantifiers are spelled out because mawk
# and BWK awk disagree about {n}.
lotw_report=$(awk -F, '
    NR == 1 && tolower($1) ~ /^call/                     { header = 1 }
                                                         { rows++ }
    NF != 3                                              { bad++ }
    $1 == ""                                             { empty++ }
    $1 !~ /^[0-9A-Za-z\/]+$/                             { badcall++ }
    $2 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { baddate++ }
    $3 !~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/           { badtime++ }
    END { printf "%d %d %d %d %d %d %d\n",
                 rows, bad, empty, badcall, baddate, badtime, header }
' "$SOURCES/lotw-user-activity.csv")
set -- $lotw_report
lotw_rows=$1; lotw_bad=$2; lotw_empty=$3
lotw_badcall=$4; lotw_baddate=$5; lotw_badtime=$6; lotw_header=$7

[ "$lotw_header" = 0 ] \
    || die "lotw: row 1 looks like a header -- the CSV format changed, the transform would emit it as a callsign"
[ "$lotw_empty" = 0 ] || die "lotw: $lotw_empty rows have an empty callsign"
# 0.1% of rows may be malformed before it stops looking like noise.
lotw_tolerance=$((lotw_rows / 1000 + 1))
[ "$lotw_bad" -le "$lotw_tolerance" ] \
    || die "lotw: $lotw_bad of $lotw_rows rows do not have 3 fields"
[ "$lotw_bad" = 0 ]     || warn "lotw: $lotw_bad rows do not have 3 fields"
[ "$lotw_badcall" = 0 ] || warn "lotw: $lotw_badcall callsigns contain unexpected characters"
[ "$lotw_baddate" = 0 ] || warn "lotw: $lotw_baddate rows have a malformed date"
[ "$lotw_badtime" = 0 ] || warn "lotw: $lotw_badtime rows have a malformed time"

# eQSL: the header line is the best single proof this is really the member
# list, and it proves CRLF survived the transfer at the same time.
eqsl_header=$(head -1 "$SOURCES/AGMemberList.txt" | tr -d '\r')
case "$eqsl_header" in
    'List of AG members as of '*' UTC') ;;
    *) die "eqsl: unexpected header line: $eqsl_header" ;;
esac
eqsl_stamp=${eqsl_header#List of AG members as of }
[ "$(non_crlf "$SOURCES/AGMemberList.txt")" = 0 ] \
    || die "eqsl: some lines do not end with CR -- the file must stay CRLF throughout"
note "eqsl: header says $eqsl_stamp"

# SCP: first line is the order directive; the release line is informational.
scp_first=$(head -1 "$SOURCES/MASTER.SCP" | tr -d '\r')
[ "$scp_first" = '!!Order,1,1' ] \
    || die "scp: first line is '$scp_first', expected '!!Order,1,1'"
[ "$(non_crlf "$SOURCES/MASTER.SCP")" = 0 ] \
    || die "scp: some lines do not end with CR -- the file must stay CRLF throughout"
scp_release=$(head -6 "$SOURCES/MASTER.SCP" | tr -d '\r' | grep '^# Release ' | head -1 || true)
scp_release=${scp_release#\# }
if [ -n "$scp_release" ]; then
    note "scp: $scp_release"
else
    warn "scp: no '# Release' line in the first six lines"
fi

# --- 3. stage the fifteen members --------------------------------------

echo 'Staging members'

# lotw1.txt: field 1, CRLF.  awk rather than `cut | sed 's/$/\r/'` because sed
# dialects disagree about \r in a replacement; ORS also reproduces the trailing
# CRLF after the last record, which the upstream file has.
awk -F, 'BEGIN { ORS = "\r\n" } { print $1 }' \
    "$SOURCES/lotw-user-activity.csv" > "$stage/lotw1.txt"

# Verbatim, never filtered.
cp "$SOURCES/AGMemberList.txt" "$stage/eqsl.txt"
cp "$SOURCES/MASTER.SCP"       "$stage/MASTER.SCP"

for f in $DXCC_FILES;  do cp "$repo/data/dxcc/$f"  "$stage/$f"; done
for f in $EXTRA_FILES; do cp "$repo/data/extra/$f" "$stage/$f"; done

sed "s/@@VERSION_DATE@@/$VERSION_DATE/" "$repo/packaging/cty/README" > "$stage/README"
grep -q '@@' "$stage/README" && die 'README still contains an unsubstituted placeholder'

chmod 0644 "$stage"/*

# --- 4. validate what was staged ---------------------------------------

echo 'Validating staged set'

# The transform's own self-check: this is what catches a locale or awk mishap.
src_lines=$(lines "$SOURCES/lotw-user-activity.csv")
gen_lines=$(lines "$stage/lotw1.txt")
[ "$gen_lines" = "$src_lines" ] \
    || die "lotw1.txt has $gen_lines lines, source had $src_lines"
[ "$(non_crlf "$stage/lotw1.txt")" = 0 ] || die 'lotw1.txt: some lines are not CRLF'
[ "$(grep -c , "$stage/lotw1.txt" || true)" = 0 ] \
    || die 'lotw1.txt: a comma survived the field split'
ends_nl "$stage/lotw1.txt" || die 'lotw1.txt: no trailing newline'

# Byte-identity of the eleven redistributed files.  This is what would catch a
# checkout that ignored .gitattributes: CountryDel.tab, iota.tbl and
# ContestName.tab are CRLF and would change under core.autocrlf.
for f in $DXCC_FILES; do
    cmp -s "$repo/data/dxcc/$f" "$stage/$f" || die "$f differs from data/dxcc/$f"
done
for f in $EXTRA_FILES; do
    cmp -s "$repo/data/extra/$f" "$stage/$f" || die "$f differs from data/extra/$f"
done

[ ! -e "$stage/qslmgr.csv" ] || die 'qslmgr.csv does not belong in the archive'

staged=$(find "$stage" -maxdepth 1 -type f | wc -l | tr -d ' ')
[ "$staged" = "$MEMBER_COUNT" ] \
    || die "staged $staged files, expected $MEMBER_COUNT"
note "$staged members staged"

# --- 5. build the archive ----------------------------------------------

echo 'Building archive'

# `find -type f` gives the ./ prefix upstream uses without adding a ./
# directory member.  --sort=name is a no-op with -T (it only orders directory
# recursion), so the list is pre-sorted here.
( cd "$stage" && find . -maxdepth 1 -type f -print | sort ) > "$OUT/filelist"

rm -f "$OUT/cqrlog-cty.tar" "$OUT/$ARCHIVE_NAME"
"$TAR" --format=gnu --no-recursion \
       --owner=0 --group=0 --numeric-owner \
       --mode='u=rw,go=r' --mtime="@$epoch" \
       -C "$stage" -cf "$OUT/cqrlog-cty.tar" -T "$OUT/filelist"

# -n drops the name and timestamp from the gzip header; no -9, because the
# upstream archive's XFL byte is 00 and -9 would make it 02.
"$GZIP_BIN" -n "$OUT/cqrlog-cty.tar"
[ -f "$OUT/$ARCHIVE_NAME" ] || die "gzip did not produce $ARCHIVE_NAME"

printf '%s' "$VERSION_DATE" > "$OUT/ver.dat"

# --- 6. round-trip the archive before anyone publishes it --------------

echo 'Verifying archive'

"$TAR" xzf "$OUT/$ARCHIVE_NAME" -C "$verify"
for f in $(cd "$stage" && ls -1); do
    cmp -s "$stage/$f" "$verify/$f" || die "round-trip mismatch: $f"
done
members=$("$TAR" tzf "$OUT/$ARCHIVE_NAME" | wc -l | tr -d ' ')
[ "$members" = "$MEMBER_COUNT" ] || die "archive holds $members members, expected $MEMBER_COUNT"
"$TAR" tzf "$OUT/$ARCHIVE_NAME" | grep -qv '^\./[A-Za-z]' \
    && die 'archive contains a member with an unexpected path' || true
note "$members members, $(bytes "$OUT/$ARCHIVE_NAME") bytes"

# --- 7. manifest and release notes -------------------------------------

lotw_n=$(lines "$stage/lotw1.txt");   lotw_b=$(bytes "$stage/lotw1.txt")
eqsl_n=$(lines "$stage/eqsl.txt");    eqsl_b=$(bytes "$stage/eqsl.txt")
scp_n=$(lines "$stage/MASTER.SCP");   scp_b=$(bytes "$stage/MASTER.SCP")
archive_sha=$(sha256 "$OUT/$ARCHIVE_NAME")
commit=${GITHUB_SHA:-$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)}

cat > "$OUT/manifest.txt" <<MANIFEST
version_date=$VERSION_DATE
members=$members
archive_bytes=$(bytes "$OUT/$ARCHIVE_NAME")
archive_sha256=$archive_sha
commit=$commit
eqsl_header_date=$eqsl_stamp
scp_release=${scp_release:-unknown}
lotw_lines=$lotw_n
eqsl_lines=$eqsl_n
scp_lines=$scp_n
warnings=$warnings
MANIFEST

cat > "$OUT/notes.md" <<NOTES
Drop-in replacement for the CQRLOG country file set, version \`$VERSION_DATE\`.

Unpack into \`~/.config/cqrlog/ctyfiles/\`, replacing **all** files at once, then
run "Rebuild DXCC statistics" from the QSO list.

The country tables are the work of **Martin, OK1RR** (martin@ok1rr.com),
redistributed with credit as CQRLOG has always redistributed them. Eleven of the
fifteen files are his, byte for byte.

### Refreshed at build time

| File | Source | Lines | Bytes | SHA-256 |
|---|---|--:|--:|---|
| \`lotw1.txt\` | [lotw-user-activity.csv]($LOTW_URL) (field 1, CRLF) | $lotw_n | $lotw_b | \`$(sha256 "$stage/lotw1.txt")\` |
| \`eqsl.txt\` | [AGMemberList.txt]($EQSL_URL) (verbatim, $eqsl_stamp) | $eqsl_n | $eqsl_b | \`$(sha256 "$stage/eqsl.txt")\` |
| \`MASTER.SCP\` | [MASTER.SCP]($SCP_URL) (verbatim, ${scp_release:-unknown release}) | $scp_n | $scp_b | \`$(sha256 "$stage/MASTER.SCP")\` |

### Two differences from OK1RR's own archive

- **\`MASTER.SCP\` is the SuperCheckPartial database** (~50 000 calls), not the
  hand-curated FOC/CWops/HSC "active on CW" list (~5 700 calls) that his archives
  carry. The two overlap by roughly 2 900 calls. If you relied on the CW list,
  keep your existing copy.
- **\`ContestName.tab\` is included**, which upstream does not ship inside the
  tarball.

All members unpack with mode 0644 and carry \`$VERSION_DATE\` as their timestamp.
\`qslmgr.csv\` is not included, matching upstream.

SHA-256 of \`$ARCHIVE_NAME\`: \`$archive_sha\`
Built from commit \`$commit\`.
NOTES

echo
printf 'Done: %s/%s\n' "$OUT" "$ARCHIVE_NAME"
printf '      %s/ver.dat  (%s)\n' "$OUT" "$VERSION_DATE"
[ "$warnings" = 0 ] || printf '      %s warning(s) -- see above\n' "$warnings"
