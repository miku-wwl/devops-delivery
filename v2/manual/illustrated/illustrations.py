"""Editable, deterministic teaching SVGs. All are conceptual, never claimed as captures.

Owning sources: orders/main.py 199-268 and payments/main.py 83-143;
resilience.py CircuitBreaker; web.py Observe + E9 incident records;
assessment/t3-out-of-band.sh. No runtime measurement is generated here.
"""
from pathlib import Path
from html import escape

ASSETS = Path(__file__).resolve().parent / 'assets'
CAPTIONS = {
    'order-outcomes.svg':'订单与支付拥有独立状态：超时只改变调用方的知识；虚线是尚未实现的对账设计，不是当前执行路径。',
    'breaker-states.svg':'熔断状态机与保护范围；按服务的熔断不区分健康与故障实例，半开只放有限试探。',
    'investigation-path.svg':'从总体异常缩到一笔请求与源码，再用总体业务结果确认缓解；三种信号互相补足。',
    'assessment-tree.svg':'T3综合诊断的竞争假设；健康状态的覆盖范围与实际请求路径不同，观察应能够区分原因。',
    'concept-outbox.svg':'事务性Outbox的原子边界仅覆盖订单与事件行；发布后再标记可能重复，消费者仍需处理副作用窗口。',
    'concept-resilience.svg':'调用先占隔舱，每次尝试再检查期限与熔断；失败后的重试要经过预算与退避。20%是长期比例，并另有初始突发。',
    'concept-hpa-loop.svg':'HPA用观测值计算整数副本目标，再受容差、稳定窗口、策略与Pod启动约束；扩容决定不等于容量已经就绪。',
    'concept-wal-pitr.svg':'恢复链由基础备份与连续WAL组成；archive_timeout触发切段，不保证对象存储在5分钟内收到完整归档。',
    'concept-commit-paths.svg':'以简化时间线区分确认条件：异步不等备库；同步要等指定备库的确认。复制传输可以与本地提交并行，图中先后不是所有实际运行的固定时序。',
    'concept-tenant-fences.svg':'安全边界分工：身份授权、准入、网络、秘密、发布目标与审计共同约束访问；任何一层都不能替代其余层。',
    'concept-sampling.svg':'头部决定在请求开始时发生；尾部决策只能使用到达采样器的数据，迟到、丢失或已被头部丢弃的span仍可能缺失。',
    'concept-app-of-apps.svg':'E1初始GitOps布局：根Application创建分层子Application；这里的wave只描述该阶段，后续网格与安全资源扩展见第9章。',
}

# Derive corrected teaching views; the historical SVGs and their generators stay intact.
DERIVATIONS = {
    'concept-outbox.svg': {
        '任何一处崩溃，重来一遍都安全':'原子提交与副作用窗口是两回事',
        '不丢：事件和订单在同一个事务里提交':'事件与订单在同一事务里提交',
        '不重：中继在“发布”与“标记”之间崩溃会重发，':'发布后未标记：中继可能重发',
        'NATS 和 notifier 各去重一次':'消息去重仍不能消除任意副作用窗口',
    },
    'concept-resilience.svg': {
        '>熔断器</text>':'>截止时间</text>',
        '对方最近一直失败吗？':'总期限还有剩余吗？',
        '是：立即拒绝':'过期：立即拒绝',
        '超时与截止时间':'熔断器与单次超时',
        '这一次最多等多久？':'断开：立即拒绝',
        '1 秒，且不超过':'放行：最多1秒',
        '上游的剩余时间':'且不超过剩余时间',
        '重试总量不超过 20%':'长期20% + 初始突发',
    },
    'concept-hpa-loop.svg': {
        '期望副本 = 当前副本 ×':'期望副本 = 向上取整',
        '当前指标 ÷ 目标':'当前副本 × 指标比值',
        '扩容：立即':'扩容：按策略执行',
    },
    'concept-wal-pitr.svg': {'或最迟每 5 分钟':'5分钟触发切段'},
    'concept-commit-paths.svg': {
        '异步复制：先回答客户端，再发送 WAL':'异步复制：不等待备库落盘就回答',
        '稍后发送 WAL：落后的这一段，主库失效时就丢了':'异步发送WAL：未到备库的尾部仍有风险',
    },
    'concept-tenant-fences.svg': {
        '实验 1–3':'身份与授权', '实验 5':'准入与可用性', '实验 4':'网络与网格',
        '实验 7':'秘密与轮换', '实验 6':'发布目标', '不拦任何东西，事后回答　实验 3':'不负责拦截；用于事后追溯',
    },
    'concept-sampling.svg': {'等 10 秒，看完整条链路':'等约10秒，按已到达span判断'},
    'concept-app-of-apps.svg': {},
}


class SVG:
    def __init__(self,h):
        self.parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="640" height="{h}" viewBox="0 0 640 {h}"><defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#638391"/></marker></defs><rect width="640" height="{h}" fill="white"/>']
    def text(self,x,y,t,size=14,color='#203345',anchor='start',weight='400'):
        self.parts.append(f'<text x="{x}" y="{y}" font-size="{size}" font-family="Microsoft YaHei, sans-serif" fill="{color}" text-anchor="{anchor}" font-weight="{weight}">{escape(t)}</text>')
    def box(self,x,y,w,h,lines,fill='#edf5f7',stroke='#a6c4cf'):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="{fill}" stroke="{stroke}"/>')
        for i,line in enumerate(lines):self.text(x+w/2,y+24+i*21,line,14,anchor='middle',weight='600' if i==0 else '400')
    def arrow(self,coords,dashed=False):
        d=' '.join(f'{x},{y}' for x,y in coords)
        self.parts.append(f'<polyline points="{d}" fill="none" stroke="#638391" stroke-width="1.6" marker-end="url(#a)"'+(' stroke-dasharray="5 4"' if dashed else '')+'/>')
    def save(self,name):
        (ASSETS/name).write_text('\n'.join(self.parts)+ '</svg>\n',encoding='utf-8')


def generate():
    ASSETS.mkdir(parents=True,exist_ok=True)
    s=SVG(325)
    s.text(16,24,'同一业务键，两个独立的状态拥有者',16,weight='600')
    s.text(16,61,'orders',14,color='#19796d',weight='600')
    s.box(110,40,140,66,['PENDING','等待支付结果'])
    s.box(390,40,220,66,['FAILED + 释放库存','当前非201分支'])
    s.arrow([(250,73),(390,73)])
    s.text(320,59,'超时 / 409',13,anchor='middle')
    s.text(16,159,'payments',14,color='#19796d',weight='600')
    s.box(110,135,140,66,['处理中','幂等锁仍存在'])
    s.box(390,135,220,66,['approved','结果可能稍后保存'])
    s.arrow([(250,168),(390,168)])
    s.text(320,153,'继续执行',13,anchor='middle')
    s.arrow([(500,201),(500,249),(250,249)],True)
    s.box(16,225,234,65,['待核对 / 查询结果','设计建议，当前未实现'],'#fff5e8','#d6b787')
    s.text(318,285,'超时 ≠ 服务端已经撤销',15,color='#9a6226',weight='600')
    s.save('order-outcomes.svg')
    s=SVG(320)
    s.text(16,24,'先看状态转移，再看保护范围',16,weight='600')
    s.box(16,85,170,72,['CLOSED','记录近期尝试'])
    s.box(235,85,170,72,['OPEN','快速拒绝5秒'])
    s.box(454,85,170,72,['HALF_OPEN','最多3次试探'])
    s.arrow([(186,120),(235,120)])
    s.text(211,77,'达阈值',12,anchor='middle')
    s.arrow([(405,120),(454,120)])
    s.text(429,77,'到期',12,anchor='middle')
    s.arrow([(540,157),(540,190),(320,190),(320,157)])
    s.text(428,183,'任一失败 → 再OPEN',12,anchor='middle')
    s.arrow([(540,85),(540,57),(100,57),(100,85)])
    s.text(325,49,'全部试探成功 → CLOSED',12,anchor='middle')
    s.box(16,226,608,69,['一个 Upstream 对应一个服务，不是一个后端实例','部分实例故障也可能打开整个服务的熔断器'],'#fff5e8','#d6b787')
    s.save('breaker-states.svg')
    s=SVG(300)
    s.text(16,25,'从“多少人坏了”到“这一笔为什么坏”',16,weight='600')
    s.box(16,68,180,85,['Metrics','旅程 / 时间 / 比例','范围与异常开始'])
    s.box(230,68,180,85,['Trace','关键调用 / 等待','单笔因果与上下文'])
    s.box(444,68,180,85,['Logs + Code','业务键 / 失败分支','状态与真实执行'])
    s.arrow([(196,110),(230,110)])
    s.arrow([(410,110),(444,110)])
    s.arrow([(534,153),(534,200),(106,200),(106,153)])
    s.text(320,190,'缓解后重新检查总体成功率与延迟',14,anchor='middle',color='#19796d')
    s.box(16,224,608,56,['部署记录解释“刚刚改变了什么”；来源与时间必须对应'],'#f5f7f1','#c2cfb3')
    s.save('investigation-path.svg')
    s=SVG(348)
    s.text(16,25,'症状相同，下一项证据不同',16,weight='600')
    s.box(16,63,190,73,['浏览正常 / 下单失败','GitOps 全部Healthy'])
    s.box(270,53,354,63,['业务实现或配置','支付端收到了请求吗？参数改变了吗？'])
    s.box(270,146,354,63,['网络或身份策略','ztunnel更新了什么？请求在哪里被拒？'])
    s.box(270,239,354,63,['过载或调用方保护','超时、熔断、隔舱与CPU是否相关？'])
    s.arrow([(206,100),(238,100),(238,84),(270,84)])
    s.arrow([(206,100),(238,100),(238,177),(270,177)])
    s.arrow([(206,100),(238,100),(238,270),(270,270)])
    s.text(16,329,'Healthy 只覆盖被管理资源的健康判定；不能替代业务与额外对象检查。',13,color='#19796d')
    s.save('assessment-tree.svg')
    for name, changes in DERIVATIONS.items():
        content = (ASSETS.parent.parent/'figures'/name).read_text(encoding='utf-8')
        for old, new in changes.items():
            if old not in content:
                raise ValueError(f'Missing historical label in {name}: {old}')
            content = content.replace(old,new)
        (ASSETS/name).write_text(content,encoding='utf-8')


if __name__=='__main__':generate()
