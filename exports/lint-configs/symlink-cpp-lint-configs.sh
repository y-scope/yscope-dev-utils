#!/usr/bin/env bash

# Exit on any error
set -e

# Error on undefined variable
set -u

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

main () {
    "${script_dir}/symlink-config.sh" "${script_dir}/.clang-format"
    "${script_dir}/symlink-config.sh" "${script_dir}/.clang-tidy"
}

main "$@"
