# Gigafactory Actions

Reusable GitHub Actions for projects managed by [Gigafactory](https://giga.endira.ai).

## Actions

| Action | Description |
|--------|-------------|
| `convention-validator` | Validate project conventions (manifest, file size, secrets, commit messages) |
| `security-scan` | Dependency audit and secret scanning |
| `setup-stack` | Set up language runtime (Go, Node, Python) and install dependencies |
| `lint` | Stack-aware linting (golangci-lint, eslint, ruff) |
| `typecheck` | Stack-aware type checking (go vet, tsc, mypy) |
| `test` | Stack-aware test runner with optional coverage enforcement |
| `deploy` | Strategy-dispatching deploy (VM, GKE, Cloudflare Pages, Docker Compose) |

## Usage

Referenced by the [managed project pipeline](https://github.com/gigafacty/gigafactory) via `.gigafactory/project.yaml` config:

```yaml
- uses: gigafacty/gigafactory-actions/convention-validator@main
  with:
    project_config: .gigafactory/project.yaml
```

## License

Proprietary. For use with Gigafactory-managed projects only.
