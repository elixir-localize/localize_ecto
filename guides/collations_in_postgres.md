# Collations in PostgreSQL

Collation is the set of rules that determines how text sorts and compares. This guide explains how PostgreSQL handles collation, how its ICU collations relate to [Localize](https://hexdocs.pm/localize), and how to add collations PostgreSQL does not provide by default. The authoritative reference is the [PostgreSQL collation documentation](https://www.postgresql.org/docs/current/collation.html).

## The database default collation

Every PostgreSQL database has a default collation, fixed at `CREATE DATABASE` time, that applies to every text comparison and sort that does not name a collation explicitly. It also determines the behavior of case conversion (`upper`, `lower`, `ILIKE`) through its character-classification (ctype) side.

Our recommendation: make the database default the builtin `C.UTF-8` locale (PostgreSQL 17 and later), falling back to the `C` locale on older PostgreSQL releases, and apply linguistic collation explicitly in queries with `COLLATE` — which is exactly what this library does.

* `C.UTF-8` (provider `builtin`, PostgreSQL 17+) sorts in Unicode code-point order — fast and permanently stable — while its ctype is full Unicode, so case conversion (`upper`, `lower`, `ILIKE`) works for all scripts without naming a collation.

* `C` is the fallback for PostgreSQL 16 and earlier. Sorting is plain byte order, equally fast and stable, but its ctype is ASCII-only: `upper('öl')` returns `öL` with the `ö` untouched. Where you need case conversion on non-ASCII text, apply a collation to the expression — `upper('öl' COLLATE "de-x-icu")` returns `ÖL`.

The reason for this recommendation is stability. A database default is fixed at `CREATE DATABASE` time, every index on text is built in its sort order, and a sort order that changes underneath an existing index silently corrupts the index's correctness. Each external collation provider carries exactly that risk:

* Operating system releases. A libc default such as `en_US.UTF-8` sorts according to the OS locale data, which changes with OS upgrades — the classic cause of index corruption after a glibc update.

* ICU releases. An ICU default would tie the database's sort order to the ICU library version, which changes as CLDR data evolves; PostgreSQL records collation versions and warns of mismatches, but the remedy is still reindexing the affected database.

* PostgreSQL releases. Byte order and code-point order are defined by Unicode itself, not by any library's tailoring data, so a `C` or `C.UTF-8` default behaves identically across PostgreSQL upgrades and never demands a reindex.

Scoping linguistic collation to query expressions confines the versioned, changeable part of collation to the places that opt into it — and any index created with an explicit ICU collation (see `Localize.Ecto.Migration.collated/2`) is a known, listed object that can be reindexed deliberately when the ICU version moves.

Neither `C` nor `C.UTF-8` sorts linguistically — `Zebra` sorts before `apple` because `Z` has a smaller code point than `a`. That is the point of the division of labor: the default collation keeps storage and indexes fast and stable, and queries opt into linguistic ordering per expression:

```elixir
from p in Product, order_by: collate(p.name, "sv")
```

## Collation providers

PostgreSQL supports three collation providers:

* `libc` — the operating system's locale facilities. Availability and behavior vary by OS, and the sort order can change under you when the OS updates its locale data.

* `icu` — the [ICU library](https://icu.unicode.org), which implements the Unicode Collation Algorithm with the tailorings defined by [CLDR](https://cldr.unicode.org), the Unicode Common Locale Data Repository. ICU collations are consistent across operating systems and are versioned, so PostgreSQL can detect when a collation's underlying data has changed.

* `builtin` (PostgreSQL 17+) — PostgreSQL's own provider offering `C` and `C.UTF-8` semantics with no external dependency.

This library uses the ICU provider exclusively, and the relationship to Localize is direct: both draw on the same CLDR data. Localize implements CLDR locale identification, language matching, and (in `Localize.Collation`) the same UCA + CLDR collation rules in Elixir. That shared foundation means the ordering PostgreSQL produces for `COLLATE "sv-x-icu"` agrees with the ordering `Localize.Collation.sort/2` produces for locale `sv` in application code — the same names sort the same way in the database and in the BEAM.

## The default ICU collations and Localize language tags

When a PostgreSQL cluster is initialized, `initdb` imports a collation for every locale the linked ICU library provides, naming each after its BCP 47 locale identifier with an `-x-icu` suffix. The shapes you will find in `pg_collation`:

* A base collation per language: `de-x-icu`, `ja-x-icu`, `sv-x-icu`.

* Regional variants: `de-DE-x-icu`, `en-GB-x-icu`, `pt-BR-x-icu`. These exist for completeness but tailor nothing — CLDR collation rules are per language and script, so `de-DE-x-icu` and `de-x-icu` are the same collator.

* Script-qualified collations where a language is written in more than one script: `sr-Cyrl-x-icu` and `sr-Latn-x-icu`, `zh-Hans-x-icu` and `zh-Hant-x-icu`. For these languages there is no plain language-region name — Taiwan is `zh-Hant-TW-x-icu`, not `zh-TW-x-icu`.

* The root collation `und-x-icu`, the untailored Unicode default order.

Localize language tags map onto these names by [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching), not by string manipulation, which is what makes the mapping robust. A requested `zh-TW` matches `zh-Hant` (Traditional script is implied by the territory); `de-DE` matches `de`; an unmatchable locale falls back to `und`. The matching is against the canonical, unmaximalized locale identifier, so a requested `und` stays `und` rather than maximizing to `en`.

```elixir
iex> Localize.Ecto.Collation.collation_for!("zh-TW")
"zh-Hant-x-icu"

iex> Localize.Ecto.Collation.collation_for!("de-DE")
"de-x-icu"

iex> Localize.Ecto.Collation.collation_for!("sr")
"sr-x-icu"
```

The precise set of imported collations depends on the ICU version PostgreSQL was built against, and grows over time. Query your server with `SELECT collname, colllocale FROM pg_collation WHERE collprovider = 'i'` to see what you have.

## Defining collations with the migration functions

ICU can construct far more collators than PostgreSQL imports by default. Any BCP 47 locale with Unicode extension keywords is a valid collation definition, and `Localize.Ecto.Migration.create_collation/2` makes creating one a single, reversible migration step.

The most common case is a collation type — the `-u-co-` keyword — selecting an alternate ordering that CLDR defines for a language:

```elixir
def change do
  create_collation("de-u-co-phonebk")
end
```

This runs `CREATE COLLATION "de-u-co-phonebk-x-icu" (provider = icu, locale = 'de-u-co-phonebk')`. The name matches what `Localize.Ecto.Collation` resolves the locale to, so from then on `collate(p.name, "de-u-co-phonebk")` works with no further configuration. German phonebook order treats `ü` as `ue`: standard German sorts `Mueller, Muller, Müller` while phonebook order sorts `Mueller, Müller, Muller`. Other collation types include `zh-u-co-stroke` and `zh-u-co-zhuyin` for Chinese stroke and Bopomofo orderings, and `es-u-co-trad` for traditional Spanish, where `ch` sorts as a single letter.

Other ICU keywords open up collation behaviors beyond language tailoring:

* Numeric ordering (`-u-kn`) compares digit sequences by numeric value, giving natural sort: `file1, file2, file10` instead of `file1, file10, file2`.

  ```elixir
  create_collation("und-u-kn", name: "natural_sort")
  ```

* Strength reduction (`-u-ks-level2`) ignores case differences. Combined with `deterministic: false` this yields a collation under which `'HELLO' = 'hello'` is true — case-insensitive matching without `citext` or `lower()` wrappers, at the cost that `LIKE` and pattern matching cannot use the collation.

  ```elixir
  create_collation("und-u-ks-level2", name: "case_insensitive", deterministic: false)
  ```

Named collations like these are used in queries with the `:collation` option:

```elixir
from f in File, order_by: collate(f.name, collation: "natural_sort")
```

Two practical notes. PostgreSQL normalizes ICU locale identifiers when it stores them, so `und-u-kn-true` is recorded in standard form as `und-u-kn` — pass the standard form to avoid a notice. And because collations live in the database, remember that a collation created in a migration exists per database: test, dev, and production each get theirs when migrations run.
