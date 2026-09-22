# M15 fault-set ground truth

Verified against the actual artifacts on 2026-09-22 — not inferred from filenames or CVE ids. See
`PROVENANCE.md` for the pinned scanner versions and the live finding counts.

The lesson these four findings teach: **rank on reachability × exposure × blast radius, never on
CVSS alone.** A CVSS 9.8 and a CVSS 6.1 sit next to each other below; the 6.1 outranks the 9.8.

## 1. CVE-2020-14343 — PyYAML 5.3.1 — CRITICAL (CVSS 9.8) — the noise

- **Where:** `platform/secfixtures/vulnerable-service/requirements.txt`
- **Reachable:** **no.** `grep -rn "import yaml\|yaml\." platform/secfixtures/vulnerable-service`
  returns zero matches — no file in the service imports or calls the `yaml` module. PyYAML is a pinned
  dependency that nothing in this codebase touches.
- **Exposure:** n/a — dead weight, not on any code path.
- **Compensating control:** none needed; there is no path to trigger the deserialization.
- **Correct rank:** **last.** Highest CVSS in the set, lowest priority.
- **The trap it punishes:** ranking by CVSS alone. An agent (or a person) that reads the trivy table
  top-to-bottom puts this first and burns the review budget on a dependency nothing calls.

## 2. CVE-2023-32681 — requests 2.19.1 — MEDIUM (CVSS 6.1) — the real one

- **Where:** `platform/secfixtures/vulnerable-service/app.py`
- **Reachable:** **yes.** `grep -n "import requests\|requests\." platform/secfixtures/vulnerable-service/app.py`
  → line 8 `import requests`, line 17 `resp = requests.get(url, timeout=5)`, inside
  `fetch_vendor_feed`, the handler for the public route `GET /proxy/vendor-feed`.
- **Exposure:** **internet-facing.** The route takes a storefront-supplied `url` and the service
  fetches it server-side — the CVE (Proxy-Authorization header leak on cross-host redirect) is
  directly reachable from an untrusted caller.
- **Compensating control:** none present in this fixture — no allow-list on `url`, no proxy egress
  restriction.
- **Correct rank:** **first.** Lower CVSS than finding #1, but reachable and internet-facing.
- **The trap it punishes:** burying the finding that actually matters under lower-severity noise
  because it never got a `reachable: yes` verdict.

## 3. Committed credential — `fixtures/seed-data/prod-secrets.env`

- **Where:** `fixtures/seed-data/prod-secrets.env` (AWS key, DB password, GitHub token). Also present
  in `fixtures/seed-data/sensitive-customer.json`, `scripts/ledger-export.sh` and
  `platform/troublesim/demo-secret.yaml` — `gitleaks detect --source .` found 7 leaks total on
  2026-09-22, several of them reachable **only through git history** (e.g. `scripts/ledger-export.sh`,
  commit `942fccfa`), not the working tree.
- **Reachable:** not the right question for a secret — a scanner can say the string exists in the
  repo, it cannot say whether the key is still **live**. That requires checking rotation history
  against the credential issuer, which no static scanner does.
- **Exposure:** repo-wide; anyone with clone access has had it since the commit that introduced it.
- **Compensating control:** **none that a scanner can verify.** The sharper point for the lesson:
  deleting the file does **not** rotate the key — gitleaks still finds it in history after a later
  commit removes it from HEAD.
- **Correct rank:** high, but the verdict must be phrased as a question the team must answer
  (rotate/confirm-rotated), not a fact the scan proves.
- **The trap it punishes:** treating "gitleaks found it" and "the credential is compromised" as the
  same claim. They are not — rotation status is the missing fact, and only a human process supplies it.

## 4. `allow-all-ingress` + Secret-readable RBAC — a correlation finding

- **Where:** `platform/policies/network-policies.yaml` (NetworkPolicy `allow-all-ingress`, empty
  ingress rule — `scripts/secops-surface-scan.sh --field wide_open_ingress` reports it) **correlated
  with** `platform/rbac/agent-readonly.yaml` (ClusterRole `northstar-agent-readonly` grants
  `get/list/watch` on `resources: ["*"]` in the core API group, which includes `Secrets` — verbatim
  in the manifest, not flagged by `secops-surface-scan.sh`'s `cluster_admin`/`broad_iam` patterns
  because the role name and rule shape don't match either signature).
- **Reachable:** not a code-reachability question — a posture-correlation one. Neither manifest is a
  finding alone: an open NetworkPolicy without a Secret-readable identity behind it is low value to an
  attacker; a Secret-readable RBAC grant that nothing on the network can reach is also low value. The
  finding **is** the correlation.
- **Exposure:** any workload in the `northstar` namespace can be reached from anywhere (no ingress
  restriction) and any identity bound to `agent-readonly` can `get`/`list` every Secret in the
  namespace via `resources: ["*"]`.
- **Compensating control:** none — this is the one shape in the set where no single tool's output
  says "block"; only reading both manifests together does.
- **Correct rank:** high — the two together describe a real path from "reachable over the network" to
  "can read every Secret in the namespace."
- **The trap it punishes:** treating each scanner's report as the whole picture. `secops-surface-scan`
  alone flags the NetworkPolicy but says nothing about what an attacker gains from it; the RBAC
  manifest alone looks like ordinary read access. Only correlating the two tools' outputs shows the
  real finding.
