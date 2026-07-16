# Using Localize Ecto

This guide covers the day-to-day API: the `collate/1,2` query macros, how locales resolve to PostgreSQL collations, and how to create collations that PostgreSQL does not provide out of the box. For background on PostgreSQL collation itself, see [Collations in PostgreSQL](https://hexdocs.pm/localize_ecto/collations_in_postgres.html).

## Setup

Import `Localize.Ecto` wherever you build queries, alongside `Ecto.Query`:

```elixir
import Ecto.Query
import Localize.Ecto
```

## Collating a query expression

`collate/2` wraps any string-valued query expression in a `COLLATE` clause for a locale. It can appear anywhere Ecto accepts a query expression — `order_by`, `select`, `where`, `distinct`, `group_by`:

```elixir
from p in Product, order_by: collate(p.name, "sv"), select: p.name
```

The generated SQL orders by `p0."name" COLLATE "sv-x-icu"`. The collation name is emitted through Ecto's `literal/1` fragment, so it is always a quoted identifier and never interpolated text.

`collate/1` does the same using the current locale, read from `Localize.get_locale/0` at the time the query is built:

```elixir
Localize.put_locale("da")
from p in Product, order_by: collate(p.name)
```

The locale argument accepts anything `Localize.validate_locale/1` accepts — a string, an atom, or a `Localize.LanguageTag` — and runtime values may be pinned, which reads naturally in query syntax:

```elixir
def sorted_products(locale) do
  from p in Product, order_by: collate(p.name, ^locale)
end
```

An invalid locale raises when the query is built, not when it runs.

## Collating a comparison

Passing a comparison to `collate/1,2` collates the comparison itself, which is how PostgreSQL expresses "compare these two values under this collation":

```elixir
from p in Product, where: collate(p.name < "münchen", "de"), select: p.name
```

This emits `p0."name" < 'münchen' COLLATE "de-x-icu"` — `COLLATE` binds tighter than any operator, so it governs the comparison. All six comparison operators are supported: `<`, `<=`, `>`, `>=`, `==` (emitted as `=`) and `!=` (emitted as `<>`).

## How locales resolve to collations

Resolution is implemented by `Localize.Ecto.Collation.collation_for/2` and follows the [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching) algorithm via `Localize.LanguageTag.best_match/3`. The requested locale is matched against the set of ICU collation locales PostgreSQL provides, and the closest match wins:

```elixir
iex> Localize.Ecto.Collation.collation_for!("en-GB")
"en-GB-x-icu"

iex> Localize.Ecto.Collation.collation_for!("de-DE")
"de-x-icu"

iex> Localize.Ecto.Collation.collation_for!("zh-TW")
"zh-Hant-x-icu"

iex> Localize.Ecto.Collation.collation_for!("und")
"und-x-icu"
```

Two things are worth noting about these results. First, a match to a broader locale — `de-DE` matching `de`, or `zh-TW` matching `zh-Hant` — selects an identical collator, because CLDR collation tailorings are defined per language and script, never per territory. Second, `und` (the undetermined locale) resolves to `und-x-icu`, the ICU root collation, which is also the fallback of last resort for locales with no meaningful match.

Resolutions are cached, so the cost of matching is paid once per distinct locale.

## Using a collation name directly

When you know exactly which collation you want — one you created in a migration, or a server collation outside the bundled snapshot — pass its name with the `:collation` option and resolution is bypassed entirely:

```elixir
from p in Product, order_by: collate(p.name, collation: "german_phonebook")
```

## Collation types and migrations

Locales can carry a BCP 47 collation type in their `-u-co-` extension: `de-u-co-phonebk` is German phonebook order, `zh-u-co-stroke` is Chinese stroke-count order. PostgreSQL does not preload collations for these, so they must be created once per database. That belongs in a migration:

```elixir
defmodule MyApp.Repo.Migrations.AddPhonebookCollation do
  use Ecto.Migration

  import Localize.Ecto.Migration

  def change do
    create_collation("de-u-co-phonebk")
  end
end
```

`create_collation/2` is reversible — rolling back drops the collation. The default name is exactly the name the resolver produces for the same locale, so after the migration runs, queries need no configuration:

```elixir
iex> Localize.Ecto.Collation.collation_for!("de-u-co-phonebk")
"de-u-co-phonebk-x-icu"
```

```elixir
from p in Product, order_by: collate(p.name, "de-u-co-phonebk")
```

The difference is real: standard German sorts `Mueller, Muller, Müller` while phonebook order treats `ü` as `ue` and sorts `Mueller, Müller, Muller`.

Custom names and other ICU tailorings are supported through options:

```elixir
create_collation("de-u-co-phonebk", name: "german_phonebook")

create_collation("und-u-ks-level2", name: "case_insensitive", deterministic: false)
```

The second example creates a nondeterministic, case-insensitive collation from ICU's `ks-level2` (strength: secondary) tailoring — useful for case-insensitive equality, with the caveats described in the [README](https://hexdocs.pm/localize_ecto/readme.html#deterministic-collations-and-unicode-normalization).

## Matching against a different server

The bundled snapshot of collation locales comes from PostgreSQL 17. If your server provides a different set, query it and pass the result with `:available`:

```elixir
locales =
  MyApp.Repo
  |> Ecto.Adapters.SQL.query!("SELECT colllocale FROM pg_collation WHERE collprovider = 'i'")
  |> Map.fetch!(:rows)
  |> List.flatten()

Localize.Ecto.Collation.collation_for!("de-AT", available: locales)
```

## Indexes

An `ORDER BY ... COLLATE` clause only uses an index created with the same collation. If a collated sort is on a hot path, add a matching expression index in a migration:

```elixir
execute(
  ~s[CREATE INDEX products_name_de ON products (name COLLATE "de-x-icu")],
  ~s[DROP INDEX products_name_de]
)
```
