# labs/clusters/ — cluster definitions

Reserved for kind/k3d cluster manifests a module needs to ship as a file rather than create from a
command. Currently empty on purpose: **M12 creates the `northstar` kind cluster inline** (`kind create
cluster --name northstar`) so the learner watches it come up rather than applying a config they did not
read, and tears it down in the same lab.

Put a cluster config here only when a module needs one that cannot be expressed as a command in the
lab — a multi-node topology, a custom CNI, or port mappings a learner should not have to retype.
