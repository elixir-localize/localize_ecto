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

    # Tailoring options accepted by `create_collation/2`, using the
    # same vocabulary as `Localize.Collation.Options`, and their
    # encodings as BCP 47 -u- keyword pairs.
    @strength_values %{
      primary: "level1",
      secondary: "level2",
      tertiary: "level3",
      quaternary: "level4",
      identical: "identic"
    }

    @alternate_values %{shifted: "shifted", non_ignorable: "noignore"}

    @case_first_values %{upper: "upper", lower: "lower", false: "false"}

    # Strengths below tertiary make canonically different strings
    # compare equal, which only takes effect in PostgreSQL when the
    # collation is nondeterministic.
    @insensitive_strengths ["level1", "level2"]

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

    * `:strength` is the comparison strength: `:primary` (base letters only — case- and accent-insensitive), `:secondary` (adds accents), `:tertiary` (adds case), `:quaternary`, or `:identical`. Encoded as the `-u-ks-` keyword.

    * `:numeric` as `true` enables natural sort, comparing digit runs by numeric value so "file2" sorts before "file10". Encoded as the `-u-kn-` keyword.

    * `:case_level` as `true` adds a case level between the accent and case strengths, making a `:primary` collation accent-insensitive but case-sensitive. Encoded as the `-u-kc-` keyword.

    * `:case_first` is `:upper`, `:lower`, or `false`, ordering one case before the other. Encoded as the `-u-kf-` keyword.

    * `:alternate` is `:shifted` (punctuation ignored at the primary strengths) or `:non_ignorable`. Encoded as the `-u-ka-` keyword.

    * `:backwards` as `true` compares accents from the end of the string (Canadian French). Encoded as the `-u-kb-` keyword.

    * `:deterministic` determines whether the collation is deterministic. The default is `true` except when the effective strength is `:primary` or `:secondary`, where it defaults to `false` — those strengths only compare case/accent variants as equal when the collation is nondeterministic. Nondeterministic collations work with `=`, `DISTINCT`, `GROUP BY` and unique indexes, but not with `LIKE` or `pg_trgm` (PostgreSQL 18 lifts the `LIKE` restriction).

    * `:if_not_exists` adds `IF NOT EXISTS` when `true`. The default is
      `false`.

    * `:schema` schema-qualifies the collation name.

    ### Returns

    * `:ok`.

    ### Examples

        create_collation("de-u-co-phonebk")

        create_collation("de-u-co-phonebk", name: "german_phonebook")

        # Natural sort: "file2" before "file10"
        create_collation("en", numeric: true)

        # Case- and accent-insensitive; nondeterministic by default.
        # Use in a unique index for case-insensitive uniqueness:
        #   create index("users", [collated(:email, "und-u-ks-level1")], unique: true)
        create_collation("und", strength: :primary)

        create_collation("und", strength: :secondary, name: "case_insensitive")

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
      {name, icu_locale, language_tag} = name_and_icu_locale(locale, options)

      if_not_exists = if options[:if_not_exists], do: "IF NOT EXISTS ", else: ""

      deterministic =
        case Keyword.get_lazy(options, :deterministic, fn ->
               default_deterministic(language_tag)
             end) do
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
      {name, _icu_locale, _language_tag} = name_and_icu_locale(locale, options)

      if_exists = if options[:if_exists], do: "IF EXISTS ", else: ""

      "DROP COLLATION #{if_exists}#{quote_name(name, options[:schema])}"
    end

    @doc """
    Returns a collated column expression for use in an index definition.

    PostgreSQL only uses an index for a collated sort or comparison when
    the index was created with the same collation. This function builds
    the column expression for such an index, for use with
    `Ecto.Migration.index/3`:

        create index("products", [collated(:name, "de")])

        create index("products", [collated(:name, collation: "german_phonebook")])

    Note that if a PostgreSQL upgrade links a newer ICU library whose
    collation data changed — uncommon, but it happens — PostgreSQL warns
    of a collation version mismatch and indexes built with that
    collation must be reindexed (`REINDEX INDEX index_name`, then
    `ALTER COLLATION collation_name REFRESH VERSION`).

    ### Arguments

    * `column` is the column name as an atom or string.

    * `locale_or_options` is a locale accepted by
      `Localize.Ecto.Collation.collation_for!/2`, or a keyword list with
      a `:collation` option naming a collation directly. The default is
      the current locale from `Localize.get_locale/0`.

    ### Returns

    * A column expression string such as `"name" COLLATE "de-x-icu"`.

    ### Examples

        iex> Localize.Ecto.Migration.collated(:name, "de")
        ~s["name" COLLATE "de-x-icu"]

        iex> Localize.Ecto.Migration.collated(:name, collation: "german_phonebook")
        ~s["name" COLLATE "german_phonebook"]

    """
    @spec collated(atom() | String.t(), Localize.locale() | String.t() | Keyword.t()) ::
            String.t()
    def collated(column, locale_or_options \\ Localize.get_locale()) do
      column = to_string(column)
      collation = Collation.resolve!(locale_or_options)

      if String.contains?(column, ~s(")) do
        raise ArgumentError, "column name #{inspect(column)} contains a double quote"
      end

      if String.contains?(collation, ~s(")) do
        raise ArgumentError, "collation name #{inspect(collation)} contains a double quote"
      end

      ~s("#{column}" COLLATE "#{collation}")
    end

    defp collation_sql_pair(locale, options) do
      {create_collation_sql(locale, options), drop_collation_sql(locale, options)}
    end

    # The default name is whatever the resolver produces for the same
    # locale, so creation and query-time resolution stay symmetric. The
    # default ICU locale string is the canonical locale identifier,
    # which preserves all extensions (-u-co-, -u-ks-, and so on).
    # Tailoring options are merged into the locale's -u- keywords
    # before either is derived.
    defp name_and_icu_locale(locale, options) do
      case Localize.validate_locale(locale) do
        {:ok, language_tag} ->
          language_tag = merge_tailoring(language_tag, tailoring_keywords(options))

          name =
            Keyword.get_lazy(options, :name, fn -> Collation.collation_for!(language_tag) end)

          icu_locale = Keyword.get(options, :icu_locale, language_tag.canonical_locale_id)

          if String.contains?(name, ~s(")) do
            raise ArgumentError, "collation name #{inspect(name)} contains a double quote"
          end

          if String.contains?(icu_locale, "'") do
            raise ArgumentError, "ICU locale #{inspect(icu_locale)} contains a single quote"
          end

          {name, icu_locale, language_tag}

        {:error, exception} ->
          raise exception
      end
    end

    defp tailoring_keywords(options) do
      strength =
        case Keyword.fetch(options, :strength) do
          {:ok, strength} -> [{"ks", fetch_value!(@strength_values, :strength, strength)}]
          :error -> []
        end

      alternate =
        case Keyword.fetch(options, :alternate) do
          {:ok, alternate} -> [{"ka", fetch_value!(@alternate_values, :alternate, alternate)}]
          :error -> []
        end

      case_first =
        case Keyword.fetch(options, :case_first) do
          {:ok, case_first} -> [{"kf", fetch_value!(@case_first_values, :case_first, case_first)}]
          :error -> []
        end

      strength ++
        alternate ++
        case_first ++
        boolean_keyword(options, :numeric, "kn") ++
        boolean_keyword(options, :case_level, "kc") ++
        boolean_keyword(options, :backwards, "kb")
    end

    defp boolean_keyword(options, key, encoded_key) do
      case Keyword.fetch(options, key) do
        {:ok, true} -> [{encoded_key, "true"}]
        {:ok, false} -> [{encoded_key, "false"}]
        {:ok, other} -> raise ArgumentError, "#{key} must be a boolean, got #{inspect(other)}"
        :error -> []
      end
    end

    defp fetch_value!(values, key, value) do
      case Map.fetch(values, value) do
        {:ok, encoded} ->
          encoded

        :error ->
          raise ArgumentError,
                "#{key} must be one of #{inspect(Map.keys(values))}, got #{inspect(value)}"
      end
    end

    defp merge_tailoring(language_tag, []) do
      language_tag
    end

    # Merge the tailoring pairs into the locale's existing -u-
    # keywords (tailoring options win) and re-validate the resulting
    # identifier so it is canonicalized exactly as a literal locale
    # string would be.
    defp merge_tailoring(language_tag, pairs) do
      existing =
        case language_tag.locale do
          %Localize.LanguageTag.U{} = u_extension -> Localize.LanguageTag.U.encode(u_extension)
          _no_u_extension -> []
        end

      merged =
        existing
        |> Map.new()
        |> Map.merge(Map.new(pairs))
        |> Enum.sort()
        |> Enum.map_join("-", fn {key, value} -> "#{key}-#{value}" end)

      base =
        language_tag.canonical_locale_id
        |> String.split("-")
        |> Enum.take_while(&(String.length(&1) > 1))
        |> Enum.join("-")

      case Localize.validate_locale(base <> "-u-" <> merged) do
        {:ok, merged_tag} -> merged_tag
        {:error, exception} -> raise exception
      end
    end

    # Nondeterministic is the only mode in which a primary- or
    # secondary-strength collation actually compares case/accent
    # variants as equal, so it is the default for those strengths.
    # An explicit `:deterministic` option always wins.
    defp default_deterministic(language_tag) do
      case language_tag.locale do
        %Localize.LanguageTag.U{} = u_extension ->
          u_extension
          |> Localize.LanguageTag.U.encode()
          |> List.keyfind("ks", 0)
          |> case do
            {"ks", strength} when strength in @insensitive_strengths -> false
            _other -> true
          end

        _no_u_extension ->
          true
      end
    end

    defp quote_name(name, nil), do: ~s("#{name}")
    defp quote_name(name, schema), do: ~s("#{schema}"."#{name}")
  end
end
