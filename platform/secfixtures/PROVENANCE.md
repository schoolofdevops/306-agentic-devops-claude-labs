Scanners pinned for the M15 fault set — reproduce with these exact versions.

- trivy 0.72.0 (`/opt/homebrew/bin/trivy`)
- gitleaks 8.30.1 (`/opt/homebrew/bin/gitleaks`)

CVE data is a moving target (the trivy vulnerability DB updates daily), so `labs/m15/checks.json`
must never assert a CVE id or a finding count — only that the learner's ranked list and verdict exist
and are internally consistent with `ground-truth.md`.

Last live-verified: 2026-09-22, against `platform/secfixtures/vulnerable-service/requirements.txt`
(`requests==2.19.1`, `PyYAML==5.3.1`, `urllib3==1.25.8`):

```
$ trivy fs --scanners vuln --severity CRITICAL,HIGH,MEDIUM platform/secfixtures/vulnerable-service
1 CRITICAL, 7 HIGH, 8 MEDIUM  (16 findings total)
```

Named findings this fault set depends on (all present in the 2026-09-22 run):

| CVE | Package | Severity |
|---|---|---|
| CVE-2020-14343 | PyYAML 5.3.1 | CRITICAL |
| CVE-2018-18074 | requests 2.19.1 | HIGH |
| CVE-2023-32681 | requests 2.19.1 | MEDIUM |
| CVE-2021-33503 | urllib3 1.25.8 | HIGH |

`gitleaks detect --source .` on the repo (working tree + history) found **7** leaks on 2026-09-22,
including `fixtures/seed-data/prod-secrets.env`, `fixtures/seed-data/sensitive-customer.json`,
`scripts/ledger-export.sh`, and `platform/troublesim/demo-secret.yaml`.

Vendored: 2026-09-22.
