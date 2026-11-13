#!/usr/bin/env bash
# Quotas and default limits for a tenant namespace.
#   bash v2/experiments/e4/quota.sh
# Namespace e4-tenant gets a ResourceQuota (4 pods, 1 CPU and 512Mi requested, 1Gi memory
# limits) and a LimitRange (default request/limit per container, at most 500m CPU). Then:
#   1. a pod without any resources: admitted, the LimitRange fills in requests and limits;
#   2. a pod asking for 2 CPU: rejected by the LimitRange at admission;
#   3. a Deployment of 6 replicas: the ReplicaSet can only create pods until the quota is used up,
#      the rest are refused with "exceeded quota" (the Deployment itself is accepted);
#   4. the quota's used/hard figures.
# The namespace is deleted at the end.
set -uo pipefail
NS=e4-tenant
trap 'kubectl delete ns $NS --wait=false >/dev/null 2>&1' EXIT
kubectl create ns $NS >/dev/null
kubectl -n $NS apply -f - <<'YAML'
apiVersion: v1
kind: ResourceQuota
metadata: {name: tenant}
spec:
  hard: {pods: "4", requests.cpu: "1", requests.memory: 512Mi, limits.memory: 1Gi}
---
apiVersion: v1
kind: LimitRange
metadata: {name: tenant-defaults}
spec:
  limits:
    - type: Container
      defaultRequest: {cpu: 100m, memory: 64Mi}
      default: {memory: 128Mi}
      max: {cpu: 500m, memory: 256Mi}
YAML
pod() {   # name [cpu-request]
  local res=""; [ -n "${2:-}" ] && res="resources: {requests: {cpu: \"$2\"}}"
  kubectl -n $NS apply -f - <<YAML 2>&1
apiVersion: v1
kind: Pod
metadata: {name: $1}
spec:
  containers:
    - name: pause
      image: registry.k8s.io/pause:3.10
      $res
YAML
}
echo "== 1. a pod without resources"
pod no-resources
kubectl -n $NS get pod no-resources -o jsonpath='  resources filled in: {.spec.containers[0].resources}{"\n"}'
echo "== 2. a pod asking for 2 CPU"
pod too-big 2
echo "== 3. a Deployment of 6 replicas (100m and 64Mi each by default)"
kubectl -n $NS create deployment many --image=registry.k8s.io/pause:3.10 --replicas=6
sleep 15
kubectl -n $NS get deploy many --no-headers | awk '{print "  deployment many: ready " $2}'
kubectl -n $NS get events --sort-by=.lastTimestamp -o custom-columns=OBJ:.involvedObject.name,REASON:.reason,MSG:.message |
  grep -i "quota" | sort | uniq -c | sort -rn | head -3 | cut -c1-230
echo "== 4. quota"
kubectl -n $NS describe resourcequota tenant | sed -n '/Resource/,$p'
