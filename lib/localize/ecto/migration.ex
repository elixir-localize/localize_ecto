if Code.ensure_loaded?(Ecto.Migration) do
  defmodule Localize.Ecto.Migration do
    @moduledoc """
    Migration helpers for creating PostgreSQL ICU collations.

    PostgreSQL preloads ICU collations for plain locales, but not for
    locales carrying a BCP 47 collation type such as `de-u-co-phonebk`
    (German phonebook ordering) or `zh-u-co-stroke` (Chinese stroke
    ordering). Those must be created once per database, which belongs
    in a migration:

        defmodule MyApp.Repo.Migrations.AddPhonebookCollation do
          use Ecto.Migration

          import Localize.Ecto.Migration

          def change do
            create_collation("de-u-co-phonebk")
          end
        end

    The default collation name is the one `Localize.Ecto.Collation`
    resolves the same locale to, so once created, the collation is used
    automatically by `Localize.Ecto.collate/2`:

        from p in Product, order_by: collate(p.name, "de-u-co-phonebk")

    The primary public API is `create_collation/2` and
    `drop_collation/2`. The SQL they execute is also available from
    `create_collation_sql/2` and `drop_collation_sql/2`.

    """

    alias Localize.Ecto.Collation

    @doc """
    Creates an ICU collation in a migration.

    Runs `CREATE COLLATION` with the ICU provider. The operation is
    reversible: rolling back drops the collation.

    ### Arguments

    * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale
      identifier accepted by `Localize.validate_locale/1`.

    * `options` is a keyword list of options.

    ### Options

    * `:name` is the collation name to create. The default is the name
      `Localize.Ecto.Collation.collation_for!/1` resolves `locale` to,
      such as `"de-u-co-phonebk-x-icu"`, so queries built with
      `Localize.Ecto.collate/2` find the collation without further
      configuration.

    * `:icu_locale` is the ICU locale string for the collation
      definition. The default is the canonical locale identifier of
      `locale`, which preserves all BCP 47 extensions.

    * `:deterministic` determines whether the collation is
      deterministic. The default is `true`, matching PostgreSQL's
      default. Non-deterministic collations compare canonically
      equivalent strings as equal but cannot be used with `LIKE` or
      pattern matching.

    * `:if_not_exists` adds `IF NOT EXISTS` when `true`. The default is
      `false`.

    * `:schema` schema-qualifies the collation name.

    ### Returns

    * `:ok`.

    ### Examples

        create_collation("de-u-co-phonebk")

        create_collation("de-u-co-phonebk", name: "german_phonebook")

        create_collation("und-u-ks-level2", name: "case_insensitive", deterministic: false)

    """
    @spec create_collation(Localize.locale() | String.t(), Keyword.t()) :: :ok
    def create_collation(locale, options \\ []) do
      {create, drop} = collation_sql_pair(locale, options)
      Ecto.Migration.execute(create, drop)
    end

    @doc """
    Drops an ICU collation in a migration.

    The operation is reversible: rolling back recreates the collation
    from the same arguments.

    ### Arguments

    * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale
      identifier accepted by `Localize.validate_locale/1`.

    * `options` is a keyword list of options. See `create_collation/2`;
      `:if_not_exists` is replaced by `:if_exists`.

    ### Returns

    * `:ok`.

    ### Examples

        drop_collation("de-u-co-phonebk")

        drop_collation("de-u-co-phonebk", name: "german_phonebook")

    """
    @spec drop_collation(Localize.locale() | String.t(), Keyword.t()) :: :ok
    def drop_collation(locale, options \\ []) do
      {create, drop} = collation_sql_pair(locale, options)
      Ecto.Migration.execute(drop, create)
    end

    @doc """
    Returns the `CREATE COLLATION` statement for a locale.

    ### Arguments

    * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale
      identifier accepted by `Localize.validate_locale/1`.

    * `options` is a keyword list of options. See `create_collation/2`.

    ### Returns

    * The SQL statement as a string.

    ### Examples

        iex> Localize.Ecto.Migration.create_collation_sql("de-u-co-phonebk")
        ~s[CREATE COLLATION "de-u-co-phonebk-x-icu" (provider = icu, locale = 'de-u-co-phonebk')]

        iex> Localize.Ecto.Migration.create_collation_sql("de-u-co-phonebk", name: "german_phonebook")
        ~s[CREATE COLLATION "german_phonebook" (provider = icu, locale = 'de-u-co-phonebk')]

    """
    @spec create_collation_sql(Localize.locale() | String.t(), Keyword.t()) :: String.t()
    def create_collation_sql(locale, options \\ []) do
      {name, icu_locale} = name_and_icu_locale(locale, options)

      if_not_exists = if options[:if_not_exists], do: "IF NOT EXISTS ", else: ""

      deterministic =
        case Keyword.get(options, :deterministic, true) do
          true -> ""
          false -> ", deterministic = false"
        end

      "CREATE COLLATION #{if_not_exists}#{quote_name(name, options[:schema])} " <>
        "(provider = icu, locale = '#{icu_locale}'#{deterministic})"
    end

    @doc """
    Returns the `DROP COLLATION` statement for a locale.

    ### Arguments

    * `locale` is a `t:Localize.LanguageTag.t/0`, or any locale
      identifier accepted by `Localize.validate_locale/1`.

    * `options` is a keyword list of options. See `drop_collation/2`.

    ### Returns

    * The SQL statement as a string.

    ### Examples

        iex> Localize.Ecto.Migration.drop_collation_sql("de-u-co-phonebk")
        ~s[DROP COLLATION "de-u-co-phonebk-x-icu"]

        iex> Localize.Ecto.Migration.drop_collation_sql("de-u-co-phonebk", if_exists: true)
        ~s[DROP COLLATION IF EXISTS "de-u-co-phonebk-x-icu"]

    """
    @spec drop_collation_sql(Localize.locale() | String.t(), Keyword.t()) :: String.t()
    def drop_collation_sql(locale, options \\ []) do
      {name, _icu_locale} = name_and_icu_locale(locale, options)

      if_exists = if options[:if_exists], do: "IF EXISTS ", else: ""

      "DROP COLLATION #{if_exists}#{quote_name(name, options[:schema])}"
    end

    defp collation_sql_pair(locale, options) do
      {create_collation_sql(locale, options), drop_collation_sql(locale, options)}
    end

    # The default name is whatever the resolver produces for the same
    # locale, so creation and query-time resolution stay symmetric. The
    # default ICU locale string is the canonical locale identifier,
    # which preserves all extensions (-u-co-, -u-ks-, and so on).
    defp name_and_icu_locale(locale, options) do
      case Localize.validate_locale(locale) do
        {:ok, language_tag} ->
          name =
            Keyword.get_lazy(options, :name, fn -> Collation.collation_for!(language_tag) end)

          icu_locale = Keyword.get(options, :icu_locale, language_tag.canonical_locale_id)

          if String.contains?(name, ~s(")) do
            raise ArgumentError, "collation name #{inspect(name)} contains a double quote"
          end

          if String.contains?(icu_locale, "'") do
            raise ArgumentError, "ICU locale #{inspect(icu_locale)} contains a single quote"
          end

          {name, icu_locale}

        {:error, exception} ->
          raise exception
      end
    end

    defp quote_name(name, nil), do: ~s("#{name}")
    defp quote_name(name, schema), do: ~s("#{schema}"."#{name}")
  end
end
