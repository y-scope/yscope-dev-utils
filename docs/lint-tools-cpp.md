# Linting for C++ projects

We use `clang-format` for formatting and `clang-tidy` for code analysis.

## General usage

C++ projects should use the [.clang-format] and [.clang-tidy] config files as follows (assuming
`yscope-dev-utils` was added to the project at `tools/yscope-dev-utils`):

1. Add a setup step to symlink the files to the project root.
   * You can use [symlink-cpp-lint-configs.sh].
2. Create project-specific config files to override any settings as necessary (see below).
3. Run `clang-format` and `clang-tidy` using the config files.

## Creating project-specific config files

* Create a `.clang-format` or `.clang-tidy` file in the project subdirectory (e.g. `src`) where the
  settings are necessary.
* In each config file, set the relevant option (see the tool-specific sections below) to inherit
  from the config file in the parent directory.

### clang-format

In the project-specific config file:

* Set `BasedOnStyle: InheritParentConfig` to inherit from the config file at the project's root.
* Set `IncludeCategories` as necessary.

For example:

```yaml
BasedOnStyle: InheritParentConfig

IncludeCategories:
  # NOTE: A header is grouped by first matching regex
  # Library headers. Update when adding new libraries.
  # NOTE: clang-format retains leading white-space on a line in violation of the YAML spec.
  - Regex: "<(absl|antlr4|archive|boost|bsoncxx|catch2|curl|date|fmt|json|log_surgeon|mariadb\
|mongocxx|msgpack|openssl|outcome|regex_utils|simdjson|spdlog|sqlite3|string_utils|yaml-cpp|zstd)"
    Priority: 3
  # C system headers
  - Regex: "^<.+\\.h>"
    Priority: 1
  # C++ standard libraries
  - Regex: "^<.+>"
    Priority: 2
  # Project headers
  - Regex: "^\".+\""
    Priority: 4
```

### clang-tidy

In the project-specific config file:

* Set `InheritParentConfig: true` to inherit from the config file at the project's root.
* Update, add, or disable checks as necessary.
  * For any disabled or added checks, add a comment explaining why.

For example:

```yaml
InheritParentConfig: true

# Disabled checks:
# - `cppcoreguidelines-avoid-non-const-global-variables` because ...
Checks: >-
  -cppcoreguidelines-avoid-non-const-global-variables,
```

[.clang-format]: ../exports/lint-configs/.clang-format
[.clang-tidy]: ../exports/lint-configs/.clang-tidy
[symlink-cpp-lint-configs.sh]: ../exports/lint-configs/symlink-cpp-lint-configs.sh
