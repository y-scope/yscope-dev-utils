# Python linter configs

This directory contains standalone, working Python linter configuration files that serve as
reference settings for integrating these linters into your project.

For a project with its own `pyproject.toml` file, at the time of writing, there is no clean, general
solution for including the standalone configuration files for different linters. In this scenario,
the settings inside the configuration files should be copied into your `pyproject.toml` file, as
seen in [ystdlib-py/pyproject.toml](../../ystdlib-py/pyproject.toml).
