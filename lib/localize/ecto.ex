defmodule Localize.Ecto do
  @moduledoc """
  Locale-aware query expressions for Ecto on PostgreSQL.

  The primary public API is the `collate/1` and `collate/2` macros,
  which wrap a query expression in a PostgreSQL `COLLATE` clause using
  the ICU collation that best matches a locale. The collation name is
  resolved by `Localize.Ecto.Collation.collation_for!/2` and emitted as
  a quoted identifier via Ecto's `literal/1` fragment, so it is never
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

  """

  @doc """
  Wraps a query expression in a `COLLATE` clause for the current locale.

  The collation is resolved from `Localize.get_locale/0` at the time the
  query is built.

  ### Arguments

  * `expression` is any Ecto query expression that evaluates to a
    string value, such as a schema field.

  ### Returns

  * A query fragment `expression COLLATE "collation-name"`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", order_by: collate(p.name), select: p.name
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro collate(expression) do
    quote do
      fragment(
        "? COLLATE ?",
        unquote(expression),
        literal(^Localize.Ecto.Collation.collation_for!())
      )
    end
  end

  @doc """
  Wraps a query expression in a `COLLATE` clause for the given locale.

  ### Arguments

  * `expression` is any Ecto query expression that evaluates to a
    string value, such as a schema field.

  * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale identifier
    accepted by `Localize.validate_locale/1`. A pinned expression
    (`^locale`) is also accepted, so runtime locale values read
    naturally in query syntax.

  ### Returns

  * A query fragment `expression COLLATE "collation-name"`.

  ### Examples

      iex> import Ecto.Query
      iex> query = from p in "products", order_by: collate(p.name, "sv"), select: p.name
      iex> match?(%Ecto.Query{}, query)
      true

  """
  defmacro collate(expression, locale) do
    locale = unpin(locale)

    quote do
      fragment(
        "? COLLATE ?",
        unquote(expression),
        literal(^Localize.Ecto.Collation.collation_for!(unquote(locale)))
      )
    end
  end

  # The locale argument is evaluated as an ordinary expression, not as a
  # query expression, so a pin is not required. Accept one anyway since
  # pinning runtime values is idiomatic inside Ecto queries.
  defp unpin({:^, _meta, [expression]}), do: expression
  defp unpin(expression), do: expression
end
