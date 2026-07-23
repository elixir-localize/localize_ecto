if Code.ensure_loaded?(Ecto.Migration) do
  defmodule Mix.Tasks.Localize.Ecto.Audit do
    @shortdoc "Audits PostgreSQL collation versions and time zones against the application"

    @moduledoc """
    Audits the PostgreSQL server's collation and Unicode state against the running application.

        mix localize.ecto.audit
        mix localize.ecto.audit -r MyApp.Repo

    Reports, for each configured repo:

    * ICU and libc collations whose recorded version differs from the current collation library — with the indexes that depend on them and the `REINDEX` / `ALTER COLLATION … REFRESH VERSION` statements that remediate the drift.

    * Database default collation version drift.

    * The server's PostgreSQL/Unicode/ICU versions versus the application's CLDR version.

    * Time zone names the application knows but the server does not (and the reverse).

    Exits with a non-zero status when any collation drift is found, so the task can gate CI or deploys.

    ## Command line options

    * `-r`, `--repo` — the repo to audit. Defaults to the application's configured `ecto_repos`. May be given more than once.

    """

    use Mix.Task

    alias Localize.Ecto.Audit

    @impl Mix.Task
    def run(args) do
      repos = Mix.Ecto.parse_repo(args)

      Mix.Task.run("app.config")

      {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

      results =
        for repo <- repos do
          Mix.Ecto.ensure_repo(repo, args)

          started =
            case repo.start_link(pool_size: 2) do
              {:ok, _pid} -> true
              {:error, {:already_started, _pid}} -> false
            end

          report = Audit.report(repo)
          print_report(repo, report)
          if started, do: repo.stop()
          report
        end

      unless Enum.all?(results, & &1.ok?) do
        Mix.raise("collation or time zone drift detected — see the report above")
      end

      :ok
    end

    defp print_report(repo, report) do
      Mix.shell().info("Audit for #{inspect(repo)}")

      print_collation_drift(report.collation_drift)
      print_database_drift(report.database_collation_drift)
      print_unicode_versions(report.unicode_versions)
      print_timezone_audit(report.timezone_audit)
    end

    defp print_collation_drift([]) do
      Mix.shell().info("  Collation versions: no drift")
    end

    defp print_collation_drift(drift) do
      Mix.shell().error("  Collation versions: #{length(drift)} drifted")

      for entry <- drift do
        Mix.shell().error(
          "    #{entry.name}: recorded #{entry.stored_version}, actual #{entry.actual_version}" <>
            " (#{length(entry.indexes)} dependent indexes)"
        )

        for sql <- Audit.remediation_sql(entry) do
          Mix.shell().info("      #{sql};")
        end
      end
    end

    defp print_database_drift(nil) do
      Mix.shell().info("  Database default collation: no drift")
    end

    defp print_database_drift(drift) do
      Mix.shell().error(
        "  Database default collation #{drift.collation}: recorded #{drift.stored_version}, " <>
          "actual #{drift.actual_version} — REINDEX affected indexes, then " <>
          "ALTER DATABASE ... REFRESH COLLATION VERSION"
      )
    end

    defp print_unicode_versions(versions) do
      Mix.shell().info(
        "  Server: PostgreSQL #{versions.server.postgres}, " <>
          "Unicode #{versions.server.unicode || "unknown"}, " <>
          "ICU Unicode #{versions.server.icu_unicode || "unknown"}"
      )

      Mix.shell().info(
        "  Application: CLDR #{versions.application.cldr}, " <>
          "Unicode #{versions.application.unicode || "unknown"}"
      )

      if versions.drift? do
        Mix.shell().error(
          "  The server's ICU Unicode version differs from the application's — " <>
            "Elixir-side and SQL-side collation may order edge cases differently"
        )
      end
    end

    defp print_timezone_audit(%{unknown_to_server: [], unknown_to_application: unknown}) do
      Mix.shell().info(
        "  Time zones: all application zones known to the server " <>
          "(#{length(unknown)} server-only zones)"
      )
    end

    defp print_timezone_audit(audit) do
      Mix.shell().error(
        "  Time zones unknown to the server: #{Enum.join(audit.unknown_to_server, ", ")}"
      )
    end
  end
end
