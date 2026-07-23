defmodule Localize.Ecto.TextSearchTest do
  use ExUnit.Case, async: true

  alias Localize.Ecto.TextSearch

  doctest Localize.Ecto.TextSearch

  describe "config_for/2" do
    test "resolves by language subtag" do
      assert TextSearch.config_for("de") == {:ok, "german"}
      assert TextSearch.config_for("de-AT") == {:ok, "german"}
      assert TextSearch.config_for("pt-BR") == {:ok, "portuguese"}
      assert TextSearch.config_for("nn") == {:ok, "norwegian"}
    end

    test "falls back to simple for languages without a stemmer" do
      assert TextSearch.config_for("ja") == {:ok, "simple"}
      assert TextSearch.config_for("zh-Hant-TW") == {:ok, "simple"}
      assert TextSearch.config_for("und") == {:ok, "simple"}
    end

    test "restricts to an available list" do
      assert TextSearch.config_for("de", available: ["english", "simple"]) == {:ok, "simple"}
      assert TextSearch.config_for("de", available: ["german"]) == {:ok, "german"}
    end

    test "returns an error for an invalid locale" do
      assert {:error, %Localize.InvalidLocaleError{}} = TextSearch.config_for("zzzz")
    end
  end

  describe "config_for!/2" do
    test "raises for an invalid locale" do
      assert_raise Localize.InvalidLocaleError, fn -> TextSearch.config_for!("zzzz") end
    end
  end
end
