#!/usr/bin/env bash

# Exit on any error
set -e

# Error on undefined variable
set -u

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Symlinks the given config file to the repo's root.
#
# @param $1 Path to the config file in the repo.
function symlink_config () {
    config_file_path="$1"

    repo_dir="$(git rev-parse --show-toplevel)"
    repo_relative_config_file_path="$(realpath --relative-to="$repo_dir" "$config_file_path")"

    src_path="${repo_dir}/${repo_relative_config_file_path}"
    dst_path="${repo_dir}/$(basename "$config_file_path")"

    # NOTE: `-e` will return false if the file is a broken symlink, so that's why we also check
    # `-L`.
    if [ ! -e "$dst_path" ] && [ ! -L "$dst_path" ]; then
        ln -s "$repo_relative_config_file_path" "$dst_path"
        echo "Symlinked '${src_path}' to '${dst_path}'."
    elif [ "$(readlink -f "$src_path")" != "$(readlink -f "$dst_path")" ]; then
        echo "Unknown config file exists at '${dst_path}'. Remove it before running this script."
    else
        echo "Already symlinked '${src_path}' to '${dst_path}'."
    fi
}

symlink_config "${script_dir}/.clang-format"
symlink_config "${script_dir}/.clang-tidy"
