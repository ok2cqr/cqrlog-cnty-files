# Algorithm

How the files in `data/dxcc/` become a table, and how a callsign becomes a DXCC
entity. This is the contract every implementation must satisfy.

Read [FORMAT.md](FORMAT.md) first for the shape of the files themselves.

A warning that applies to the whole document: several rules below look like
bugs, and some of them are. They are specified anyway, because CQRLOG has
resolved callsigns this way for twenty years and hundreds of thousands of
logged QSOs carry the answers. Changing one changes history, so each is
reproduced deliberately and pinned by a test. Where a rule is genuinely wrong,
it says so and says what the consequence is.

## 1. Assembling the tables

The parser does not read the six files individually. It works with two tables,
assembled like this:

**The valid table** is the concatenation of, in this order:

1. `Country.tab`
2. `CallResolution.tbl`
3. `AreaOK1RR.tbl`

**The order is load-bearing.** The index sort is stable and lookup keeps the
first of two equally good candidates, so when two marks produce the same sort
key, whichever file contributed its mark first wins. Concatenate them in any
other order and some callsigns resolve differently.

**The deleted table** is `CountryDel.tab` alone.

Then, optionally, the `%` expansion:

> Every line whose **first character** is `%` is appended to the table again,
> 26 more times, with that leading `%` replaced by `A`, `B`, … `Z`. Only the
> leading `%` is replaced; the rest of the mark is copied verbatim, so
> `%%%%/B[A-LRSTYZ]0[A-F]%` yields `A%%%/B[A-LRSTYZ]0[A-F]%` and so on.
>
> The generated lines all go **after** the originals, and are **not themselves
> re-expanded**.

### Why the expansion is optional, and which variant is the reference

CQRLOG builds its country table in two different places and they disagree:

| Builder | When | Expansion |
|---|---|---|
| `dData.pas:1057` `PrepareDXCCData` | first run | no |
| `fImportProgress.pas:344-351` | manual "Import DXCC data" | yes |

Both variants exist in the field, so both are specified. **The expanded form is
the reference** — it is what a user has after updating their country files, and
it resolves callsigns the plain form cannot reach at all.

The reason the difference matters: a `%`-leading mark sorts above every
alphanumeric (see §2), so a lookup keyed on the callsign's first character can
never reach it. In the plain table those 204 guest-operator patterns are dead
weight; expanded, they resolve. `OK1A/BA0AX` is the standard example — the two
variants give different countries for it.

### Line endings and trailing newlines

Strip every byte below 32 while reading. Ensure each file's content ends with a
newline before concatenating, or the last line of one file will be glued to the
first line of the next.

`tools/build-tables.sh` writes these merged files out if you want to compare
against them; nothing in the repository needs it to have run.

## 2. Collation

The index is sorted by a custom collation, not by ASCII. The exact 256-byte
mapping must be reproduced exactly; it is written out as literals in
`parsers/pascal/tests/tCollation.pas`, which is the authoritative copy.

Two properties carry the weight:

**The five metacharacters `[`, `]`, `%`, `#`, `?` occupy five consecutive ranks,
above every alphanumeric.** Lookup finds patterns whose second character is a
metacharacter by scanning the single contiguous range
`firstchar + '[' .. firstchar + '?'`. That scan is only correct because those
five ranks are adjacent. Reorder them and wildcard patterns silently stop being
found.

**Bytes 254 and 255 share rank 254.** The table that builds the collation scans
with `x < 254` where `x <= 255` was meant. It is a real off-by-one, and it is
part of the specification because the sort order depends on it.

The sort key of a string is the per-byte rank, **after stripping one leading
`=`**. That is what puts `=OK1ABC` and `OK1ABC` in the same neighbourhood, where
they compete.

## 3. Matching a mark against a callsign

Three modes:

| Mode | Meaning |
|---|---|
| `prefix` | the mark must match the start of the callsign; trailing characters are free |
| `exact` | the mark must consume the whole callsign |
| `exactnoequals` | as `exact`, but entries stored with a leading `=` are ignored |

Character classes (`[A-F]`, `[ABC]`, mixed) are matched by scanning the class
body; ranges and singletons may be combined.

## 4. Choosing the winner

When several marks match, the winner is decided in this order:

1. **Longest pattern wins**, where length is counted in *pattern positions* — a
   whole `[…]` class counts as **one**, not as its width.
2. On a tie, the **more specific** pattern wins: literal beats `#` beats `?`
   beats `%`, compared position by position.
3. Still tied: the **first in the table** wins, which is why the sort must be
   stable and the concatenation order matters.

### The specificity walk is off by one at both ends

The comparison in rule 2 starts at index **0** and stops at **Length − 1**. In
the original this was a shortstring, where index 0 is the length byte, not a
character — so the walk compares the *length* as if it were a character, and
never examines the final character at all. A 35-character pattern compares as if
its first character were `#`, a 37-character one as if it were `%`.

This is faithfully reproduced. It changes which of two same-length patterns
wins, and therefore which country some callsigns get.

### Known consequence: rule 1 can defeat finer entries

Because rule 1 counts positions and prefix mode leaves trailing characters free,
a short pattern with a wildcard can outrank a longer literal one. Czech
callsigns between 1993-01-01 and 2005-04-30 are the documented case:

| mark | positions | matches `OK1AYY`? |
|---|---|---|
| `OK1` | 3 | yes |
| `OK[1-7]%` | **4** | yes — consumes `OK1A`, ignores `YY` |

`OK[1-7]%` wins on length, so the call areas `OK1` and `OK2` are unreachable in
that window and the country string reads "Czech Rep., Special & Contest
Station". The ADIF is unaffected. This is a **data** problem, not a parser one —
see [`../docs/proposals/`](../docs/proposals/).

## 5. Date validity

An entry is valid on a date when `ValidFrom <= date <= ValidTo`, compared as
**strings**. Dates are `YYYY/MM/DD`, which makes lexicographic comparison
correct, and no implementation needs date arithmetic.

Defaults are `1945/01/01` and `2050/01/01`. `*` is always valid, `!` never.

Invalid entries are skipped during the scan; they do not win and then get
rejected.

## 6. Resolving a callsign

Full resolution has two stages, because a callsign is not a table key.

### Stage 1 — reduce the callsign to a lookup key

Given `OK1ABC/P`, the table should be probed with `OK1ABC`. Given `KL7AA/1`,
with `W1`. This stage handles that. Roughly, in order:

1. Try the **whole string** as an exact match first. This is how explicitly
   listed portable forms like `=LU2ERA/Z` are answered without any splitting.
2. No slash: the callsign is the key.
3. Split on the slash. Decide which side is the *location* and which is the
   *operator* by probing both against the table.
4. A suffix in `Exceptions.tab`, or `P`, `QRP`, `QRPP`, or any suffix longer
   than three characters with no digit in it, carries no location — drop it and
   keep the operator's callsign.
5. `MM` (maritime mobile) and `AM` (aeronautical mobile) mean **no country**.
   The key becomes `?`.
6. A single-digit suffix renumbers the call area: `SP2AD/1` → `SP1AD`.
7. US calls move to the `W` district: `KL7AA/1` → `W1`.

Every one of these steps that probes the table passes the date, so this stage is
date-sensitive throughout.

### Stage 2 — look the key up

Probe the **deleted table first**, then the valid one, both in prefix mode.
Deleted-first is what makes `OK1AYY` on 1992-12-12 resolve to Czechoslovakia
(ADIF 218) rather than to a modern Czech entity.

## 7. Argentina — the one deliberate departure

Argentine provinces are encoded in the **fourth character** of the callsign, not
in a prefix: `LU1AAA` is Buenos Aires, `LU1FAA` is Santa Fe, `LU1HAA` is
Córdoba. A single trailing letter means the operator is working from a different
province, and it is applied by **overwriting character 4**:

```
LU1AAA/Z  ->  LU1ZAA
```

This matters beyond cosmetics: `LU#Z` is **Antarctica**, a different DXCC
entity.

The original restricted this rewrite to the suffix letters
`A–D, E, H, J, L–V, X–Z` — omitting **F, G, I, K and W**, because each is a
major DXCC prefix. But those letters are also Argentine provinces. Of the
omitted five:

- `/W` and `/X` are rescued by explicit slash patterns in `AreaOK1RR.tbl`
  (`L[O-W][1-9]%%%/W` → Chubut, `/X[A-O]` → Santa Cruz, `/X[P-Z]` → Tierra del
  Fuego). The whole-string exact match in stage 1 answers them before any
  rewriting happens. **Implementations must leave these alone.**
- **F, G, I and K got no such entry**, so they lost their province.

Additionally, the `/M` and `/P` shortcut tested only for the literal prefix
`LU`, so the ten companion prefixes (`LW`, `AY`, `AZ`, `LO`, `LP`, `LQ`, `LR`,
`LS`, `LT`, `LV`) lost Mendoza and San Juan.

**This repository fixes both.** It is the only intentional behavioural
difference from the original engine.

### What the fix does not do

It does not move any DXCC entity. It is tempting to read the original as
resolving `LU1AAA/F` to *France* — it did not. The generic branch sets the key
to the bare suffix, but the next step probes `prefix[1..2] + '/' + suffix`
(`LU/F`) in prefix mode, and `LU` is itself a mark, so the probe hits and the old
answer was plain **Argentina**. The same mechanism makes `DL1ABC/F` resolve as
Germany.

Since every Argentine province shares ADIF 100, the fix sharpens the *province
string* and never changes the entity. Verified against a 58 184-QSO log: zero
ADIF differences. See [`../docs/EQUIVALENCE.md`](../docs/EQUIVALENCE.md).

## 8. Limits, and what must not be a limit

| Limit | Value | Status |
|---|---|---|
| mark length | 40 characters | **enforced** — truncate; live in the current data |
| description length | 250 characters | **enforced** — truncate |
| number of entries | none | the original's ceilings must not be reproduced |
| number of descriptions | none | " |

The original capped descriptions at 10 000. The current files need **9 056** —
90.6% of the ceiling. Overflowing it there is not a loud failure: it sets an
internal flag after which *every* lookup returns "no country", silently. Do not
reproduce this. Grow.

Equally, do not reproduce the original's out-of-bounds read on small tables: a
lookup whose probe key sorts above everything in the table must return "no
match", not crash.
