defmodule Localize.Ecto do
  @moduledoc """
  Locale-aware query expressions for Ecto on PostgreSQL.

  The primary public API is the `collate/1` and `collate/2` macros,
  which apply a PostgreSQL `COLLATE` clause to a query expression — or
  to a comparison between two expressions — using the ICU collation
  that best matches a locale. The collation name is resolved by
  `Localize.Ecto.Collation.resolve!/1` and emitted as a quoted
  identifier via Ecto's `literal/1` fragment, so it is never
  interpolated into the SQL as text.

  Import this module (or `import Localize.Ecto, only: [collate: 1, collate: 2]`)
  alongside `Ecto.Query` and use `collate/1,2` anywhere a query
  expression is accepted — `order_by`, `select`, `where`, `distinct`
  and so on:

      import Ecto.Query
      import Localize.Ecto

      # Collate using the current locale (Localize.get_locale/0)
      from p in Product, order_by: collate(p.name)

      # Collate using an explicit locale
      from p in Product, order_by: collate(p.name, "sv")

      # Locale determined at runtime
      def sorted_products(locale) do
        from p in Product, order_by: collate(p.name, ^locale)
      end

      # Collate a comparison: name < 'münchen' under German collation
      from p in Product, where: collate(p.name < "münchen", "de"), select: p.name

      # Use a collation created in a migration, by name
      from p in Product, order_by: collate(p.name, collation: "german_phonebook")

  Collations for locales carrying a BCP 47 collation type, such as
  `de-u-co-phonebk`, are not preloaded by PostgreSQL. Create them once
  in a migration with `Localize.Ecto.Migration.create_collation/2` and
  they resolve automatically thereafter.

  """

  @comparison_operators [:<, :>, :<=, :>=, :==, :!=]

  @doc """
  Applies a `COLLATE` clause for the current locale.

  The collation is resolved from `Localize.get_locale/0` at the time
  the query is built.

  ### Arguments

  * `expression` is any Ecto query expression that evaluates to a
    string value, or a comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`)
    between two such expressions.

  ### Returns

  * A query fragment `expression COLLATE "collation"`, or for a
    comparison `left OP right COLLATE "collation"`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", order_by: collate(p.name), select: p.name
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro collate(expression) do
    build_collate(expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Applies a `COLLATE` clause for the given locale or collation.

  ### Arguments

  * `expression` is any Ecto query expression that evaluates to a
    string value, or a comparison (`<`, `<=`, `>`, `>=`, `==`, `!=`)
    between two such expressions.

  * `locale_or_options` is a `t:Localize.LanguageTag.t/0`, any locale
    identifier accepted by `Localize.validate_locale/1`, or a keyword
    list of options. A pinned expression (`^locale`) is also accepted,
    so runtime locale values read naturally in query syntax.

  ### Options

  * `:collation` is a collation name used verbatim, bypassing locale
    resolution — for example a collation created with
    `Localize.Ecto.Migration.create_collation/2` under a custom name.

  * Any other options are passed to
    `Localize.Ecto.Collation.collation_for!/2`.

  ### Returns

  * A query fragment `expression COLLATE "collation"`, or for a
    comparison `left OP right COLLATE "collation"`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", order_by: collate(p.name, "sv"), select: p.name
      iex> match?(%Ecto.Query{}, query)
      true

      iex> import Ecto.Query
      iex> query = from p in "products", select: collate(p.name < p.description, "de")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro collate(expression, locale_or_options) do
    locale_or_options = unpin(locale_or_options)

    build_collate(
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  # A comparison collates its right-hand operand; PostgreSQL applies
  # the collation to the comparison since COLLATE binds tighter than
  # any operator.
  defp build_collate({operator, _meta, [left, right]}, resolver)
       when operator in @comparison_operators do
    sql = "? #{sql_operator(operator)} ? COLLATE ?"

    quote do
      fragment(unquote(sql), unquote(left), unquote(right), literal(^unquote(resolver)))
    end
  end

  defp build_collate(expression, resolver) do
    quote do
      fragment("? COLLATE ?", unquote(expression), literal(^unquote(resolver)))
    end
  end

  defp sql_operator(:==), do: "="
  defp sql_operator(:!=), do: "<>"
  defp sql_operator(operator), do: Atom.to_string(operator)

  @doc """
  Applies PostgreSQL's `AT TIME ZONE` with a validated time zone.

  The zone is canonicalized by `Localize.Ecto.Type.TimeZone.canonicalize!/1` when the query is built, so an alias or BCP 47 short zone identifier is accepted and an unknown zone raises in the application instead of failing on the server.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a timestamp.

  * `zone` is a canonical IANA name, a CLDR-known alias, or a BCP 47 short zone identifier. A pinned expression (`^zone`) is also accepted.

  ### Returns

  * A query fragment `expression AT TIME ZONE 'zone'`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from e in "events", select: at_time_zone(e.starts_at, "Australia/Sydney")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro at_time_zone(expression, zone) do
    zone = unpin(zone)

    quote do
      fragment(
        "? AT TIME ZONE ?",
        unquote(expression),
        ^Localize.Ecto.Type.TimeZone.canonicalize!(unquote(zone))
      )
    end
  end

  @doc """
  Locale-aware full-text search match using the current locale.

  See `ts_match/3`.
  """
  defmacro ts_match(expression, query) do
    build_ts_match(expression, query, quote(do: Localize.Ecto.TextSearch.config_for!()))
  end

  @doc """
  Locale-aware full-text search match.

  Expands to `to_tsvector(config, expression) @@ websearch_to_tsquery(config, query)` where `config` is the PostgreSQL text search configuration `Localize.Ecto.TextSearch.config_for!/2` resolves for the locale — `'german'` for `"de-AT"`, `'simple'` for languages PostgreSQL has no stemmer for.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to the searched text.

  * `query` is the user's search input, in `websearch_to_tsquery` syntax.

  * `locale_or_options` is a locale accepted by `Localize.Ecto.TextSearch.config_for!/2`, or a keyword list with a `:config` option naming a text search configuration directly. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A boolean query fragment for use in `where`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", where: ts_match(p.description, "wooden chair", "de"), select: p.id
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro ts_match(expression, query, locale_or_options) do
    locale_or_options = unpin(locale_or_options)

    resolver =
      quote do
        case unquote(locale_or_options) do
          options when is_list(options) ->
            case Keyword.pop(options, :config) do
              {nil, options} ->
                Localize.Ecto.TextSearch.config_for!(Localize.get_locale(), options)

              {config, _options} ->
                config
            end

          locale ->
            Localize.Ecto.TextSearch.config_for!(locale)
        end
      end

    build_ts_match(expression, query, resolver)
  end

  # The configuration is bound as a text parameter and cast to
  # regconfig on the server — postgrex encodes a bare `?::regconfig`
  # parameter as an oid, not a name.
  defp build_ts_match(expression, query, resolver) do
    quote do
      fragment(
        "to_tsvector(?::text::regconfig, ?) @@ websearch_to_tsquery(?::text::regconfig, ?)",
        ^unquote(resolver),
        unquote(expression),
        ^unquote(resolver),
        unquote(query)
      )
    end
  end

  @doc """
  Locale-aware `lower()` using the collation of the current locale.

  See `lower/2`.
  """
  defmacro lower(expression) do
    build_case(:lower, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `lower()`.

  PostgreSQL's `lower()`, `upper()` and `initcap()` follow the collation of their argument, so the locale determines the case mapping — under a Turkish collation `lower("I")` is the dotless "ı", which the default collation gets wrong.

  ### Arguments

  * `expression` is an Ecto query expression that evaluates to a string.

  * `locale_or_options` is a locale or keyword list as accepted by `collate/2`. A pinned expression (`^locale`) is also accepted.

  ### Returns

  * A query fragment `lower(expression COLLATE "collation")`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", select: lower(p.name, "tr")
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro lower(expression, locale_or_options) do
    locale_or_options = unpin(locale_or_options)

    build_case(
      :lower,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware `upper()` using the collation of the current locale.

  See `lower/2`.
  """
  defmacro upper(expression) do
    build_case(:upper, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `upper()`. See `lower/2` for the arguments and semantics.
  """
  defmacro upper(expression, locale_or_options) do
    locale_or_options = unpin(locale_or_options)

    build_case(
      :upper,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  @doc """
  Locale-aware `initcap()` using the collation of the current locale.

  See `lower/2`.
  """
  defmacro initcap(expression) do
    build_case(:initcap, expression, quote(do: Localize.Ecto.Collation.resolve!()))
  end

  @doc """
  Locale-aware `initcap()`. See `lower/2` for the arguments and semantics.
  """
  defmacro initcap(expression, locale_or_options) do
    locale_or_options = unpin(locale_or_options)

    build_case(
      :initcap,
      expression,
      quote(do: Localize.Ecto.Collation.resolve!(unquote(locale_or_options)))
    )
  end

  defp build_case(function, expression, resolver) do
    sql = "#{function}(? COLLATE ?)"

    quote do
      fragment(unquote(sql), unquote(expression), literal(^unquote(resolver)))
    end
  end

  # The locale argument is evaluated as an ordinary expression, not as a
  # query expression, so a pin is not required. Accept one anyway since
  # pinning runtime values is idiomatic inside Ecto queries.
  defp unpin({:^, _meta, [expression]}), do: expression
  defp unpin(expression), do: expression
end
