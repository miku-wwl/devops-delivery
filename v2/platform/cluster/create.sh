#!/usr/bin/env bash
# Create the v2 "ent" cluster (E0): one control plane and three workers in three simulated zones.
#
#   bash v2/platform/cluster/create.sh            # run inside the devops-lab WSL distro
#
# What is real and what is simulated ([模拟]):
#   - every node is a Docker container on this one machine; "zone-a/b/c" are only node labels;
#   - each worker gets a REAL size from the kernel: 4 pinned CPUs (cpuset) and a 3.5 GiB memory
#     limit (cgroup memory.max), like a small VM (3 GiB in E0-E6; E7 added 512 MiB per worker for
#     the backup stack - chapter 8, platform/cluster/resize-workers.sh changed the running nodes);
#   - kubelet cannot see that size (it reads the VM's /proc/meminfo and /proc/cpuinfo), so the
#     part of the machine that does not belong to the node is subtracted through kubelet flags:
#       system-reserved cpu = host CPUs - 4             -> allocatable CPU  = 4 - 0.25
#       eviction-hard memory.available < MemTotal - (3584Mi - 150Mi)
#                                                        -> eviction starts at 3434 MiB used,
#                                                           150 MiB before the kernel OOM limit
#     (derivation and measurements: v2/manual chapter E0, evidence/e0/).
# Outside the cluster: pull-through registry mirrors and the cloud-provider-kind load balancer
# controller. The script is idempotent for those parts and never touches an existing cluster.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2="$(cd "$HERE/../.." && pwd)"
source <(tr -d '\r' < "$V2/platform/versions.env")

CLUSTER=ent
export KIND_EXPERIMENTAL_DOCKER_NETWORK=kind-ent   # own Docker network, apart from v1's "kind"
NET=$KIND_EXPERIMENTAL_DOCKER_NETWORK
STATE=${ENT_STATE_DIR:-$HOME/ent-data}             # ext4, outside the repo (survives repo moves)

NODE_CPUS=4 NODE_MEM_MI=3584 EVICT_MARGIN_MI=150 KUBE_RES="cpu=250m,memory=256Mi"
HOST_CPUS=$(nproc)
MEMTOTAL_MI=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
PHANTOM_CPU=$((HOST_CPUS - NODE_CPUS))
EVICT_MI=$((MEMTOTAL_MI - NODE_MEM_MI + EVICT_MARGIN_MI))
CP_CPUSET=0-3
declare -A ZONE=([ent-worker]=zone-a [ent-worker2]=zone-b [ent-worker3]=zone-c)
declare -A CPUSET=([ent-worker]=4-7 [ent-worker2]=8-11 [ent-worker3]=12-15)

echo "host: ${HOST_CPUS} CPUs, MemTotal ${MEMTOTAL_MI} MiB"
echo "worker: ${NODE_CPUS} CPUs, ${NODE_MEM_MI} MiB; system-reserved cpu=${PHANTOM_CPU}; eviction memory.available<${EVICT_MI}Mi"

mkdir -p "$STATE/audit-policy" "$STATE/audit-log"
cp "$HERE/audit-policy.yaml" "$STATE/audit-policy/policy.yaml"

worker() { # name zone
  cat <<EOF
  - role: worker
    labels:
      topology.kubernetes.io/region: local-1
      topology.kubernetes.io/zone: $2
      node.kubernetes.io/instance-type: sim-4c$(awk -v m="$NODE_MEM_MI" 'BEGIN {printf "%g", m / 1024}')g
    kubeadmConfigPatchesJSON6902:
      - group: kubeadm.k8s.io
        version: v1beta4
        kind: JoinConfiguration
        patch: |
          - op: add
            path: /nodeRegistration/kubeletExtraArgs/-
            value: {name: kube-reserved, value: "${KUBE_RES}"}
          - op: add
            path: /nodeRegistration/kubeletExtraArgs/-
            value: {name: system-reserved, value: "cpu=${PHANTOM_CPU}"}
          - op: add
            path: /nodeRegistration/kubeletExtraArgs/-
            value: {name: eviction-hard, value: "memory.available<${EVICT_MI}Mi,nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%"}
          - op: add
            path: /nodeRegistration/kubeletExtraArgs/-
            value: {name: eviction-minimum-reclaim, value: "memory.available=100Mi"}
EOF
}

CONFIG="$STATE/ent-cluster.yaml"
{
  cat <<EOF
# Rendered by v2/platform/cluster/create.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER}
networking:
  podSubnet: 10.240.0.0/16
  serviceSubnet: 10.96.0.0/16
kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      extraVolumes:
        - name: audit-policy
          hostPath: /etc/kubernetes/audit
          mountPath: /etc/kubernetes/audit
          readOnly: true
          pathType: Directory
        - name: audit-log
          hostPath: /var/log/kubernetes/audit
          mountPath: /var/log/kubernetes/audit
          pathType: DirectoryOrCreate
    scheduler:
      extraArgs:
        - name: bind-address
          value: "0.0.0.0"
    etcd:
      local:
        extraArgs:
          - name: listen-metrics-urls
            value: "http://0.0.0.0:2381"
  - |
    kind: KubeProxyConfiguration
    metricsBindAddress: "0.0.0.0:10249"
kubeadmConfigPatchesJSON6902:
  - group: kubeadm.k8s.io
    version: v1beta4
    kind: ClusterConfiguration
    patch: |
      - op: add
        path: /apiServer/extraArgs/-
        value: {name: audit-policy-file, value: /etc/kubernetes/audit/policy.yaml}
      - op: add
        path: /apiServer/extraArgs/-
        value: {name: audit-log-path, value: /var/log/kubernetes/audit/audit.log}
      - op: add
        path: /apiServer/extraArgs/-
        value: {name: audit-log-maxsize, value: "100"}
      - op: add
        path: /apiServer/extraArgs/-
        value: {name: audit-log-maxbackup, value: "5"}
      - op: add
        path: /controllerManager/extraArgs/-
        value: {name: bind-address, value: "0.0.0.0"}
nodes:
  - role: control-plane
    labels:
      topology.kubernetes.io/region: local-1
    extraMounts:
      - hostPath: ${STATE}/audit-policy
        containerPath: /etc/kubernetes/audit
        readOnly: true
      - hostPath: ${STATE}/audit-log
        containerPath: /var/log/kubernetes/audit
EOF
  for n in ent-worker ent-worker2 ent-worker3; do worker "$n" "${ZONE[$n]}"; done
} > "$CONFIG"

# 1. cluster
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "cluster $CLUSTER exists; not recreating"
else
  start=$(date +%s)
  kind create cluster --config "$CONFIG" --image "$KIND_NODE_IMAGE" --wait 180s
  echo "kind create cluster took $(( $(date +%s) - start )) s"
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

# 2. pull-through mirrors (Distribution in proxy mode), one per upstream registry
declare -A MIRROR=([mirror-docker]=https://registry-1.docker.io [mirror-ghcr]=https://ghcr.io
                   [mirror-quay]=https://quay.io [mirror-k8s]=https://registry.k8s.io)
for m in "${!MIRROR[@]}"; do
  if ! docker inspect "$m" >/dev/null 2>&1; then
    docker run -d --restart=always --name "$m" --network "$NET" \
      -e REGISTRY_PROXY_REMOTEURL="${MIRROR[$m]}" -v "$m:/var/lib/registry" "$REGISTRY_IMAGE" >/dev/null
  fi
done

# 3. the local push registry and GitLab join the cluster network (v1 keeps its own network too)
for c in kind-registry gitlab; do
  # "index" because a network name with a dash is not a valid template field name
  if docker inspect "$c" >/dev/null 2>&1 &&
     [ "$(docker inspect -f "{{json (index .NetworkSettings.Networks \"$NET\")}}" "$c")" = "null" ]; then
    docker network connect "$NET" "$c"
  fi
done

# 4. containerd on every node: localhost:5001 -> kind-registry, upstream registries -> mirrors
hosts() { # node registry server mirror
  docker exec "$1" mkdir -p "/etc/containerd/certs.d/$2"
  printf 'server = "%s"\n\n[host."http://%s:5000"]\n  capabilities = ["pull", "resolve"]\n' "$3" "$4" |
    docker exec -i "$1" cp /dev/stdin "/etc/containerd/certs.d/$2/hosts.toml"
}
for node in $(kind get nodes --name "$CLUSTER"); do
  docker exec "$node" mkdir -p /etc/containerd/certs.d/localhost:5001
  printf '[host."http://kind-registry:5000"]\n' |
    docker exec -i "$node" cp /dev/stdin /etc/containerd/certs.d/localhost:5001/hosts.toml
  hosts "$node" docker.io https://registry-1.docker.io mirror-docker
  hosts "$node" ghcr.io https://ghcr.io mirror-ghcr
  hosts "$node" quay.io https://quay.io mirror-quay
  hosts "$node" registry.k8s.io https://registry.k8s.io mirror-k8s
done

# 5. real node sizes (persist in the container's HostConfig, survive restarts)
docker update --cpuset-cpus "$CP_CPUSET" ent-control-plane >/dev/null
for n in ent-worker ent-worker2 ent-worker3; do
  docker update --cpuset-cpus "${CPUSET[$n]}" --memory "${NODE_MEM_MI}m" --memory-swap "${NODE_MEM_MI}m" "$n" >/dev/null
done

# 6. load balancers: cloud-provider-kind runs outside the cluster, like a cloud's LB service
if ! docker inspect ent-ccm >/dev/null 2>&1; then
  docker run -d --restart=unless-stopped --name ent-ccm --network host \
    -e KIND_EXPERIMENTAL_DOCKER_NETWORK="$NET" \
    -v /var/run/docker.sock:/var/run/docker.sock "$CLOUD_PROVIDER_KIND_IMAGE" \
    --gateway-channel disabled >/dev/null
fi

# 7. advertise the local registry (KEP-1755) and install metrics-server (vendored manifest)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:5001"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
kubectl apply -k "$V2/platform/addons/metrics-server"
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
