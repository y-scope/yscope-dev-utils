#!/usr/bin/env python3

"""See help fields inside _main or run `find.py --help` for information."""

from __future__ import annotations

import argparse
import sys
from fnmatch import fnmatchcase
from pathlib import Path


def find(
    root_paths: list[str],
    include_patterns: list[str] | None = None,
    exclude_patterns: list[str] | None = None,
    filename_patterns: list[str] | None = None,
) -> set[Path]:
    """
    Recursively search paths starting from each path in `root_paths`. A path is only retunred if:
    1. the path is matched by at least one `include` pattern.
    2. the path is not matched by any `exclude` patterns.
    3. the path's filename is matched by at least one `filename` pattern.

    :param root_paths: Paths to recursively search from.
    :param include_patterns: pathlib patterns to include paths. Default: All paths included
    :param exclude_patterns: pathlib patterns to exclude paths. Default: No paths excluded
    :param filename_patterns: fnmatch patterns to include filenames. Default: All filenames included
    :return: Matched paths.
    """
    results: set[Path] = set()
    if not include_patterns:
        include_patterns = ["**/*"]

    for root in root_paths:
        root_path = Path(root)
        if not root_path.exists():
            raise FileNotFoundError(root_path)

        for include_pattern in include_patterns:
            for path in root_path.glob(include_pattern):
                if not exclude_patterns or not any(
                    path.full_match(exlcude_pattern) for exlcude_pattern in exclude_patterns
                ):
                    if not filename_patterns or any(
                        fnmatchcase(path.name, pattern) for pattern in filename_patterns
                    ):
                        results.add(path)

    return results


def _main() -> int:
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Recursively search and print file paths similar to the `find` utility.\n\n"
            "Paths are searched recursively starting from each path in `root_paths`. A path is"
            " printed only if:\n\n"
            "  1. the path is matched by at least one `include` pattern.\n"
            "  2. the path is not matched by any `exclude` patterns.\n"
            "  3. the path's filename is matched by at least one `filename` pattern.\n\n"
            "Path patterns are matched against the entire path, and filename patterns are matched"
            " against the entire name (the directory path is ignored). All pattern matching is case"
            " sensitive.\n\n"
            "https://docs.python.org/3.13/library/pathlib.html#pathlib-pattern-language"
        ),
    )
    parser.add_argument(
        "root_paths",
        nargs="*",
        default=["."],
        help=(
            "Paths to start the search from. If a path is to a file there is no searching to "
            "perform and filtering is applied directly. (default: Current directory)"
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
    sys.exit(_main())
