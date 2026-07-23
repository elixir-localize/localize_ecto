defmodule Localize.Ecto.TextSearch do
  @moduledoc """
  Resolves a locale to the best matching PostgreSQL text search configuration.

  PostgreSQL's full-text search stems and filters words per language via a `regconfig` such as `'french'` or `'german'`. This module maps a `t:Localize.LanguageTag.t/0` (or any locale identifier accepted by `Localize.validate_locale/1`) to the built-in configuration for its language, falling back to the language-agnostic `'simple'` configuration when PostgreSQL has no stemmer for the language.

  The mapping is by the language subtag after locale validation, so regional and script variants resolve to their language's configuration — `"pt-BR"` to `'portuguese'`, `"zh-Hant-TW"` to `'simple'` (PostgreSQL has no Chinese stemmer).

  The primary public API is `config_for/2` and `config_for!/2`, used by the `Localize.Ecto.ts_match/2,3` query macro.

  """

  # PostgreSQL's built-in text search configurations (snowball
  # stemmers plus the hunspell-less defaults), keyed by the language
  # subtag they cover. All three Norwegian subtags share the bokmål
  # based stemmer, matching PostgreSQL's single 'norwegian' config.
  @configs_by_language %{
    "ar" => "arabic",
    "hy" => "armenian",
    "eu" => "basque",
    "ca" => "catalan",
    "da" => "danish",
    "nl" => "dutch",
    "en" => "english",
    "fi" => "finnish",
    "fr" => "french",
    "de" => "german",
    "el" => "greek",
    "hi" => "hindi",
    "hu" => "hungarian",
    "id" => "indonesian",
    "ga" => "irish",
    "it" => "italian",
    "lt" => "lithuanian",
    "ne" => "nepali",
    "nb" => "norwegian",
    "nn" => "norwegian",
    "no" => "norwegian",
    "pt" => "portuguese",
    "ro" => "romanian",
    "ru" => "russian",
    "sr" => "serbian",
    "es" => "spanish",
    "sv" => "swedish",
    "ta" => "tamil",
    "tr" => "turkish",
    "yi" => "yiddish"
  }

  @fallback_config "simple"

  @doc """
  Returns the PostgreSQL text search configuration for a locale.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale identifier accepted by `Localize.validate_locale/1`. The default is `Localize.get_locale/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:available` is a list of configuration names to restrict resolution to — for example the rows of `SELECT cfgname FROM pg_ts_config` when custom configurations replace the built-ins. A language whose configuration is not in the list falls back to `"simple"`.

  ### Returns

  * `{:ok, config_name}` such as `{:ok, "german"}`, or

  * `{:error, exception}` if `locale` is not a valid locale.

  ### Examples

      iex> Localize.Ecto.TextSearch.config_for("de-AT")
      {:ok, "german"}

      iex> Localize.Ecto.TextSearch.config_for("pt-BR")
      {:ok, "portuguese"}

      iex> Localize.Ecto.TextSearch.config_for("ja")
      {:ok, "simple"}

      iex> Localize.Ecto.TextSearch.config_for("en", available: ["simple"])
      {:ok, "simple"}

  """
  @spec config_for(Localize.locale() | String.t(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def config_for(locale \\ Localize.get_locale(), options \\ []) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      # The language is read from the canonical identifier, not the
      # struct's (likely-subtag maximized) language field — a
      # requested "und" must fall back to 'simple', not maximize to
      # "en" and stem as English.
      [language | _rest] = String.split(language_tag.canonical_locale_id, "-")

      config =
        @configs_by_language
        |> Map.get(language, @fallback_config)
        |> restrict_to_available(Keyword.fetch(options, :available))

      {:ok, config}
    end
  end

  defp restrict_to_available(config, :error), do: config

  defp restrict_to_available(config, {:ok, available}) do
    if config in available, do: config, else: @fallback_config
  end

  @doc """
  Returns the PostgreSQL text search configuration for a locale or raises.

  ### Arguments

  * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale identifier accepted by `Localize.validate_locale/1`. The default is `Localize.get_locale/0`.

  * `options` is a keyword list of options. See `config_for/2`.

  ### Returns

  * A configuration name string such as `"german"`.

  ### Examples

      iex> Localize.Ecto.TextSearch.config_for!("fr-CA")
      "french"

  """
  @spec config_for!(Localize.locale() | String.t(), Keyword.t()) :: String.t()
  def config_for!(locale \\ Localize.get_locale(), options \\ []) do
    case config_for(locale, options) do
      {:ok, config} -> config
      {:error, exception} -> raise exception
    end
  end
end
