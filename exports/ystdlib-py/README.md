# ystdlib-py

Python utilities developed and used at YScope.

## Modules

How to get started with the modules inside ystdlib-py.

### find.py

List all Python files exported from yscope-dev-utils, but excluding anything from a virtual env:

```shell
uv run find yscope-dev-utils --include "**/exports/**" --exclude "**/.venv/**" --filename "*.py"
```

Display detailed information for the command:

```shell
uv run find --help
```

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

To see how to run a subset of tests run:

```shell
task -a
```

Look for all tasks under the `tests` namespace (identified by the `tests:` prefix).

### Linting

Before submitting a pull request, ensure you’ve run the linting commands below and have fixed all
violations and suppressed all warnings.

Linting is run through the yscope-dev-utils taskfile. To run all linting checks:

```shell
task lint:check
```

To run all linting checks AND fix some violations:

```shell
task lint:fix
```

To see how to run a subset of linters for a specific file type run:

```shell
task -a
```

Look for all tasks under the `lint` namespace (identified by the `lint:` prefix).

[Task]: https://taskfile.dev
[uv]: https://docs.astral.sh/uv
