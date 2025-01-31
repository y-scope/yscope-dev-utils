# yscope-clang-tidy-utils

This project contains CLI scripts for running [clang-tidy][clang-tidy-home] checks.

## Requirements
- [uv]

## Installation
To install the tool permanently:
```shell
uv tool install .
```

Using virtual environment:
```shell
uv venv
uv pip install .
```

## Usage
```shell
yscope-clang-tidy-utils [-h] [-j NUM_JOBS] FILE [FILE ...] [-- CLANG-TIDY-ARGS ...]
```
Note:
- By default, the number of jobs will be set to the number of cores in the running environment.
- Anything after `--` will be considered as clang-tidy arguments and will be directly passed into
  clang-tidy.

## Development:
```shell
uv tool run mypy src
uv tool run docformatter -i src
uv tool run black src
uv tool run ruff check --fix src
```

[clang-tidy-home]: https://clang.llvm.org/extra/clang-tidy/
[uv]: https://docs.astral.sh/uv/getting-started/installation/