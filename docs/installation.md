# Installation

## Requirements

- Nim 2.0 or newer
- Nimble
- a C compiler supported by Nim
- SQLite through the `db_connector` package

The repository is currently verified with Nim 2.2.4 on Windows. SQLite support
is included in the default build. PostgreSQL is optional and has separate
[runtime requirements](backends.md#postgresql).

Check your toolchain:

```shell
nim --version
nimble --version
```

## Install from GitHub

Until a tagged release is published in the Nimble package directory, install
directly from the public repository:

```shell
nimble install https://github.com/hakunamta00700/mahaorm.git
```

For library development, clone the repository and register the checkout:

```shell
git clone https://github.com/hakunamta00700/mahaorm.git
cd mahaorm
nimble install -d
nimble develop
nimble test
```

After the package is listed in Nimble, consumers will be able to use:

```shell
nimble install nimorm
```

Do not add `requires "nimorm"` to a public package until that registry release
exists. During source-based development, `nimble develop` provides the local
package mapping.

## Verify the installation

Create `hello_nimorm.nim`:

```nim
import nimorm

model Message:
  text = stringField(maxLength = 200)

echo tableName(Message)
```

Then compile it:

```shell
nim c -r hello_nimorm.nim
```

It should print `message`. Continue with the
[5-minute quickstart](quickstart.md).
