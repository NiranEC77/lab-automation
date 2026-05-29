# Changelog

## [Unreleased] - 2026-05-28

### Added
- `configure-supervisor.ps1` — sets supervisor control plane size (default `MEDIUM`) using VMware.Sdk.vSphere 13.5.0 SDK; skips if already at target size; polls `ConfigStatus` every 15s (up to 20 min) until `RUNNING` before returning
- `supervisor-services/services.yaml` — YAML manifest defining which supervisor services to install; supports `enabled: true/false` toggle and `exclude_envs` list per service; replaces hardcoded arrays in `setup-lab.sh`
- `python3-yaml` prereq install check added to `setup-lab.sh`

### Changed
- `install-supervisor-services.ps1` — supervisor service create retry pattern broadened to catch transient `500 Internal Server Error` / `internal_server_error` responses in addition to `package not found`; retry count increased 6 → 10, delay increased 20s → 30s
- `setup-lab.sh` — `secret-store-service-config.yaml` now generated at runtime using the environment's `$STORAGE_CLASS` variable instead of being hardcoded to the `adv` env value
- `setup-lab.sh` — supervisor service list now parsed from `services.yaml` via Python inline heredoc; `configure-supervisor.ps1` called before service install loop
- `install-supervisor-services.ps1` — precheck timeout extended 300s → 600s; poll interval reduced 15s → 5s
- `README.md` — updated Supervisor Service Installation section and Files table

### Removed
- `supervisor-services/services.conf` — replaced by `services.yaml`
- Hardcoded `supervisor-management-proxy` exclusion logic in `setup-lab.sh` — now handled via `exclude_envs: [ss]` in `services.yaml`
