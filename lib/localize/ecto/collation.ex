defmodule Localize.Ecto.Collation do
  @moduledoc """
  Resolves a locale to the name of a PostgreSQL ICU collation.

  PostgreSQL's `initdb` imports the full set of ICU collations into
  `pg_catalog`, naming each one after its BCP 47 locale identifier with
  an `-x-icu` suffix — for example `de-DE-x-icu`, `zh-Hant-TW-x-icu`
  and the root collation `und-x-icu`.

  This module maps a `t:Localize.LanguageTag.t/0` (or any locale
  identifier accepted by `Localize.validate_locale/1`) onto the best
  matching collation using the [CLDR Language Matching](https://www.unicode.org/reports/tr35/tr35.html#LanguageMatching)
  algorithm implemented by `Localize.LanguageTag.best_match/3`. The
  requested locale is matched against the set of collation locales
  PostgreSQL derives from ICU, bundled with this library, and the root
  collation `und-x-icu` is the fallback of last resort.

  Because CLDR collation tailorings are defined per language (and
  script) rather than per territory, a match to a broader locale — for
  example `de-DE` matching the `de` collation locale — selects an
  identical collator.

  The primary public API is `collation_for/2` and `collation_for!/2`.

  """

  alias Localize.LanguageTag

  @external_resource Path.join(__DIR__, "../../../priv/localize_ecto/pg_icu_collations.txt")

  @known_collations @external_resource
                    |> File.read!()
                    |> String.split("\n", trim: true)

  @root_collation "und-x-icu"

  @doc """
  Returns the PostgreSQL ICU collation name for the given locale.

  Resolutions against the default collation locales are cached, so
  repeated calls for the same locale are inexpensive.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale identifier
    accepted by `Localize.validate_locale/1`. The default is
    `Localize.get_locale/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:available` is a list of BCP 47 locale strings (without the
    `-x-icu` suffix) to match against. The default is the list bundled
    with this library, generated from PostgreSQL's `pg_collation`
    catalog.

  ### Returns

  * `{:ok, collation_name}` where `collation_name` is a string such as
    `"de-x-icu"`, or

  * `{:error, exception}` if `locale` is not a valid locale.

  ### Examples

      iex> Localize.Ecto.Collation.collation_for("de-DE")
      {:ok, "de-x-icu"}

      iex> Localize.Ecto.Collation.collation_for("zh-TW")
      {:ok, "zh-Hant-x-icu"}

      iex> Localize.Ecto.Collation.collation_for("xx")
      {:error, %Localize.InvalidLocaleError{locale_id: "xx"}}

  """
  @spec collation_for(Localize.locale() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def collation_for(locale \\ Localize.get_locale(), options \\ []) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      case Keyword.fetch(options, :available) do
        {:ok, available} -> {:ok, match_collation(language_tag, available)}
        :error -> {:ok, cached_collation(language_tag)}
      end
    end
  end

  @doc """
  Returns the PostgreSQL ICU collation name for the given locale or
  raises.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale identifier
    accepted by `Localize.validate_locale/1`. The default is
    `Localize.get_locale/0`.

  * `options` is a keyword list of options. See `collation_for/2`.

  ### Returns

  * A collation name string such as `"de-x-icu"`, or

  * raises if `locale` is not a valid locale.

  ### Examples

      iex> Localize.Ecto.Collation.collation_for!("sv")
      "sv-x-icu"

      iex> Localize.Ecto.Collation.collation_for!(:"en-GB")
      "en-GB-x-icu"

  """
  @spec collation_for!(Localize.locale() | String.t(), Keyword.t()) :: String.t()
  def collation_for!(locale \\ Localize.get_locale(), options \\ []) do
    case collation_for(locale, options) do
      {:ok, collation} -> collation
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the list of locales for which a PostgreSQL ICU collation is
  known to exist.

  The list contains BCP 47 locale strings without the `-x-icu` suffix,
  as recorded in the `colllocale` column of `pg_collation`.

  ### Returns

  * A list of locale strings.

  ### Examples

      iex> "de-DE" in Localize.Ecto.Collation.known_collations()
      true

      iex> "und" in Localize.Ecto.Collation.known_collations()
      true

  """
  @spec known_collations() :: [String.t()]
  def known_collations do
    @known_collations
  end

  # Matching against the full collation locale list takes a few
  # milliseconds, which is significant on the query-build path, so
  # resolutions against the default list are cached. The set of distinct
  # locales an application resolves is bounded, and entries are written
  # once, which suits :persistent_term.
  defp cached_collation(%LanguageTag{canonical_locale_id: canonical_locale_id} = language_tag) do
    key = {__MODULE__, canonical_locale_id}

    case :persistent_term.get(key, nil) do
      nil ->
        collation = match_collation(language_tag, @known_collations)
        :persistent_term.put(key, collation)
        collation

      collation ->
        collation
    end
  end

  # Matching is on canonical_locale_id rather than the language tag
  # struct: the struct fields are likely-subtag maximized, which would
  # turn a requested "und" into its maximization "en" and lose the
  # root-collation request.
  defp match_collation(%LanguageTag{} = language_tag, available) do
    case LanguageTag.best_match(language_tag.canonical_locale_id, available) do
      {:ok, locale, _distance} -> locale <> "-x-icu"
      {:error, _} -> @root_collation
    end
  end
end
