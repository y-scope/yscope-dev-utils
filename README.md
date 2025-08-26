# Contributing

Before you submit a pull request, ensure you follow the testing and linting instructions below.

> [!NOTE]
> We use [Task] to automate our development workflow. You can use `task --list-all` to see all
> available tasks.

## Requirements

* Python 3.10 or higher
* [Task] 3.40 or higher
* [uv] 0.7.10 or higher

### macOS

The exported tasks use GNU utilities that are not always pre-installed on macOS. You may need to
install the following brew packages and add their executables to your PATH:

* [coreutils]\: `md5sum`
* [gnu-tar]\: `gtar`

## Testing

To run all tests:

```bash
task test
```

You can also run specific unit tests with `task tests:<test>`, where `<test>` is the name of the
test you want to run.

## Linting

To run all linting checks:

```bash
task lint:check
```

You can also run specific linting checks with `task lint:<check>`, where `<check>` is the name of
check you want to run.

## Cleaning

To clean up any generated files:

```bash
task clean
```

[coreutils]: https://formulae.brew.sh/formula/coreutils
[gnu-tar]: https://formulae.brew.sh/formula/gnu-tar
[Task]: https://taskfile.dev/
[uv]: https://docs.astral.sh/uv
