---
name: helm-style
description: Use when authoring or changing Northstar's Kubernetes desired state (anything under platform/helm/ or platform/policies/) — encodes the house chart conventions, the workload baselines that are not negotiable, the exact Kubernetes vocabulary that prevents the common near-miss errors, and the offline render-test contract. Produces or corrects charts; never writes to a cluster.
---

# helm-style

The house style for Northstar's Helm charts. Read this **before** editing a chart under `platform/helm/`,
and check the rendered output against it before proposing the change.

This skill exists because a chart that renders is not a chart that rolls out. Helm will happily template a
Deployment that lints clean, passes every schema check, and then takes the service down at rollout or is
rejected by the API server at sync time. The defects below are the ones that survive every offline check
unless somebody writes them down.

## Inputs

- `chart` — the chart directory being changed (e.g. `platform/helm/orders-api`).
- `tests` — the chart's own test directory (e.g. `platform/helm/orders-api/tests`), holding `*.test.sh`
  and a `run.sh` runner. Tests render the chart; they never touch a cluster.
- `values` — the value files the chart is rendered with: `values.yaml` (the default the reconciler uses)
  plus any `values-<env>.yaml` overlays.
- `policies` — what the cluster enforces independently of the chart: `platform/policies/pod-security.yaml`,
  `network-policies.yaml`, `resource-quotas.yaml`.
- `application` — the Argo CD Application that points at this chart, under `platform/argocd/applications/`.
  It names the `path`, the `valueFiles` and the destination namespace — the render you verify must be the
  render the reconciler will perform.

## Deterministic zone — collect facts

Never assert chart compliance from reading the template. Templates are not what runs; the render is.

```bash
helm lint "${chart}"
helm template orders-api "${chart}" > /tmp/render.yaml
```

`helm lint` checks that the chart is well-formed. It does **not** read your values for operational sense —
a chart that takes every pod down at once lints clean. Treat a clean lint as "this will install", never as
"this is safe to roll out".

Query the render as data rather than reading it as prose. `yq` here is jq syntax over YAML, and the render
is a multi-document stream:

```bash
yq -r 'select(.kind=="Deployment") | .spec.strategy.rollingUpdate.maxUnavailable' /tmp/render.yaml
yq -r 'select(.kind=="Deployment") | .spec.template.spec.containers[0].resources' /tmp/render.yaml
yq -r 'select(.kind=="Deployment") | .spec.selector.matchLabels' /tmp/render.yaml
```

When a chart carries environment overlays, render **each one** and diff them. A value that is correct in
`values.yaml` and wrong in `values-prod.yaml` is the defect this catches, and it is invisible in a
single render:

```bash
helm template orders-api "${chart}" -f "${chart}/values.yaml" > /tmp/render-default.yaml
helm template orders-api "${chart}" -f "${chart}/values-prod.yaml" > /tmp/render-prod.yaml
diff /tmp/render-default.yaml /tmp/render-prod.yaml
```

To see the conventions you are matching rather than guessing at them:

```bash
grep -rn 'app.kubernetes.io' platform/helm/*/templates/_helpers.tpl
grep -rn 'pod-security.kubernetes.io' platform/policies/
```

## The conventions

### Layout
`Chart.yaml` / `values.yaml` / `templates/` per chart, with `_helpers.tpl` owning every name and label.
Environment differences live in `values-<env>.yaml` overlays — never in a second copy of a template, and
never in a conditional that hardcodes an environment name.

### Naming and labels
- Object names come from the `<chart>.fullname` helper, never typed literally into a template.
- Every object carries the `<chart>.labels` helper output; every pod selector uses `<chart>.selectorLabels`.
- **`spec.selector.matchLabels` on a Deployment is immutable after creation.** Changing the selector labels
  of a running workload is not an edit — it is a delete and recreate, and the reconciler will fail the sync
  rather than perform it. If a selector must change, that is a planned replacement with an owner and a
  window, stated in the change summary. It is never a drive-by rename.

### Values
- Every value that an operator would reasonably tune is a value: replica count, resources, probe timings,
  image tag, rollout parameters.
- A value has one home. If `values-prod.yaml` repeats a key with the same value as `values.yaml`, delete it —
  a duplicated value is a value that will drift.
- No secret is ever written into a values file. Secrets arrive as a `secretKeyRef`; the chart references a
  name, never a credential.

### Workload baselines — hardcoded, not variabilized
These are properties of how Northstar runs workloads, not choices a caller makes. Writing them as a value
is itself the finding, because it turns a guarantee into a default someone can override during an incident:

- **Every container declares `resources.requests` and `resources.limits` for cpu and memory.** A container
  with no requests is `BestEffort` — it is the first thing evicted under node pressure, and it is scheduled
  as if it were free.
- **Every pod sets `securityContext.runAsNonRoot: true`.** See the vocabulary table for the numeric-UID
  requirement that goes with it.
- **A rolling update always leaves a serving floor.** `maxUnavailable` is never `100%` and never equals the
  replica count. With `replicas: 1` there is no floor available at all, so a service that must stay up
  during a rollout carries `replicas: 2` or more. This is an arithmetic property of the two values
  together, not a property of either one alone.
- **An image tag is never `latest`.** A floating tag with `imagePullPolicy: IfNotPresent` is the worst of
  both: the node keeps whatever it cached, so two pods of the same Deployment can run different code.
- **The readiness probe and the liveness probe address the same endpoint the application actually serves.**
  A probe path is a contract with the application, and it is verified against the app's routes, not
  assumed.

## Exact Kubernetes vocabulary — use these strings verbatim

Most chart failures at Northstar have been vocabulary, not logic. Each of these renders cleanly, lints
cleanly, and then behaves wrongly — which is why they are written down rather than left to recall.

| Thing | Correct | Common wrong answer | What the wrong one does |
|---|---|---|---|
| Rollout strategy | `RollingUpdate` | `Rolling` | Rejected at apply; the sync fails |
| Serving floor | `maxUnavailable: 0` | `maxUnavailable: "100%"` | Every pod terminates at once; full outage during a normal deploy |
| Memory quantity | `256Mi` | `256M` | 256 megabytes, not mebibytes — a silent 5% under-allocation |
| CPU quantity | `100m` | `100` | One hundred **cores**, not 100 millicores — the pod never schedules |
| Non-root enforcement | `runAsNonRoot: true` **plus** a numeric `runAsUser` | `runAsNonRoot: true` alone, against an image whose `USER` is a name | Kubelet cannot verify the UID before start: `CreateContainerConfigError`, pod never runs |
| Seccomp | `seccompProfile.type: RuntimeDefault` | `runtime/default` | The annotation-era spelling; ignored as a field value |
| Pod Security level | `pod-security.kubernetes.io/enforce: baseline` | `restricted` assumed | `baseline` does **not** require non-root; assuming it does is how a root container ships |
| Service port wiring | `targetPort: http` matching `ports[].name: http` | `targetPort: 8080` typed literally | Works until the container port moves, then routes to nothing |
| Probe field | `httpGet.path` | `httpGet.uri` | Renders and lints; the API server rejects the unknown field at apply |
| Argo CD sync of a new namespace | `CreateNamespace=true` in `syncOptions` | assumed automatic | First sync fails with a missing namespace |

## Offline verification contract

Northstar charts are verified **without a cluster** before they are proposed, and the verification is a
committed artifact rather than a command someone remembers to run.

### Render tests — "does the chart produce the manifest we intend?"

Tests live in `<chart>/tests/`, one concern per file, named `*.test.sh`:

```bash
#!/usr/bin/env bash
# rollout.test.sh — a rolling update must leave a serving floor.
set -euo pipefail
CHART="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$(helm template orders-api "$CHART")"

mu=$(echo "$RENDER" | yq -r 'select(.kind=="Deployment") | .spec.strategy.rollingUpdate.maxUnavailable')
replicas=$(echo "$RENDER" | yq -r 'select(.kind=="Deployment") | .spec.replicas')

[[ "$mu" != "100%" ]] || { echo "FAIL: maxUnavailable=100% takes every pod down at once"; exit 1; }
[[ "$replicas" -ge 2 ]] || { echo "FAIL: replicas=$replicas leaves no serving floor"; exit 1; }
echo "PASS: rollout keeps a serving floor (replicas=$replicas, maxUnavailable=$mu)"
```

Rules the runner depends on:

- Each test is executable, exits `0` on pass and non-zero on failure, and prints one line saying **what was
  checked and what the value was**. `FAIL` with no value is a test you cannot debug from CI output.
- `tests/run.sh` runs every `*.test.sh` in the directory and ends with a single summary line in the form
  `PASS n / FAIL n`, exiting non-zero if any test failed.
- A test asserts on the **render**, never on the template text. `grep maxUnavailable values.yaml` passes on
  a value the template never uses.
- A test that must fail before it can pass. Write the assertion against the current chart and watch it
  report the real defect **before** changing any value — a test written after the fix has never been
  observed failing, and an assertion that cannot fail is documentation.

### What a render test cannot tell you

State this honestly in the change summary rather than implying more coverage than exists:

- It cannot tell you the image will start. `runAsNonRoot` against a named `USER` renders perfectly and
  fails at container creation.
- It cannot tell you the API server will accept the object. Selector immutability, quota rejection and
  admission policy all live on the far side of a real apply.
- It cannot tell you the probe path exists. That is a claim about the application, and it is verified
  against the app's routes or against a running container.

## Reasoning zone — check the render before proposing

Walk the rendered manifest against these branches and name what you find:

- `maxUnavailable` at `100%`, or `>=` the replica count → **AVAILABILITY: no serving floor.** Blocks.
- A container with no `resources.requests` or no `resources.limits` → **RELIABILITY: unbounded workload.**
- `runAsNonRoot: true` with no numeric `runAsUser`, against an image whose `USER` is a name →
  **CORRECTNESS: pod will not start.** Name the image and the UID it needs.
- An image tag of `latest`, or a floating tag with `imagePullPolicy: IfNotPresent` →
  **REPRODUCIBILITY: two pods can run different code.**
- A changed value in `spec.selector.matchLabels` against a workload that already exists →
  **BLAST RADIUS: immutable field.** This is a replacement, not an edit. Stop and say so.
- A literal credential in a values file → **SECURITY: secret in desired state.** Blocks.
- A quantity, field name or enum not in the vocabulary table → **CORRECTNESS: wrong Kubernetes vocabulary.**
  Correct it against the table rather than guessing a plausible spelling.
- A value present in an overlay identical to the base → **STYLE: duplicated value.**

Every branch terminates in a named finding. "Looks fine" is not an output.

## Output schema

```json
{
  "chart": "platform/helm/orders-api",
  "lint_clean": true,
  "render_ok": true,
  "tests": {"passed": 4, "failed": 0},
  "findings": [
    {"severity": "availability", "rule": "no serving floor", "detail": "maxUnavailable: 100% with replicas: 1"},
    {"severity": "reliability", "rule": "unbounded workload", "detail": "containers[0] has no resources block"}
  ],
  "verdict": "changes-required"
}
```

`verdict` is `compliant` only when `lint_clean` and `render_ok` are both true, every test passes, and no
`availability`, `security` or `correctness` finding remains.

## NEVER DO

- **Never run `kubectl apply`, `kubectl delete`, `helm install`, `helm upgrade` or `argocd app sync`.**
  This skill authors and checks desired state. The reconciler is the only identity that writes to a
  cluster; propose the change on a branch and stop.
- **Never weaken a baseline to make a rollout succeed.** A pod that will not start under `runAsNonRoot` is
  an image problem, not a reason to delete the security context.
- **Never rename selector labels to tidy a chart.** It is an immutable field and the sync will fail; if the
  rename is genuinely needed it is a scheduled replacement with a stated window.
- **Never invent a Kubernetes field name.** If it is not in the vocabulary table and not in an existing
  Northstar chart, check the API reference rather than guessing.
- **Never edit `platform/helm/*/values-prod.yaml` as part of routine work.** Production values change
  through the reviewed change path, with `change-reviewer` approval.

## Stop conditions

- If `helm lint` or `helm template` fails, report the error and stop. Do not propose a chart that does not
  render.
- If the target is outside `platform/`, stop — this skill governs Northstar's Kubernetes desired state only.
- If a baseline cannot be satisfied without changing what the workload is (a service that genuinely cannot
  run non-root, a job that genuinely cannot tolerate a rolling update), stop and say so explicitly. That is
  a design question for a human, not a values edit.
