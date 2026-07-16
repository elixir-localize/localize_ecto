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

  # The locale argument is evaluated as an ordinary expression, not as a
  # query expression, so a pin is not required. Accept one anyway since
  # pinning runtime values is idiomatic inside Ecto queries.
  defp unpin({:^, _meta, [expression]}), do: expression
  defp unpin(expression), do: expression
end
