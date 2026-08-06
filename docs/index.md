# nimorm documentation

nimorm turns a compact model declaration into native Nim objects, typed queries,
schema metadata, and synchronous SQLite or PostgreSQL persistence.

## New to nimorm?

Follow these pages in order:

1. [Installation](installation.md), 2 minutes
2. [5-minute quickstart](quickstart.md), one model and one query
3. [Build a small blog](tutorial.md), validation, relations, and updates

Every tutorial program lives in `examples/` and is compiled by
`nimble example`. The documentation is not asking you to trust a stale snippet.

## Guides

- [Models and metadata](models.md)
- [Fields and validation](fields.md)
- [CRUD and typed queries](queries.md)
- [Relations](relations.md)
- [Schema snapshots and migrations](migrations.md)
- [SQLite and PostgreSQL](backends.md)
- [Cookbook](cookbook.md)

## Reference and project notes

- [Public API reference](api-reference.md)
- [Migration CLI reference](cli-reference.md)
- [Troubleshooting](troubleshooting.md)
- [FAQ](faq.md)
- [Architecture and design](design.md)
- [Benchmark method and results](../benchmarks/README.md)
- [Changelog](../CHANGELOG.md)
- [Roadmap](../ROADMAP.md)
- [Contributing](../CONTRIBUTING.md)
- [Security policy](../SECURITY.md)

The public API is synchronous. Version `0.1.0` does not include eager loading,
arbitrary projection, relation traversal inside filters, async execution, or
automatic SQLite table rebuilds. Those boundaries are documented so you can
decide whether nimorm fits before adopting it.
