# yscope-dev-utils

This repo contains configs, scripts, and tools that are reusable across all our repos.

## Usage

To use the repo's artifacts in your project:

1. Add `yscope-dev-utils` as a submodule in your project:
   ```shell
   git submodule add https://github.com/y-scope/yscope-dev-utils.git tools/yscope-dev-utils
   ```
2. Add a setup step (to the project's setup script or docs) to check out the submodule:
   ```shell
   git submodule update --init --recursive tools/yscope-dev-utils
   ```
3. Use the artifacts as needed.

For language/tool-specific guides, see:

* [Linting for C++ projects](lint-tools-cpp.md)
