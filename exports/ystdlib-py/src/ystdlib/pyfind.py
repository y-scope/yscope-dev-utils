"""See help fields inside _main or run the script with `--help` for information."""

from __future__ import annotations

import argparse
import logging
import sys
from fnmatch import fnmatchcase
from pathlib import Path

logger = logging.getLogger(__name__)


def find(
    root_paths: list[str],
    include_patterns: list[str] | None = None,
    exclude_patterns: list[str] | None = None,
    filename_patterns: list[str] | None = None,
) -> set[Path]:
    """
    Recursively searches for paths matching the given predicates, starting from each path in
    `root_paths`. A path is only returned if:

    1. the path is matched by at least one `include` pattern.
    2. the path is not matched by any `exclude` patterns.
    3. the path's filename is matched by at least one `filename` pattern.

    :param root_paths: Paths to start the search from. If pointing to a file, filtering is applied
    directly.
    :param include_patterns: pathlib patterns to include paths. `None` or an empty list indicates
    all paths should be included.
    :param exclude_patterns: pathlib patterns to exclude paths. `None` or an empty list indicates no
    paths should be excluded.
    :param filename_patterns: fnmatch patterns to include filenames. `None` or an empty list
    indicates all filenames should be included.
    :return: Matched paths.
    """
    _validate_patterns_are_relative(include_patterns)
    _validate_patterns_are_relative(exclude_patterns)
    if not include_patterns:
        include_patterns = ["**/*"]

    results: set[Path] = set()
    for root in root_paths:
        root_path = Path(root)
        if not root_path.exists():
            raise FileNotFoundError(root_path)

        for include_pattern in include_patterns:
            for path in root_path.glob(include_pattern):
                if not exclude_patterns or not any(
                    path.full_match(root_path / p) for p in exclude_patterns
                ):
                    if not filename_patterns or any(
                        fnmatchcase(path.name, p) for p in filename_patterns
                    ):
                        results.add(path)

    return results


def _validate_patterns_are_relative(patterns: list[str] | None) -> None:
    if patterns:
        for p in patterns:
            if Path(p).is_absolute():
                msg = f"Non-relative patterns are unsupported: {p}"
                raise NotImplementedError(msg)


def _main() -> int:
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Recursively search and print file paths similar to the `find` utility.\n\n"
            "Paths are searched recursively starting from each path in `root_paths`. A path is"
            " printed only if:\n\n"
            "1. the path is matched by at least one `include` pattern.\n"
            "2. the path is not matched by any `exclude` patterns.\n"
            "3. the path's filename is matched by at least one `filename` pattern.\n\n"
            "Path patterns are matched against the entire path, and filename patterns are matched"
            " against the entire name (the directory path is ignored). All pattern matching is case"
            " sensitive. For:\n\n"
            "* include/exclude pattern syntax, see"
            " https://docs.python.org/3.13/library/pathlib.html#pathlib-pattern-language\n"
            "* filename pattern syntax, see https://docs.python.org/3.13/library/fnmatch.html\n"
        ),
    )
    parser.add_argument(
        "root_paths",
        nargs="*",
        default=["."],
        help=(
            "Paths to start the search from. If a 'root_path' points to a file, filtering is"
            " applied directly. (default: Current directory)"
        ),
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        help=(
            "Wildcard patterns where any matching file paths (relative to `root_paths`) will be"
            " included. (default: All paths included)"
        ),
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help=(
            "Wildcard patterns where any matching paths (relative to `root_paths`) will be"
            " excluded. (default: No paths excluded)"
        ),
    )
    parser.add_argument(
        "--filename",
        action="append",
        default=[],
        help=(
            "Wildcard patterns where only files whose name (not the full path) matches a pattern "
            " will be included. This is useful for specifying the extensions of files (e.g."
            " '*.py'). (default: All filenames included)"
        ),
    )
    args = parser.parse_args()

    results = find(args.root_paths, args.include, args.exclude, args.filename)
    for result in results:
        sys.stdout.write(f"{result}\n")

    return 0


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s.%(msecs)03d %(levelname)s [%(module)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    sys.exit(_main())
