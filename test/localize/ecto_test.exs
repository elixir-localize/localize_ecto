defmodule Localize.EctoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Localize.Ecto

  doctest Localize.Ecto

  defp to_sql(query) do
    {query, _cast_params, _dump_params} =
      Ecto.Adapter.Queryable.plan_query(:all, Ecto.Adapters.Postgres, query)

    IO.iodata_to_binary(Ecto.Adapters.Postgres.Connection.all(query))
  end

  describe "collate/2" do
    test "emits a COLLATE clause with the quoted collation name" do
      query = from p in "products", order_by: collate(p.name, "sv"), select: p.name

      assert to_sql(query) =~ ~s[ORDER BY p0."name" COLLATE "sv-x-icu"]
    end

    test "accepts a pinned runtime locale" do
      locale = "de-DE"
      query = from p in "products", order_by: collate(p.name, ^locale), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "de-x-icu"]
    end

    test "accepts a validated language tag" do
      {:ok, language_tag} = Localize.validate_locale("fr-CA")
      query = from p in "products", order_by: collate(p.name, ^language_tag), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "fr-CA-x-icu"]
    end

    test "collates in select expressions" do
      query = from p in "products", select: collate(p.name, "nb")

      assert to_sql(query) =~ ~s[SELECT p0."name" COLLATE "nb-x-icu"]
    end

    test "collates in where expressions" do
      query = from p in "products", where: collate(p.name, "tr") == "istanbul", select: p.id

      assert to_sql(query) =~ ~s[WHERE (p0."name" COLLATE "tr-x-icu" = 'istanbul')]
    end

    test "uses a collation name given directly" do
      query =
        from p in "products",
          order_by: collate(p.name, collation: "german_phonebook"),
          select: p.name

      assert to_sql(query) =~ ~s[COLLATE "german_phonebook"]
    end

    test "accepts pinned runtime options" do
      options = [collation: "german_phonebook"]
      query = from p in "products", order_by: collate(p.name, ^options), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "german_phonebook"]
    end

    test "resolves a -u-co- locale to its keyword collation name" do
      query =
        from p in "products",
          order_by: collate(p.name, "de-u-co-phonebk"),
          select: p.name

      assert to_sql(query) =~ ~s[COLLATE "de-u-co-phonebk-x-icu"]
    end

    test "collates a comparison" do
      query = from p in "products", where: collate(p.name < p.brand, "de"), select: p.id

      assert to_sql(query) =~ ~s[WHERE (p0."name" < p0."brand" COLLATE "de-x-icu")]
    end

    test "collates comparisons for every operator" do
      for {operator, sql} <- [
            {quote(do: p.a < p.b), "<"},
            {quote(do: p.a > p.b), ">"},
            {quote(do: p.a <= p.b), "<="},
            {quote(do: p.a >= p.b), ">="},
            {quote(do: p.a == p.b), "="},
            {quote(do: p.a != p.b), "<>"}
          ] do
        {query, _} =
          Code.eval_quoted(
            quote do
              import Ecto.Query
              import Localize.Ecto
              from p in "products", select: collate(unquote(operator), "sv")
            end
          )

        assert to_sql(query) =~ ~s[p0."a" #{sql} p0."b" COLLATE "sv-x-icu"]
      end
    end

    test "collates a comparison in a select expression" do
      query = from p in "products", select: collate(p.name < p.brand, "de")

      assert to_sql(query) =~ ~s[SELECT p0."name" < p0."brand" COLLATE "de-x-icu"]
    end

    test "raises for an invalid locale when the query is built" do
      assert_raise Localize.InvalidLocaleError, fn ->
        from p in "products", order_by: collate(p.name, "zzzz"), select: p.name
      end
    end
  end

  describe "collate/1" do
    test "resolves the collation from the current locale" do
      {:ok, _} = Localize.put_locale("da")
      query = from p in "products", order_by: collate(p.name), select: p.name

      assert to_sql(query) =~ ~s[COLLATE "da-x-icu"]
    after
      Localize.put_locale("en")
    end
  end
end
