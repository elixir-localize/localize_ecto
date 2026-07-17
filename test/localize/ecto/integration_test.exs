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
end
