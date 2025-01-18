# yscope-clang-tidy-utils

This project contains CLI scripts for running [clang-tidy][clang-tidy-home] checks.

## Installation
```shell
python3 -m pip install .
```
Note:
- Python 3.10 or higher is required.
- It is highly suggested to install in a virtual environment.

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
pip install -e .[dev]
mypy src
docformatter -i src
black src
ruff check --fix src
```

[clang-tidy-home]: https://clang.llvm.org/extra/clang-tidy/