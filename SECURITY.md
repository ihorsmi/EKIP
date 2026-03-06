# Security Policy

## Supported Versions

The project is in active hackathon-release hardening. Report issues against the latest main branch.

## Reporting a Vulnerability

Please do not open public issues for suspected vulnerabilities.

Report privately with:

- affected component/path
- impact summary
- reproduction steps
- suggested remediation (if available)

Temporary contact channel until dedicated security inbox is set:

- Open a private security advisory in GitHub Security tab for this repository.

## Secrets Policy

- Never commit credentials, API keys, tokens, connection strings, or private keys.
- Use Azure Key Vault and Managed Identity for cloud secret access.
- CI includes automated secret scanning (gitleaks) on push and pull request.

## Disclosure and Remediation

- We will acknowledge reports and triage severity.
- Fixes will be prioritized for high-impact issues affecting auth, data exposure, or secret handling.
