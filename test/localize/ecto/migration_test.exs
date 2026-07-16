defmodule Localize.Ecto.MigrationTest do
  use ExUnit.Case, async: true

  alias Localize.Ecto.Migration

  doctest Localize.Ecto.Migration

  describe "create_collation_sql/2" do
    test "creates a keyword collation named for resolver symmetry" do
      assert Migration.create_collation_sql("de-u-co-phonebk") ==
               ~s[CREATE COLLATION "de-u-co-phonebk-x-icu" (provider = icu, locale = 'de-u-co-phonebk')]
    end

    test "a regional keyword locale keeps its full ICU locale definition" do
      assert Migration.create_collation_sql("de-DE-u-co-phonebk") ==
               ~s[CREATE COLLATION "de-u-co-phonebk-x-icu" (provider = icu, locale = 'de-DE-u-co-phonebk')]
    end

    test "accepts an explicit name" do
      assert Migration.create_collation_sql("de-u-co-phonebk", name: "german_phonebook") ==
               ~s[CREATE COLLATION "german_phonebook" (provider = icu, locale = 'de-u-co-phonebk')]
    end

    test "preserves non-collation extensions in the ICU locale" do
      assert Migration.create_collation_sql("und-u-ks-level2", name: "case_insensitive") ==
               ~s[CREATE COLLATION "case_insensitive" (provider = icu, locale = 'und-u-ks-level2')]
    end

    test "supports deterministic, if_not_exists and schema options" do
      sql =
        Migration.create_collation_sql("de-u-co-phonebk",
          name: "german_phonebook",
          deterministic: false,
          if_not_exists: true,
          schema: "i18n"
        )

      assert sql ==
               ~s[CREATE COLLATION IF NOT EXISTS "i18n"."german_phonebook" ] <>
                 ~s[(provider = icu, locale = 'de-u-co-phonebk', deterministic = false)]
    end

    test "raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Migration.create_collation_sql("zzzz")
      end
    end

    test "rejects a name containing a double quote" do
      assert_raise ArgumentError, fn ->
        Migration.create_collation_sql("de", name: ~s(bad"name))
      end
    end

    test "rejects an ICU locale containing a single quote" do
      assert_raise ArgumentError, fn ->
        Migration.create_collation_sql("de", icu_locale: "de'; drop table x; --")
      end
    end
  end

  describe "collated/2" do
    test "builds a collated column expression from a locale" do
      assert Migration.collated(:name, "de") == ~s["name" COLLATE "de-x-icu"]

      assert Migration.collated("name", "de-u-co-phonebk") ==
               ~s["name" COLLATE "de-u-co-phonebk-x-icu"]
    end

    test "builds a collated column expression from a collation name" do
      assert Migration.collated(:name, collation: "german_phonebook") ==
               ~s["name" COLLATE "german_phonebook"]
    end

    test "defaults to the current locale" do
      {:ok, _} = Localize.put_locale("sv")
      assert Migration.collated(:name) == ~s["name" COLLATE "sv-x-icu"]
    after
      Localize.put_locale("en")
    end

    test "raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Migration.collated(:name, "zzzz")
      end
    end

    test "rejects identifiers containing double quotes" do
      assert_raise ArgumentError, fn ->
        Migration.collated(~s(bad"name), "de")
      end

      assert_raise ArgumentError, fn ->
        Migration.collated(:name, collation: ~s(bad"collation))
      end
    end
  end

  describe "drop_collation_sql/2" do
    test "drops by the resolver-symmetric name" do
      assert Migration.drop_collation_sql("de-u-co-phonebk") ==
               ~s[DROP COLLATION "de-u-co-phonebk-x-icu"]
    end

    test "supports if_exists and schema options" do
      assert Migration.drop_collation_sql("de-u-co-phonebk",
               name: "german_phonebook",
               if_exists: true,
               schema: "i18n"
             ) == ~s[DROP COLLATION IF EXISTS "i18n"."german_phonebook"]
    end
  end
end
