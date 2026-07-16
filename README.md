# Localize Ecto

Locale-aware PostgreSQL collation for [Ecto](https://hexdocs.pm/ecto) queries. `localize_ecto` resolves a [Localize](https://hexdocs.pm/localize) language tag to the best matching PostgreSQL ICU collation and applies it with a `COLLATE` clause, so query results sort and compare according to the conventions of the user's locale.

```elixir
import Ecto.Query
import Localize.Ecto

# Order by the current locale (Localize.get_locale/0)
from p in Product, order_by: collate(p.name)

# Order by an explicit locale
from p in Product, order_by: collate(p.name, "sv")

# Collate a comparison
from p in Product, where: collate(p.name < "münchen", "de")

# Use a collation created in a migration, by name
from p in Product, order_by: collate(p.name, collation: "german_phonebook")
```

Locale resolution uses the [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching) algorithm, so any valid locale finds its best available collation — `"zh-TW"` resolves to `zh-Hant-x-icu`, `"de-DE"` to `de-x-icu`, and an unknown locale falls back gracefully. Locales that carry a BCP 47 collation type, such as `de-u-co-phonebk` (German phonebook order), resolve to collations you create once in a migration with [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#create_collation/2).

## Installation

Add `localize_ecto` to your dependencies:

```elixir
def deps do
  [
    {:localize_ecto, "~> 0.1.0"}
  ]
end
```

## PostgreSQL only

This library supports PostgreSQL only. It emits `COLLATE` clauses referencing the ICU collations that PostgreSQL imports at `initdb` time, and its migration helpers run PostgreSQL's `CREATE COLLATION` with the ICU provider. Other databases either lack ICU collations, name them differently, or do not support `COLLATE` expressions in the same form.

## Deterministic collations and Unicode normalization

The collations this library resolves to are deterministic, which is PostgreSQL's default. A deterministic collation never treats two strings as equal unless they are byte-for-byte identical: comparison first uses the linguistic collation order, then breaks ties bytewise. This has a practical consequence for Unicode text that is not normalized. Canonically equivalent strings in different normalization forms — for example `é` as the single code point U+00E9 versus `e` followed by combining U+0301 — will sort adjacently but will never compare equal, so equality tests, `DISTINCT`, `GROUP BY`, joins on text keys, and unique indexes all see them as different values.

To get expected results, normalize text (NFC is the usual choice) before writing it to the database. In Elixir use [String.normalize/2](https://hexdocs.pm/elixir/String.html#normalize/2); in PostgreSQL the [normalize](https://www.postgresql.org/docs/current/functions-string.html) function and `IS NFC NORMALIZED` predicate are available for checking or repairing existing data. Alternatively, PostgreSQL supports nondeterministic collations that do compare canonically equivalent strings as equal — [Localize.Ecto.Migration.create_collation/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#create_collation/2) can create one with `deterministic: false` — but they cannot be used with `LIKE` or pattern matching and are slower.

## Available collations vary between PostgreSQL releases

PostgreSQL imports its ICU collations from the ICU library it was built against, so the available set differs between PostgreSQL releases and between builds linked to different ICU versions. This library bundles a snapshot of the collation locales from PostgreSQL 17 (ICU 76) and resolves against it. Because resolution uses CLDR language matching rather than exact name lookup, small differences between the snapshot and your server are usually harmless — a locale matches the closest collation that exists in the snapshot, and base-language collations such as `de-x-icu` or `zh-x-icu` are present in every release.

To see exactly which ICU collations your server provides:

```sql
SELECT collname, colllocale
FROM pg_collation
WHERE collprovider = 'i'
ORDER BY collname;
```

If your server's set differs materially from the snapshot, pass your own list with the `:available` option of [Localize.Ecto.Collation.collation_for/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Collation.html#collation_for/2).

## Performance considerations

Linguistic comparison is more expensive than PostgreSQL's default byte-order comparison, and an `ORDER BY ... COLLATE` clause can only use an index that was created with the same collation. For hot queries, create an index with the collation you sort by using [Localize.Ecto.Migration.collated/2](https://hexdocs.pm/localize_ecto/Localize.Ecto.Migration.html#collated/2):

```elixir
create index("products", [collated(:name, "de")])
```

If a PostgreSQL upgrade links a newer ICU library whose collation data changed — uncommon, but it happens — PostgreSQL warns of a collation version mismatch and indexes built with that collation must be reindexed. Nondeterministic collations carry an additional performance penalty. See the [PostgreSQL collation documentation](https://www.postgresql.org/docs/current/collation.html) for the details of collation selection, index compatibility, and the trade-offs between providers.

## Guides

* [Using Localize Ecto](https://hexdocs.pm/localize_ecto/using_localize_ecto.html) — the `collate/1,2` macros, locale resolution, and migrations.

* [Collations in PostgreSQL](https://hexdocs.pm/localize_ecto/collations_in_postgres.html) — how PostgreSQL collation works, choosing a database default, and how ICU collations relate to Localize.

## License

Copyright 2026 Kip Cole

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/elixir-localize/localize_ecto/blob/v0.1.0/LICENSE.md).
