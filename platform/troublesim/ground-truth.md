| Workload | Signature | Root cause | Blast radius |
|---|---|---|---|
| `imagepull-test` | ImagePullBackOff | image `nonexistent-registry.io/fake-app:v1.0.0` does not resolve | 2 replicas, never served |
| `crashloop-test` | CrashLoopBackOff | container command exits 1 after 5s | 1 replica, never served |
| `resource-limit-test` | Pending | requests 10Gi/4000m × 3, node cannot satisfy | 3 replicas, never scheduled |
| `liveness-probe-test` | restart loop **and** zero endpoints | TWO defects: liveness probes port 9999 where nothing listens, so the container is killed repeatedly; readiness probes `/ready` on port 8080 while nginx serves 80, so pods never go Ready | 2 replicas, flapping and never serving |
| `configmap-mount-test` | ContainerCreating, `FailedMount` | **the ConfigMap is fine.** The pod also mounts Secret `missing-secret-does-not-exist`, which is absent. The upstream filename names the wrong object | 1 replica, never starts |

Verified against the pinned manifests, not inferred from filenames. Fault `04` carries two
independent defects and fault `05`'s filename names the wrong object — both are traps for an agent
that pattern-matches on names instead of reading events. Task 8 grades `04` correct only if BOTH
defects are found.
