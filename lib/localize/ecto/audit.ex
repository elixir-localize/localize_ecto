defmodule Localize.Ecto.Audit do
  @moduledoc """
  Audits the PostgreSQL server's collation and Unicode state against the running application.

  Collations are compiled into indexes: when a PostgreSQL upgrade (or an OS upgrade underneath it) links a newer ICU library whose collation data changed, every index built with an affected collation is silently inconsistent with new comparisons until it is reindexed. PostgreSQL records the collation version each collation was created with and warns on first use after a change; this module surfaces the drift proactively and generates the remediation statements.

  The primary public API is `report/1` — used by the `mix localize.ecto.audit` task — with `collation_drift/1`, `database_collation_drift/1`, `remediation_sql/1` and `unicode_versions/1` as the individual checks.

  All functions take a started `Ecto.Repo` for a PostgreSQL database.

  """

  # The Unicode version each recent CLDR release is built on, used to
  # compare the application's collation expectations (Localize bundles
  # CLDR root collation data) with the server's ICU Unicode version.
  @cldr_unicode_versions %{
    43 => "15.0",
    44 => "15.1",
    45 => "15.1",
    46 => "16.0",
    47 => "16.0",
    48 => "16.0",
    49 => "17.0"
  }

  @drifted_collations_sql """
  SELECT c.oid::bigint, c.collname, c.collversion, pg_collation_actual_version(c.oid)
  FROM pg_collation c
  WHERE c.collversion IS NOT NULL
    AND pg_collation_actual_version(c.oid) IS NOT NULL
    AND c.collversion <> pg_collation_actual_version(c.oid)
  ORDER BY c.collname
  """

  @dependent_indexes_sql """
  SELECT DISTINCT cl.relname
  FROM pg_depend d
  JOIN pg_class cl ON cl.oid = d.objid AND cl.relkind = 'i'
  WHERE d.refclassid = 'pg_collation'::regclass AND d.refobjid = $1
  ORDER BY cl.relname
  """

  @database_collation_sql """
  SELECT datcollate, datcollversion, pg_database_collation_actual_version(oid)
  FROM pg_database
  WHERE datname = current_database()
  """

  @doc """
  Returns the collations whose recorded version differs from the collation library's current version.

  ### Arguments

  * `repo` is a started `Ecto.Repo` module for a PostgreSQL database.

  ### Returns

  * A list of maps with `:name`, `:stored_version`, `:actual_version` and `:indexes` (the names of indexes depending on the collation, which need reindexing). An empty list means no drift.

  ### Examples

      Localize.Ecto.Audit.collation_drift(MyApp.Repo)
      #=> []

  """
  @spec collation_drift(module()) :: [map()]
  def collation_drift(repo) do
    %{rows: rows} = repo.query!(@drifted_collations_sql, [])

    for [oid, name, stored, actual] <- rows do
      %{rows: index_rows} = repo.query!(@dependent_indexes_sql, [oid])

      %{
        name: name,
        stored_version: stored,
        actual_version: actual,
        indexes: List.flatten(index_rows)
      }
    end
  end

  @doc """
  Returns the database default collation's version drift, or `nil` when there is none.

  The database default collation orders every text column without an explicit collation, so drift here potentially affects every index on text columns.

  ### Arguments

  * `repo` is a started `Ecto.Repo` module for a PostgreSQL database.

  ### Returns

  * `nil` when the default collation version matches, or a map with `:collation`, `:stored_version` and `:actual_version`.

  """
  @spec database_collation_drift(module()) :: map() | nil
  def database_collation_drift(repo) do
    case repo.query!(@database_collation_sql, []) do
      %{rows: [[_collation, stored, actual]]}
      when is_nil(stored) or is_nil(actual) or stored == actual ->
        nil

      %{rows: [[collation, stored, actual]]} ->
        %{collation: collation, stored_version: stored, actual_version: actual}
    end
  end

  @doc """
  Returns the remediation statements for one entry of `collation_drift/1`.

  Reindex first, then refresh the recorded version — refreshing first would hide the drift while the indexes are still stale.

  ### Arguments

  * `drift` is one map from `collation_drift/1`.

  ### Returns

  * A list of SQL statements.

  ### Examples

      iex> Localize.Ecto.Audit.remediation_sql(%{name: "de-x-icu", indexes: ["idx_names"], stored_version: "153.14", actual_version: "153.120"})
      [~s[REINDEX INDEX "idx_names"], ~s[ALTER COLLATION "de-x-icu" REFRESH VERSION]]

  """
  @spec remediation_sql(map()) :: [String.t()]
  def remediation_sql(%{name: name, indexes: indexes}) do
    reindexes = Enum.map(indexes, fn index -> ~s[REINDEX INDEX "#{index}"] end)
    reindexes ++ [~s[ALTER COLLATION "#{name}" REFRESH VERSION]]
  end

  @doc """
  Returns the Unicode-relevant versions of the server and the application.

  ### Arguments

  * `repo` is a started `Ecto.Repo` module for a PostgreSQL database.

  ### Returns

  * A map with `:server` (`:postgres`, `:unicode`, `:icu_unicode` — the latter two `nil` before PostgreSQL 17) and `:application` (`:cldr`, `:unicode`). When the server's ICU Unicode version and the application's CLDR-implied Unicode version differ, `:drift?` is `true` — collation results computed in Elixir by `Localize.Collation` may then order edge-case strings differently from the server.

  """
  @spec unicode_versions(module()) :: map()
  def unicode_versions(repo) do
    %{rows: [[postgres_version]]} = repo.query!("SELECT current_setting('server_version')", [])

    cldr_version = Localize.version()
    application_unicode = Map.get(@cldr_unicode_versions, cldr_version.major)

    server_unicode = optional_scalar(repo, "SELECT unicode_version()")
    server_icu_unicode = optional_scalar(repo, "SELECT icu_unicode_version()")

    drift? =
      not is_nil(server_icu_unicode) and not is_nil(application_unicode) and
        server_icu_unicode != application_unicode

    %{
      server: %{
        postgres: postgres_version,
        unicode: server_unicode,
        icu_unicode: server_icu_unicode
      },
      application: %{cldr: to_string(cldr_version), unicode: application_unicode},
      drift?: drift?
    }
  end

  @doc """
  Runs every audit and returns the combined result.

  ### Arguments

  * `repo` is a started `Ecto.Repo` module for a PostgreSQL database.

  ### Returns

  * A map with `:collation_drift`, `:database_collation_drift`, `:unicode_versions`, `:timezone_audit` and `:ok?` — `true` when nothing needs attention.

  """
  @spec report(module()) :: map()
  def report(repo) do
    collation_drift = collation_drift(repo)
    database_drift = database_collation_drift(repo)
    unicode_versions = unicode_versions(repo)
    timezone_audit = timezone_audit(repo)

    %{
      collation_drift: collation_drift,
      database_collation_drift: database_drift,
      unicode_versions: unicode_versions,
      timezone_audit: timezone_audit,
      ok?:
        collation_drift == [] and is_nil(database_drift) and
          not unicode_versions.drift? and timezone_audit.unknown_to_server == []
    }
  end

  @doc """
  Compares the application's IANA time zone inventory with the server's.

  A zone name the server does not know fails at query time in `AT TIME ZONE`; a zone the application does not know cannot be validated by `Localize.Ecto.Type.TimeZone`. Small differences are normal — the server's tzdata and CLDR's zone inventory update on different schedules — but zones the application writes must exist on the server.

  ### Arguments

  * `repo` is a started `Ecto.Repo` module for a PostgreSQL database.

  ### Returns

  * A map with `:unknown_to_server` (canonical CLDR zones missing from `pg_timezone_names`) and `:unknown_to_application` (server zones absent from the CLDR inventory, excluding the `posix/`, `Etc/` and abbreviation-style entries PostgreSQL adds).

  """
  @spec timezone_audit(module()) :: map()
  def timezone_audit(repo) do
    %{rows: rows} = repo.query!("SELECT name FROM pg_timezone_names", [])
    server_zones = rows |> List.flatten() |> MapSet.new()

    application_zones = MapSet.new(Localize.DateTime.Timezone.known_timezones())

    unknown_to_server =
      application_zones
      |> MapSet.difference(server_zones)
      |> Enum.sort()

    unknown_to_application =
      server_zones
      |> MapSet.difference(application_zones)
      |> Enum.reject(fn name ->
        String.starts_with?(name, ["posix/", "Etc/", "SystemV/", "right/"]) or
          not String.contains?(name, "/")
      end)
      |> Enum.sort()

    %{unknown_to_server: unknown_to_server, unknown_to_application: unknown_to_application}
  end

  defp optional_scalar(repo, sql) do
    case repo.query(sql, []) do
      {:ok, %{rows: [[value]]}} -> value
      {:error, _not_supported} -> nil
    end
  end
end
