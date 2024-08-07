# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and is generated by [Changie](https://github.com/miniscruff/changie).

Please take notes of *Changed*, *Removed* and *Deprecated* items prior
upgrading.

## v0.3.3 - 2024-08-04

### Internal

- Enforces CHANGELOG entries on PRs
- Enforces formatted Crystal code
- Ensure spec passes in CI
- Automate release generation with PR
- Automate release on merge of Release PR

## v0.3.2 - 2024-05-06

### Fixes

- Correctly load `Drift.embed_as` helper
- Solve mismatch between tag/shards.yml

## v0.2.0 - 2024-01-06

### *Breaking change*

- Change migration files and commands from `up` to `migrate` and `down` to `rollback`.

### Fixes

- Properly close database when finishing.
