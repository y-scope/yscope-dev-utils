#!/usr/bin/env python3

"""See help fields inside _main or run `find.py --help` for information."""

from __future__ import annotations

import argparse
import logging
import sys
from fnmatch import fnmatchcase
from pathlib import Path

logger = logging.getLogger(__name__)


def _glob_paths(root_path: Path, patterns: list[str]) -> set[Path]:
    paths: set[Path] = set()
    for pattern in patterns:
        for path in root_path.glob(pattern):
            paths.add(path)
    return paths


def _find(
    root_paths: list[str],
    include_patterns: list[str],
    exclude_patterns: list[str],
    filename_patterns: list[str],
) -> bool:
    for root in root_paths:
        root_path = Path(root)
        if not root_path.exists():
            logger.error("[error] Path does not exist: '%s'", root_path)
            return False

        included_paths: set[Path] = _glob_paths(root_path, include_patterns)
        excluded_paths: set[Path] = _glob_paths(root_path, exclude_patterns)

        for path in included_paths - excluded_paths:
            if not filename_patterns or any(fnmatchcase(path.name, p) for p in filename_patterns):
                sys.stdout.write(f"{path}\n")
    return True


def _main() -> bool:
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Recursively search and print file paths similar to the `find` utility.\n\n"
            "Paths are searched recursively starting from each path in `root_paths`. A path is"
            " printed only if:\n\n"
            "  1. the path is matched by at least one `include` pattern.\n"
            "  2. the path is not matched by any `exclude` patterns.\n"
            "  3. the path's file name is matched by at least one `filename` pattern.\n\n"
            "Path patterns are matched against the entire path, and file name patterns are matched"
            " against the entire name (the directory path is ignored). All pattern matching is case"
            " sensitive.\n\n"
            "NOTE: The pattern `**` will only match files starting from Python 3.13."
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
        default=["**/*"],
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
            " '*.py'). (default: All file names match)"
        ),
    )

    args = parser.parse_args()

    # If the user specified an include, remove the default value from the list (argparse will keep
    # default values in the list when using action="append").
    if len(args.include) > 1:
        args.include.pop(0)
    return _find(args.root_paths, args.include, args.exclude, args.filename)


if __name__ == "__main__":
    sys.exit(0 if _main() else 1)
