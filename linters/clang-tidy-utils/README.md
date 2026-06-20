# clang-tidy-utils

`clang-tidy-utils` is a command-line tool for running [clang-tidy][clang-tidy-home] checks efficiently.

## Requirements
- [uv] (for package and environment management)

## Installation

### Virtual environment installation (Recommended)

For installation within a virtual environment:
```shell
uv venv
uv pip install .
```

### System-wide installation

To install the tool globally:
```shell
uv tool install .
```

## Usage

Run the tool using:
```shell
uv run clang-tidy-utils [-h] [-j NUM_JOBS] FILE [FILE ...] [-- CLANG-TIDY-ARGS ...]
```
- By default, the number of jobs (`-j`) is set to the number of available CPU cores.
- Arguments after `--` are directly passed to `clang-tidy`.

## Development:
To format and lint the code, run:
```shell
uv tool run mypy src
uv tool run docformatter -i src
uv tool run black src
uv tool run ruff check --fix src
```

[clang-tidy-home]: https://clang.llvm.org/extra/clang-tidy/
[uv]: https://docs.astral.sh/uv/getting-started/installation/
