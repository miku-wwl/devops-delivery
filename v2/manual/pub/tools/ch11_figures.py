"""Chapter 11: the three Mermaid xy charts become charts drawn from the evidence (figures.py); one new chart."""
from edit import Doc

d = Doc("11-e10")
d.block('```{.mermaid caption="处于 Running 的虚拟 Pod 数。',
        "![一万个虚拟 Pod 进入 Running 的过程，每个点是一次实际计数。K1 在创建结束之后是一条直线，斜率每秒 50 个——"
        "调度器并不忙，它在等客户端限速的令牌。K2 放开限速后调度跟着创建走，29.4 秒全部调度完；Running 晚到 48.6 秒，"
        "是因为所有 Pod 的状态都由同一个 kwok 控制器写入。](../figures/e10-scheduling.svg)")
d.block('```{.mermaid caption="删除 10 000 个 Pod 前后的 etcd 数据库。',
        "![删除 10 000 个 Pod 前后的 etcd。灰柱是数据库文件，绿柱是其中的有效数据：删除让文件增大；API server 的压缩"
        "把有效数据降到 24.3 MiB，文件却没有变小；碎片整理之后文件才变为 18.7 MiB。](../figures/e10-etcd.svg)")
d.block('```{.mermaid caption="API server 的匿名内存（MiB），每 2 秒取一个点',
        "![洪水期间 API server 的匿名内存，每秒一个采样点。两次运行中优先级 e10-low 都只有 3 个 LIST 在执行；曲线落到 0 的"
        "地方，是进程被内核杀死、Docker 重启它的时刻。上限 1536 MiB 时它在 4 秒内被杀，之后反复被杀；上限 2560 MiB 时，"
        "三个并发的 LIST 把它推到 2437 MiB，10 秒后越过上限被杀一次，重启后在同样的洪水下维持在 1.6–2.0 GiB。]"
        "(../figures/e10-apiserver-memory.svg)")
d.before("### 第一次运行：事故 E10-1",
         "![七次运行的结果。条形是洪水期间受害者成功请求的 p99，越短越好；括号里是洪水开始前的 p99。没有一次运行把它"
         "保持在安静值的 2 倍以内（绿色虚线）：每一次改动都排除了一个错误的解释，直到第 7 次才看清真正的限制是 API server 的"
         "内存。](../figures/e10-k5-runs.svg)")
d.save()
