"""Who wrote what - from the Kubernetes audit log (E8, chapter 9).

  docker exec ent-control-plane grep -h -e e8-probe -e impersonatedUser /var/log/kubernetes/audit/audit.log \
    | python3 audit_who.py <since, ISO 8601 UTC> [object-name ...]

1. every logged request on an object with one of the given names: time, user, impersonated user, verb,
   resource, namespace/name, HTTP code (and whether it was a dry run);
2. every logged write made with impersonation since <since>, counted by impersonated user, verb,
   resource, namespace, HTTP code and whether it was applied or only a dry run (Argo CD's server-side
   diff sends dry runs).
The audit policy (platform/cluster/audit-policy.yaml) does not log reads of service accounts: a refused
read appears only in the client's own error message, not here.
"""
import json
import sys
from collections import Counter

WRITES = ("create", "update", "patch", "delete")


def main() -> None:
    since, names = sys.argv[1], set(sys.argv[2:])
    hits, imp = [], Counter()
    for line in sys.stdin:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        ts = e.get("requestReceivedTimestamp", "")
        if e.get("stage") != "ResponseComplete" or ts < since:
            continue
        ref = e.get("objectRef") or {}
        user = (e.get("user") or {}).get("username", "")
        as_user = (e.get("impersonatedUser") or {}).get("username", "")
        code = (e.get("responseStatus") or {}).get("code", "")
        res = ref.get("resource", "") + ("/" + ref["subresource"] if ref.get("subresource") else "")
        ns = ref.get("namespace", "-")
        dry = " (dry run)" if "dryRun=All" in e.get("requestURI", "") else ""
        if ref.get("name") in names:
            hits.append(f"{ts[:23]} {user} as={as_user or '-'} {e['verb']} {res} {ns}/{ref['name']} {code}{dry}")
        if as_user and e["verb"] in WRITES:
            imp[(as_user, e["verb"], res, ns, code, "dry-run" if dry else "applied")] += 1
    print(f"requests on {' '.join(sorted(names)) or '(no names)'} since {since}:")
    for h in hits:
        print("  " + h)
    print(f"writes with impersonation since {since} (impersonated user, verb, resource, namespace, code, applied/dry-run: count):")
    for k, n in sorted(imp.items()):
        print("  " + " ".join(map(str, k)) + f": {n}")


if __name__ == "__main__":
    main()
