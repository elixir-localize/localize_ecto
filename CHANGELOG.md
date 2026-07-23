# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* Collation resolution carries all collation-affecting BCP 47 `-u-` keywords (`kn`, `ks`, `kc`, `kf`, `ka`, `kb`, `kr`, `kv`) into the collation name, so `collate(f.name, "en-u-kn-true")` finds a natural-sort collation created in a migration.

* `create_collation/2` accepts tailoring options (`:strength`, `:numeric`, `:case_level`, `:case_first`, `:alternate`, `:backwards`) using the `Localize.Collation.Options` vocabulary. Primary and secondary strengths default to a nondeterministic collation, enabling case/accent-insensitive equality and unique indexes.

* `mix localize.ecto.audit` and `Localize.Ecto.Audit` report collation version drift with per-index remediation SQL, database default collation drift, server-versus-application Unicode/ICU/CLDR versions, and time zone inventory differences.

* `Localize.Ecto.Type.TimeZone` is an Ecto type for IANA time zone identifiers, canonicalizing aliases and BCP 47 short zone ids against the CLDR inventory; `at_time_zone/2` applies a validated `AT TIME ZONE`.

* `Localize.Ecto.TextSearch.config_for/2` resolves a locale to the best PostgreSQL text search configuration, and `ts_match/2,3` builds a locale-aware `to_tsvector … @@ websearch_to_tsquery` match.

* `lower/1,2`, `upper/1,2` and `initcap/1,2` apply locale-aware case mapping via the locale's collation ("INDIGO" lowercases to "ındıgo" under `"tr"`).

### Changed

* Requires Localize `~> 1.0-rc.1` for the CLDR time zone inventory.

## [0.2.0] - 2026-07-23

### Changes

* Requires Localize `~> 1.0-rc`

## [0.1.0] - 2026-07-17

Initial release.

### Highlights

* `Localize.Ecto.collate/1,2` query macros applying PostgreSQL ICU `COLLATE` clauses to query expressions and comparisons, resolved from a locale or the current `Localize` locale.

* Locale-to-collation resolution via CLDR language matching, including BCP 47 `-u-co-` collation types and direct collation names.

* `Localize.Ecto.Migration.create_collation/2` and `drop_collation/2` for creating ICU collations reversibly in migrations, and `collated/2` for building collated indexes with `Ecto.Migration.index/3`.

See the [README](https://hexdocs.pm/localize_ecto/readme.html) for full documentation.
