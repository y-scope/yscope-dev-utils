# Python linter configs

This directory contains standalone Python linter configuration files that double as a source of
reference settings for using the linters in your project.

For a project with its own `pyproject.toml` file, at the time of writing there is not a clean
general solution to include the standalone configuration files for different linters. In this
scenario, the settings inside the configuration files should be copied into your `pyproject.toml`
file, as seen in [ystdlib-py/pyproject.toml](../../ystdlib-py/pyproject.toml).
