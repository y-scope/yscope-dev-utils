# Contributing

Before you submit a pull request, ensure you follow the testing and linting instructions below.

> [!NOTE]
> We use [Task] to automate our development workflow. You can use `task --list-all` to see all
> available tasks.

## Requirements

* Python 3.10 or higher
* [Task] 3.38 or higher

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

You can also run specific unit tests with `task tests:*`

A list of available tasks can be found with `task --list-all`
