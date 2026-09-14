# Changelog

## [Unreleased] - 2026-05-28

### Added
- `configure-supervisor.ps1` — sets supervisor control plane size (default `MEDIUM`) using VMware.Sdk.vSphere 13.5.0 SDK; skips if already at target size; polls `ConfigStatus` every 15s (up to 20 min) until `RUNNING` before returning
- `supervisor-services/services.yaml` — YAML manifest defining which supervisor services to install; supports `enabled: true/false` toggle and `exclude_envs` list per service; replaces hardcoded arrays in `setup-lab.sh`
- `python3-yaml` prereq install check added to `setup-lab.sh`

### Changed
- `setup-lab.sh` — VKS cluster class in generated `terraform.tfvars` bumped `builtin-generic-v3.6.0` → `builtin-generic-v3.7.0` to match the VKS 3.7 supervisor service being installed
- `setup-lab.sh` — Phase 2 now waits (up to 5 min) for the namespace API to accept VCFA credentials before `terraform apply`, fixing first-run auth failures on 9.1
- `setup-lab.sh` — Phase 2 fallback now retries `terraform apply` up to 5 times with a 60s wait between attempts (covers the provider bug and VCFA / namespace API 500/503s while the cluster builds), and before each attempt (and after the last) reconciles `module.vks.kubernetes_manifest.kubernetes_cluster` with the real cluster — untaints it if tainted, or `terraform import`s it if a wait error left it out of state — so later applies no longer destroy and recreate a healthy cluster
- `configure-supervisor.ps1` — added 9.0.x fallback path using `Invoke-GetClusterNamespaceManagement` / `Invoke-UpdateClusterNamespaceManagement` with `SizeHint` on the update spec; `Wait-ForSupervisorRunning` now accepts either `SupervisorId` (9.1+ summary API) or `ClusterMoRef` (9.0.x cluster info API) for state polling
- `install-supervisor-services.ps1` — supervisor service create retry pattern broadened to catch transient `500 Internal Server Error` / `internal_server_error` responses in addition to `package not found`; retry count increased 6 → 10, delay increased 20s → 30s
- `setup-lab.sh` — `secret-store-service-config.yaml` now generated at runtime using the environment's `$STORAGE_CLASS` variable instead of being hardcoded to the `adv` env value
- `setup-lab.sh` — supervisor service list now parsed from `services.yaml` via Python inline heredoc; `configure-supervisor.ps1` called before service install loop
- `install-supervisor-services.ps1` — precheck timeout extended 300s → 600s; poll interval reduced 15s → 5s
- `README.md` — updated Supervisor Service Installation section and Files table

### Removed
- `supervisor-services/services.conf` — replaced by `services.yaml`
- Hardcoded `supervisor-management-proxy` exclusion logic in `setup-lab.sh` — now handled via `exclude_envs: [ss]` in `services.yaml`
