# E4 eviction prediction (written before run 2)

Run 1 (`eviction-1.log`, an earlier version of `experiments/e4/eviction.sh`) ended within
seconds: its wait loop counted the hogs that were Running while they were still Pending, saw
none and stopped; the namespace was deleted before any pressure built up. It recorded one real
result: the kubelet rejected the Guaranteed pod (requests = limits 300Mi) at admission with
reason `OutOfmemory`, although the pod was bound with `nodeName` and the scheduler never saw it.
ent-worker has 2666 MiB allocatable and its pods already requested 2402 MiB.

Run 2: `experiments/e4/eviction.sh eviction-2 ent-worker`, three pods bound to ent-worker:

| Pod | QoS | Request | Memory |
|---|---|---|---|
| guaranteed | Guaranteed | 128Mi (= limit) | holds 80 MiB |
| burst-hog | Burstable | 64Mi, no limit | holds 100 MiB, grows 4 MiB/s from the start |
| be-hog | BestEffort | none | holds 150 MiB; grows 3 MiB/s only after the script signals it, once the first hog has stopped |

The kubelet evicts when `memory.available` (= 15642 MiB capacity − node working set) falls
below 12720Mi, i.e. at a node working set of ~2922 MiB; before the run the working set was
2150-2350 MiB. It ranks pods by (1) working set above the request, (2) priority, (3) working
set minus request (`experiments/e4/evict_rank.py`). Before the run the highest real candidate on
ent-worker is `data/pg-main-1`: 59 MiB above its 256 MiB request, priority 0.

Testable claims, with the tolerance decided now:

| | Claim | Passes if |
|---|---|---|
| V1 | burst-hog is evicted first, although be-hog is BestEffort: when pressure is reached its working set minus request (≥ 300 MiB) is larger than be-hog's (~160 MiB) | burst-hog `Failed/Evicted` while be-hog is still Running |
| V2 | be-hog is evicted second, after it starts to grow | be-hog `Failed/Evicted` after the signal |
| V3 | nothing else is evicted or killed: the Guaranteed pod stays within its request, pg-main-1 ranks below both hogs | guaranteed Running at the end; no Evicted event outside `e4-evict`; no phase or restart change of any other pod on ent-worker |
| V4 | the kubelet acts within about two 10-s checks of the threshold, before the node container's 3072 MiB limit | the evicted pods' messages report `memory.available` below 12720Mi; the lowest sampled `memory.available` ≥ 12570 MiB (overshoot ≤ 150 MiB); no container `OOMKilled` |
| V5 | while the node reports MemoryPressure, the kubelet's admission rejects a new BestEffort pod even when it is bound with `nodeName` | be-probe `Failed/Evicted`, message naming the MemoryPressure condition |
| V6 | MemoryPressure and the `node.kubernetes.io/memory-pressure` taint appear within ~20 s of the first eviction and clear ~5 minutes (the transition period) after the last observed pressure | sampled timeline; condition `lastTransitionTime` when it clears is 5-6 min after the second eviction |

Expected timing (not a pass criterion): the first eviction 50-200 s after the hogs start (the
working set has to grow by 200-700 MiB at 4 MiB/s; between runs it varied from 1886 to 2346 MiB,
mostly page cache), the second 150-250 s after the signal.
