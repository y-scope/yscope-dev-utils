# ystdlib-py

Python utilities developed and used at YScope.

## Usage

### pyfind

Display detailed information for the command:

```shell
uv run pyfind --help
```

Example: *List all Python files exported from yscope-dev-utils, excluding anything from a virtual
environment.*

```shell
uv run pyfind yscope-dev-utils --include "**/exports/**" --exclude "**/.venv/**" --filename "*.py"
```

Source location: [`src/ystdlib/pyfind.py`](src/ystdlib/pyfind.py)

## Contributing

Before you submit a pull request, ensure you follow the testing and linting instructions below.

### Requirements

* [Task] 3.40 or higher
* [uv] 0.7.10 or higher

### Set up

To install all Python dependencies run:

```shell
uv sync
```

### Testing

Testing is run through the yscope-dev-utils taskfile. To run all tests:

```shell
task tests:ystdlib-py
```

To run a subset of tests, list all tests:

```shell
task -a
```

Then look for all tasks under the `tests` namespace (identified by the `tests:` prefix).

### Linting

Before submitting a pull request, ensure you've run the linting commands below and have fixed all
violations and suppressed all warnings.

Linting is run through the yscope-dev-utils taskfile. To run all linting checks:

```shell
task lint:check
```

To run all linting checks AND fix some violations:

```shell
task lint:fix
```

To run a subset of linters for a specific file type, list all tasks:

```shell
task -a
```

Then look for all tasks under the `lint` namespace (identified by the `lint:` prefix).

[Task]: https://taskfile.dev
[uv]: https://docs.astral.sh/uv
