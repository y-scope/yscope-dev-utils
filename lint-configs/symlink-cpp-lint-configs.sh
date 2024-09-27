#!/usr/bin/env bash

# Exit on any error
set -e

# Error on undefined variable
set -u

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Symlinks the given config file to the repo's root.
#
# @param $1 Path to the config file in the repo.
symlink_config () {
    if [ "$#" -ne 1 ]; then
        echo "Usage: symlink_config <config-file-path>" >&2
        return 1
    fi

    config_file_path="$1"
    if [ ! -f "$config_file_path" ]; then
        echo "symlink_config: Config file doesn't exist: '$config_file_path'." >&2
        return 1
    fi

    repo_dir="$(git rev-parse --show-toplevel)"
    config_file_absolute_path="$(readlink -f "$config_file_path")"

    # Ensure $repo_dir has a single trailing slash
    repo_dir="${repo_dir%/}/"

    # Get the config file's path relative to the repo root
    # NOTE: This is a bit fragile since it depends on $repo_dir having a single trailing slash.
    # Ideally, we would use `realpath --relative-to` instead of variable substitution, but
    # `--relative-to` isn't available on macOS.
    repo_relative_config_file_path="${config_file_absolute_path#"${repo_dir}"}"

    src_path="${repo_dir}/${repo_relative_config_file_path}"
    dst_path="${repo_dir}/$(basename "$config_file_path")"

    # NOTE: `-e` will return false if the file is a broken symlink, so that's why we also check
    # `-L`.
    if [ ! -e "$dst_path" ] && [ ! -L "$dst_path" ]; then
        ln -s "$repo_relative_config_file_path" "$dst_path"
        echo "Symlinked '${src_path}' to '${dst_path}'."
    elif [ "$(readlink -f "$src_path")" != "$(readlink -f "$dst_path")" ]; then
        echo "Unknown config file exists at '${dst_path}'. Remove it before running this script." \
            >&2
        return 1
    else
        echo "Already symlinked '${src_path}' to '${dst_path}'."
    fi

    return 0
}

main () {
    if ! symlink_config "${script_dir}/.clang-format"; then
        exit 1
    fi
    if ! symlink_config "${script_dir}/.clang-tidy"; then
        exit 1
    fi
}

main "$@"
