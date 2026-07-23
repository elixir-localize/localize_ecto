defmodule Localize.Ecto.IntegrationTest do
  # Migrations and DDL are global to the test database, so this suite
  # is not async.
  use ExUnit.Case, async: false

  import Ecto.Query
  import Localize.Ecto

  alias Localize.Ecto.TestRepo

  defmodule AddPhonebookCollation do
    use Ecto.Migration

    import Localize.Ecto.Migration

    def change do
      create_collation("de-u-co-phonebk", if_not_exists: true)
      create_collation("de-u-co-phonebk", name: "german_phonebook", if_not_exists: true)
    end
  end

  defmodule DropPhonebookCollation do
    use Ecto.Migration

    import Localize.Ecto.Migration

    def change do
      drop_collation("de-u-co-phonebk", name: "german_phonebook", if_exists: true)
    end
  end

  setup_all do
    TestRepo.query!("create table if not exists words (id serial primary key, word text)")
    TestRepo.query!("truncate words")

    for word <- ["Muller", "Müller", "Mueller", "Mahler"] do
      TestRepo.query!("insert into words (word) values ($1)", [word])
    end

    :ok
  end

  defp migrate(:up, migration, version) do
    Ecto.Migrator.up(TestRepo, version, migration, log: false)
  end

  defp migrate(:down, migration, version) do
    Ecto.Migrator.down(TestRepo, version, migration, log: false)
  end

  defp collation_names do
    "select collname from pg_collation where collname like '%phonebk%' or collname like '%phonebook%'"
    |> TestRepo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp words_ordered_by(locale_or_options) do
    query = from w in "words", order_by: collate(w.word, ^locale_or_options), select: w.word
    TestRepo.all(query)
  end

  describe "create_collation/2 and drop_collation/2 in a migration" do
    test "creating, using, rolling back and dropping collations" do
      assert :ok = migrate(:up, AddPhonebookCollation, 20_260_717_000_001)
      assert "de-u-co-phonebk-x-icu" in collation_names()
      assert "german_phonebook" in collation_names()

      # Standard German sorts ü after u; phonebook order treats ü as ue.
      assert words_ordered_by("de") == ["Mahler", "Mueller", "Muller", "Müller"]
      assert words_ordered_by("de-u-co-phonebk") == ["Mahler", "Mueller", "Müller", "Muller"]

      assert words_ordered_by(collation: "german_phonebook") ==
               ["Mahler", "Mueller", "Müller", "Muller"]

      # A collated comparison in a where clause.
      comparison =
        from w in "words",
          where: collate(w.word < "Muller", "de-u-co-phonebk"),
          order_by: w.word,
          select: w.word

      assert TestRepo.all(comparison) == ["Mahler", "Mueller", "Müller"]

      # drop_collation/2 is reversible too: run its migration up, then
      # roll both migrations back and confirm the collations are gone.
      assert :ok = migrate(:up, DropPhonebookCollation, 20_260_717_000_002)
      refute "german_phonebook" in collation_names()

      assert :ok = migrate(:down, DropPhonebookCollation, 20_260_717_000_002)
      assert "german_phonebook" in collation_names()

      assert :ok = migrate(:down, AddPhonebookCollation, 20_260_717_000_001)
      refute "de-u-co-phonebk-x-icu" in collation_names()
      refute "german_phonebook" in collation_names()
    end
  end

  describe "collate/1,2 against a live server" do
    test "orders by locale-specific collations" do
      assert words_ordered_by("de") == ["Mahler", "Mueller", "Muller", "Müller"]
      assert words_ordered_by("sv") == ["Mahler", "Mueller", "Muller", "Müller"]
    end

    test "orders by the current locale" do
      {:ok, _} = Localize.put_locale("de")
      query = from w in "words", order_by: collate(w.word), select: w.word

      assert TestRepo.all(query) == ["Mahler", "Mueller", "Muller", "Müller"]
    after
      Localize.put_locale("en")
    end
  end

  defmodule AddNaturalSortCollation do
    use Ecto.Migration

    import Localize.Ecto.Migration

    def change do
      create_collation("en", numeric: true, if_not_exists: true)
    end
  end

  defmodule AddInsensitiveCollation do
    use Ecto.Migration

    import Localize.Ecto.Migration

    def change do
      create_collation("und", strength: :secondary, if_not_exists: true)
    end
  end

  describe "natural sort collation" do
    test "digit runs compare numerically" do
      assert :ok = migrate(:up, AddNaturalSortCollation, 20_260_723_000_001)

      TestRepo.query!("create table if not exists files (name text)")
      TestRepo.query!("truncate files")

      for name <- ["file10", "file2", "file1"] do
        TestRepo.query!("insert into files (name) values ($1)", [name])
      end

      natural =
        from f in "files", order_by: collate(f.name, "en-u-kn-true"), select: f.name

      assert TestRepo.all(natural) == ["file1", "file2", "file10"]

      lexical = from f in "files", order_by: collate(f.name, "en"), select: f.name
      assert TestRepo.all(lexical) == ["file1", "file10", "file2"]
    after
      migrate(:down, AddNaturalSortCollation, 20_260_723_000_001)
      TestRepo.query!("drop table if exists files")
    end
  end

  describe "at_time_zone/2 against a live server" do
    test "converts with a canonicalized zone" do
      query =
        from w in fragment("(select timestamp with time zone '2026-01-01 00:00:00+00' as t)"),
          select: at_time_zone(w.t, "Australia/NSW")

      assert [%NaiveDateTime{} = local] = TestRepo.all(query)
      # Sydney is UTC+11 in January (daylight saving).
      assert local == ~N[2026-01-01 11:00:00.000000]
    end

    test "an unknown zone raises before reaching the server" do
      assert_raise Localize.UnknownTimezoneError, fn ->
        TestRepo.all(from w in "words", select: at_time_zone(fragment("now()"), "Nowhere/Void"))
      end
    end
  end

  describe "ts_match/2,3 against a live server" do
    setup do
      TestRepo.query!("create table if not exists articles (body text)")
      TestRepo.query!("truncate articles")

      for body <- ["Die Häuser der Stadt", "The houses of the city"] do
        TestRepo.query!("insert into articles (body) values ($1)", [body])
      end

      on_exit(fn -> TestRepo.query!("drop table if exists articles") end)
      :ok
    end

    test "stems per the locale's configuration" do
      # German stemming matches "Häuser" (houses) from the singular "Haus".
      german = from a in "articles", where: ts_match(a.body, "Haus", "de"), select: a.body
      assert TestRepo.all(german) == ["Die Häuser der Stadt"]

      # English stemming matches "houses" from "house".
      english = from a in "articles", where: ts_match(a.body, "house", "en"), select: a.body
      assert TestRepo.all(english) == ["The houses of the city"]

      # The simple config does no stemming, so the singular misses.
      simple =
        from a in "articles", where: ts_match(a.body, "house", config: "simple"), select: a.body

      assert TestRepo.all(simple) == []
    end
  end

  describe "locale-aware case mapping against a live server" do
    test "Turkish dotless i" do
      query =
        from w in fragment("(select 'INDIGO' as word)"),
          select: {lower(w.word, "tr"), lower(w.word, "en")}

      assert [{turkish, english}] = TestRepo.all(query)
      assert turkish == "ındıgo"
      assert english == "indigo"
    end

    test "upper and initcap follow the collation" do
      query =
        from w in fragment("(select 'indigo' as word)"),
          select: {upper(w.word, "tr"), initcap(w.word, "en")}

      assert [{turkish_upper, english_initcap}] = TestRepo.all(query)
      assert turkish_upper == "İNDİGO"
      assert english_initcap == "Indigo"
    end
  end

  describe "case- and accent-insensitive collation" do
    test "equality and unique indexes are insensitive" do
      assert :ok = migrate(:up, AddInsensitiveCollation, 20_260_723_000_002)

      TestRepo.query!("create table if not exists people (email text)")
      TestRepo.query!("truncate people")
      TestRepo.query!("insert into people (email) values ($1)", ["Kip@Example.com"])

      insensitive =
        from p in "people",
          where: collate(p.email == "kip@example.com", "und-u-ks-level2"),
          select: p.email

      assert TestRepo.all(insensitive) == ["Kip@Example.com"]

      sensitive =
        from p in "people", where: p.email == "kip@example.com", select: p.email

      assert TestRepo.all(sensitive) == []

      # A unique index over the insensitive collation rejects a
      # case-variant duplicate.
      TestRepo.query!(
        "create unique index people_email_ci on people ((email COLLATE \"und-u-ks-level2-x-icu\"))"
      )

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
               TestRepo.query("insert into people (email) values ($1)", ["KIP@EXAMPLE.COM"])
    after
      TestRepo.query!("drop table if exists people")
      migrate(:down, AddInsensitiveCollation, 20_260_723_000_002)
    end
  end
end
