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

  # The BCP 47 -u- keywords that select a different ICU collator:
  # collation type (co), alternate handling (ka), backwards second
  # level (kb), case level (kc), case first (kf), numeric/natural
  # sort (kn), reordering (kr), strength (ks) and variable top (kv).
  # All of them are carried into the resolved collation name so that
  # creation and query-time resolution stay symmetric.
  @collation_keywords ~w(co ka kb kc kf kn kr ks kv)

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
  Resolves the argument of `Localize.Ecto.collate/2` to a collation
  name.

  This is the runtime companion of the `Localize.Ecto.collate/1,2`
  macros and is not usually called directly.

  ### Arguments

  * `locale_or_options` is a locale accepted by `collation_for!/2`, or
    a keyword list.

  ### Options

  * `:collation` is a collation name used verbatim, bypassing locale
    resolution — for example a collation created with
    `Localize.Ecto.Migration.create_collation/2` under a custom name.

  * Any other options are passed to `collation_for!/2`.

  ### Returns

  * A collation name string, or

  * raises if the locale is not valid.

  ### Examples

      iex> Localize.Ecto.Collation.resolve!("sv")
      "sv-x-icu"

      iex> Localize.Ecto.Collation.resolve!(collation: "german_phonebook")
      "german_phonebook"

  """
  @spec resolve!(Localize.locale() | String.t() | Keyword.t()) :: String.t()
  def resolve!(locale_or_options \\ Localize.get_locale())

  def resolve!(options) when is_list(options) do
    case Keyword.pop(options, :collation) do
      {nil, options} -> collation_for!(Localize.get_locale(), options)
      {collation, _options} -> collation
    end
  end

  def resolve!(locale) do
    collation_for!(locale)
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
  # root-collation request. Extension sections are stripped before
  # matching — they would perturb the language-matching distance (a
  # requested "und-u-ks-level2" must still match the root collation)
  # and the collation-relevant keywords are re-attached afterwards.
  defp match_collation(%LanguageTag{} = language_tag, available) do
    base_id =
      language_tag.canonical_locale_id
      |> String.split("-")
      |> Enum.take_while(&(String.length(&1) > 1))
      |> Enum.join("-")

    base =
      case LanguageTag.best_match(base_id, available) do
        {:ok, locale, _distance} -> locale
        {:error, _} -> "und"
      end

    case collation_keywords(language_tag) do
      [] ->
        base <> "-x-icu"

      keywords ->
        pairs = Enum.map_join(keywords, "-", fn {key, value} -> "#{key}-#{value}" end)
        base <> "-u-" <> pairs <> "-x-icu"
    end
  end

  # The collation-affecting -u- keywords of the locale in their
  # canonical short encoding (:phonebook encodes as "phonebk"),
  # sorted as `Localize.LanguageTag.U.encode/1` produces them. The
  # default collation type (`co-standard`) is dropped — it selects
  # the same collator as the bare locale. PostgreSQL only preloads
  # collations for plain locales, so names carrying any keyword must
  # be created in a migration with
  # `Localize.Ecto.Migration.create_collation/2`.
  defp collation_keywords(%LanguageTag{locale: %Localize.LanguageTag.U{} = u_extension}) do
    u_extension
    |> Localize.LanguageTag.U.encode()
    |> Enum.filter(fn {key, _value} -> key in @collation_keywords end)
    |> Enum.reject(fn {key, value} -> key == "co" and value == "standard" end)
  end

  defp collation_keywords(%LanguageTag{}) do
    []
  end
end
