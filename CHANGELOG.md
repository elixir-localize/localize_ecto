# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-17

Initial release.

### Highlights

* `Localize.Ecto.collate/1,2` query macros applying PostgreSQL ICU `COLLATE` clauses to query expressions and comparisons, resolved from a locale or the current `Localize` locale.

* Locale-to-collation resolution via CLDR language matching, including BCP 47 `-u-co-` collation types and direct collation names.

* `Localize.Ecto.Migration.create_collation/2` and `drop_collation/2` for creating ICU collations reversibly in migrations.

See the [README](https://hexdocs.pm/localize_ecto/readme.html) for full documentation.
