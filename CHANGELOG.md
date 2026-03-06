# Changelog

All notable changes to this project will be documented in this file.

## [0.1.2] - 2026-03-04

### Added

- Azure-first release documentation (`README.md`, demo and troubleshooting docs)
- CI secret scanning via gitleaks
- Public repository metadata: `SECURITY.md`, issue/PR templates, contributing docs
- Open source licensing (`MIT`)

### Changed

- CI streamlined to fast checks: secret scan, backend lint/tests, frontend lint/build
- Repository hygiene updates for public release

### Removed

- Local secret file `.env`
- Generated output artifacts under `infra/out/`
- Python cache artifacts and duplicate noise files
