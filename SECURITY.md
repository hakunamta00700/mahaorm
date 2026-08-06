# Security policy

## Supported versions

Until the first tagged release, security fixes target the latest commit on the
default development branch. Old commits and untagged snapshots are not
maintained as separate support lines.

## Report a vulnerability

Do not open a public issue with exploit details, credentials, connection
strings, or production data.

Visit the repository's
[Security page](https://github.com/hakunamta00700/mahaorm/security). If GitHub
offers a private vulnerability-reporting form, use it. If no private form is
available, open a minimal issue asking the maintainers to establish private
contact, without describing the vulnerability.

Include privately:

- affected commit or version;
- backend and platform;
- minimal reproduction;
- impact and prerequisites;
- suggested mitigation, if known.

Maintainers should acknowledge a private report before discussing disclosure
timing. No response-time guarantee is offered before a stable release.

## Security boundaries

- ORM-generated CRUD and query values use bound parameters.
- Raw SQL and `dbDefault` accept trusted source text. Callers must never
  concatenate untrusted input into them.
- Query-log redaction covers common sensitive field names, not every possible
  business secret. Production loggers should avoid recording parameter values.
- Database credentials are owned by the application and should come from its
  secret-management system, not source code.
- Migration safety flags are confirmation gates, not backups or automatic data
  conversion.

See [backend security notes](docs/backends.md#parameters-logging-and-errors) and
[troubleshooting](docs/troubleshooting.md#query-logging-still-contains-application-values).
