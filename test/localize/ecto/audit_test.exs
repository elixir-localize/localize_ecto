defmodule Localize.Ecto.AuditTest do
  # Reads server-global catalog state, so not async with the DDL in
  # the integration suite.
  use ExUnit.Case, async: false

  alias Localize.Ecto.Audit
  alias Localize.Ecto.TestRepo

  doctest Localize.Ecto.Audit

  describe "collation_drift/1" do
    test "reports no drift on a healthy database" do
      # A freshly created database records current collation versions,
      # so drift only appears after an ICU upgrade — the healthy path
      # is what CI can assert.
      assert Audit.collation_drift(TestRepo) == []
    end

    test "detects an artificially drifted collation with its indexes" do
      TestRepo.query!(
        "create collation audit_drift (provider = icu, locale = 'de')",
        []
      )

      TestRepo.query!("create table audit_words (word text collate \"audit_drift\")", [])
      TestRepo.query!("create index audit_words_idx on audit_words (word)", [])

      # Backdate the recorded version to simulate an ICU upgrade.
      TestRepo.query!(
        "update pg_collation set collversion = '0.0' where collname = 'audit_drift'",
        []
      )

      assert [entry] = Audit.collation_drift(TestRepo)
      assert entry.name == "audit_drift"
      assert entry.stored_version == "0.0"
      assert entry.actual_version != "0.0"
      assert "audit_words_idx" in entry.indexes

      assert Audit.remediation_sql(entry) == [
               ~s[REINDEX INDEX "audit_words_idx"],
               ~s[ALTER COLLATION "audit_drift" REFRESH VERSION]
             ]
    after
      TestRepo.query!("drop table if exists audit_words", [])
      TestRepo.query!("drop collation if exists audit_drift", [])
    end
  end

  describe "database_collation_drift/1" do
    test "reports no drift on a healthy database" do
      assert Audit.database_collation_drift(TestRepo) == nil
    end
  end

  describe "unicode_versions/1" do
    test "reports server and application versions" do
      versions = Audit.unicode_versions(TestRepo)

      assert is_binary(versions.server.postgres)
      assert is_binary(versions.application.cldr)
      assert is_boolean(versions.drift?)
    end
  end

  describe "timezone_audit/1" do
    test "the application zone inventory is known to the server" do
      audit = Audit.timezone_audit(TestRepo)

      # Both inventories track IANA; a handful of drift entries can
      # appear when tzdata versions differ, but wholesale divergence
      # means a broken inventory on one side.
      assert length(audit.unknown_to_server) < 10
      assert is_list(audit.unknown_to_application)
    end
  end

  describe "report/1" do
    test "combines the audits" do
      report = Audit.report(TestRepo)

      assert Map.has_key?(report, :collation_drift)
      assert Map.has_key?(report, :unicode_versions)
      assert is_boolean(report.ok?)
    end
  end
end
