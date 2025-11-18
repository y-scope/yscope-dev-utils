# Python linter configs

This directory contains standalone, working Python linter configuration files that serve as
reference settings for integrating these linters into your project.

## Integration Methods

### Ruff

Ruff supports the `extend` directive. Add this to your `pyproject.toml`:

```toml
[tool.ruff]
extend = "path/to/yscope-dev-utils/exports/lint-configs/python/ruff.toml"
```

See [ystdlib-py/pyproject.toml](../../ystdlib-py/pyproject.toml) for an example.

### Mypy

Mypy does not support extending external configuration files. Copy the settings from `mypy.ini`
into your `pyproject.toml` under `[tool.mypy]`.
