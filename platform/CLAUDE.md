# Cluster context for this directory

Work in this directory targets ONE cluster and ONE namespace:

- cluster: `northstar` (local kind)
- namespace: `northstar`
- kubeconfig: `platform/kubeconfigs/agent-readonly.yaml`
- context: `northstar-agent-readonly`

Never run a cluster command without `--kubeconfig` and `-n`. An agent that does not
state which cluster it is pointed at has not finished the sentence.

This identity is read-only by RBAC. If a command returns 403, that is the boundary
working — report it, do not route around it.
