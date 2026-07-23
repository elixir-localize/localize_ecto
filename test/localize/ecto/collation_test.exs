defmodule Localize.Ecto.CollationTest do
  use ExUnit.Case, async: true

  alias Localize.Ecto.Collation

  doctest Localize.Ecto.Collation

  describe "collation_for/2" do
    test "matches a locale with its own collation exactly" do
      assert Collation.collation_for("en-GB") == {:ok, "en-GB-x-icu"}
      assert Collation.collation_for("pt-BR") == {:ok, "pt-BR-x-icu"}
      assert Collation.collation_for("fr-CA") == {:ok, "fr-CA-x-icu"}
    end

    test "matches a regional locale to its base language collation" do
      # CLDR matching treats these as distance 0; the collations are
      # identical because collation tailorings are per language.
      assert Collation.collation_for("de-DE") == {:ok, "de-x-icu"}
      assert Collation.collation_for("sr-RS") == {:ok, "sr-x-icu"}
    end

    test "resolves a bare language to its collation" do
      assert Collation.collation_for("en") == {:ok, "en-x-icu"}
      assert Collation.collation_for("sv") == {:ok, "sv-x-icu"}
      assert Collation.collation_for(:ja) == {:ok, "ja-x-icu"}
    end

    test "matches script-distinct locales to a script-qualified collation" do
      assert Collation.collation_for("zh-TW") == {:ok, "zh-Hant-x-icu"}
      assert Collation.collation_for("sr-Latn") == {:ok, "sr-Latn-x-icu"}
      assert Collation.collation_for("zh-Hant") == {:ok, "zh-Hant-x-icu"}
    end

    test "matches default-script locales to the base language collation" do
      assert Collation.collation_for("zh-CN") == {:ok, "zh-x-icu"}
      assert Collation.collation_for("sr-Cyrl") == {:ok, "sr-x-icu"}
    end

    test "resolves und to the root collation" do
      assert Collation.collation_for("und") == {:ok, "und-x-icu"}
    end

    test "ignores locale extensions other than the collation type" do
      assert Collation.collation_for("de-u-nu-latn") == {:ok, "de-x-icu"}
      assert Collation.collation_for("en-u-ca-buddhist") == {:ok, "en-x-icu"}
    end

    test "carries the -u-co- collation type into the collation name" do
      assert Collation.collation_for("de-u-co-phonebk") == {:ok, "de-u-co-phonebk-x-icu"}
      assert Collation.collation_for("de-DE-u-co-phonebk") == {:ok, "de-u-co-phonebk-x-icu"}
      assert Collation.collation_for("zh-u-co-stroke") == {:ok, "zh-u-co-stroke-x-icu"}
    end

    test "treats the standard collation type as the default" do
      assert Collation.collation_for("en-u-co-standard") == {:ok, "en-x-icu"}
    end

    test "accepts a validated language tag" do
      {:ok, language_tag} = Localize.validate_locale("fr-CA")
      assert Collation.collation_for(language_tag) == {:ok, "fr-CA-x-icu"}
    end

    test "defaults to the current locale" do
      {:ok, _} = Localize.put_locale("nb")
      assert Collation.collation_for() == {:ok, "nb-x-icu"}
    after
      Localize.put_locale("en")
    end

    test "matches within the language when a script has no collation" do
      # There is no en-Shaw collation locale; matching stays within English.
      assert {:ok, "en" <> _} = Collation.collation_for("en-Shaw")
    end

    test "matches against a caller-supplied available list" do
      assert Collation.collation_for("de-AT", available: ["de", "und"]) ==
               {:ok, "de-x-icu"}

      # The CLDR algorithm selects the first non-und supported locale
      # as the match of last resort.
      assert Collation.collation_for("sv", available: ["de", "und"]) ==
               {:ok, "de-x-icu"}
    end

    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} = Collation.collation_for("zzzz")
    end
  end

  describe "collation_for!/2" do
    test "returns the collation name" do
      assert Collation.collation_for!("da") == "da-x-icu"
    end

    test "raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        Collation.collation_for!("zzzz")
      end
    end
  end

  describe "known_collations/0" do
    test "contains the root locale and common locales" do
      known = Collation.known_collations()
      assert "und" in known
      assert "de-DE" in known
      assert "zh-Hant-TW" in known
      refute "zh-TW" in known
    end
  end

  describe "collation keyword resolution" do
    test "carries collation-affecting -u- keywords into the name" do
      assert Collation.collation_for!("de-u-kn-true") == "de-u-kn-true-x-icu"
      assert Collation.collation_for!("und-u-ks-level2") == "und-u-ks-level2-x-icu"

      assert Collation.collation_for!("und-u-kc-true-ks-level1") ==
               "und-u-kc-true-ks-level1-x-icu"

      assert Collation.collation_for!("de-u-co-phonebk-kn-true") ==
               "de-u-co-phonebk-kn-true-x-icu"
    end

    test "the root locale with keywords still matches the root collation" do
      assert Collation.collation_for!("und-u-ks-level2") == "und-u-ks-level2-x-icu"
    end

    test "non-collation keywords are not carried into the name" do
      assert Collation.collation_for!("de-u-nu-thai-hc-h23") == "de-x-icu"
    end

    test "the default collation type is dropped" do
      assert Collation.collation_for!("de-u-co-standard") == "de-x-icu"
    end
  end
end
