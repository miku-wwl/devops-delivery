"""Build the independent Illustrated Edition without running the lab or rewriting history."""
from __future__ import annotations

import argparse
import hashlib
import html
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image
from pypdf import PdfReader, PdfWriter
from presentation import CODE_STEPS, SHOT_AIDS

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MAN = HERE.parent
BUILD = MAN / "build" / "illustrated"
CAT = json.loads((HERE / "sources.json").read_text(encoding="utf-8"))
BASE = CAT["baseline"]
URL = CAT["repository"] + "/blob/" + BASE + "/"
DEFAULT = MAN / "dist" / "Enterprise-Platform-SRE-Handbook-Vol2-Illustrated-Edition.pdf"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def svg_sha(path: Path) -> str:
    return sha(path.read_text(encoding='utf-8').encode('utf-8'))


def link(path: str, start: int | None = None, end: int | None = None) -> str:
    if not (ROOT/path).exists():
        raise FileNotFoundError(f'Linked repository path is missing: {path}')
    base = CAT['repository'] + '/tree/' + BASE + '/' if (ROOT/path).is_dir() else URL
    return base + path + (f"#L{start}-L{end or start}" if start else "")


def grounded(path: str) -> str:
    actual = (ROOT / path).read_text(encoding="utf-8").replace("\r\n", "\n")
    baseline = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT).decode("utf-8").replace("\r\n", "\n")
    if actual != baseline:
        raise ValueError(f"Source changed since the declared baseline: {path}")
    return actual


def color(line: str, start: int = 0, end: int | None = None) -> str:
    # Highlight without changing one character of the executable source.
    pat = r'''(\#.*$|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:async|await|def|class|if|else|elif|for|in|try|except|finally|return|raise|with|not|and|or|None|True|False|resource|terraform|encryption)\b)'''
    end = len(line) if end is None else end
    out, last = [], start
    for m in re.finditer(pat, line):
        a, b = max(start, m.start()), min(end, m.end())
        if a >= b:
            continue
        out.append(html.escape(line[last:a]))
        raw = m.group(0)
        cls = "com" if raw.startswith("#") else "str" if raw.startswith(('"', "'")) else "kw"
        out.append(f'<span class="{cls}">{html.escape(line[a:b])}</span>')
        last = b
    out.append(html.escape(line[last:end]))
    return "".join(out)


def visual_wrap(line: str, limit: int = 80) -> list[tuple[int, int]]:
    """Only split the presentation; joined fragments retain every source character.

    Prefer parameter/SQL comma boundaries and whitespace. Continuation gutters
    carry an arrow instead of a new source line number. Never leave a tiny
    closing quote or parenthesis on an otherwise empty visual line.
    """
    parts, start = [], 0
    pairs = {('FOR','UPDATE'), ('ORDER','BY'), ('GROUP','BY'), ('INSERT','INTO'),
             ('DELETE','FROM'), ('IS','NULL'), ('IS','NOT'), ('NOT','NULL'), ('SKIP','LOCKED')}
    def boundary(p):
        left = re.search(r'([A-Za-z_]+)\s*$', line[:p])
        right = re.match(r'\s*([A-Za-z_]+)', line[p:])
        return not (left and right and (left[1],right[1]) in pairs)
    while len(line) - start > limit:
        stop = start + limit
        minimum = start + int(limit * .48)
        candidates = [m.end() for m in re.finditer(r',|\s+|(?:&&|\|\|)', line)
                      if minimum <= m.end() <= stop and len(line) - m.end() >= 14 and boundary(m.end())]
        commas = [p for p in candidates if line[p - 1] == ',']
        cut = (commas or candidates or [stop])[-1]
        parts.append((start, cut))
        start = cut
    parts.append((start, len(line)))
    assert ''.join(line[a:b] for a, b in parts) == line
    return parts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=DEFAULT)
    ap.add_argument("--sources-only", action="store_true")
    args = ap.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    import illustrations
    illustrations.generate()
    chapters = sorted((HERE / "chapters").glob("*.md"))
    corpus = "\n".join(p.read_text(encoding="utf-8") for p in chapters)
    body_chapters = [p for p in chapters if re.match(r"(?:0[1-9]|1[0-3])-", p.name)]
    if len(body_chapters) != 13:
        raise ValueError("The edition must contain all 13 teaching chapters")
    captions = {}
    for p in sorted((MAN / "chapters").glob("*.md")):
        for caption, name in re.findall(r"!\[(.*?)\]\([^\n)]*/([^/\n)]+\.svg)\)", p.read_text(encoding="utf-8")):
            captions[name] = caption
    captions["concept-outbox.svg"] = "事务性Outbox的原子边界仅覆盖订单与事件行；发布后再标记可能重复，消费者仍需处理副作用窗口。"
    captions["concept-saga.svg"] = "编排式Saga的正常步骤与补偿路径；补偿是独立操作，也可能失败，不能当作跨服务数据库回滚。"
    captions["concept-l4-l7.svg"] = "同一个调用方、两个副本，两种选择时机。少量长连接可能持续集中到同一后端；L7按请求选择。图中为E2实测份额取整：无网格97.1%/2.9%，waypoint后49.7%/50.3%。"
    captions["concept-eviction-order.svg"] = "E4中三个Pod的内存驱逐顺序：先看是否超出requests，再看优先级，最后看超出量。QoS类别不是直接排序键；超出160 MiB的BestEffort排在超出712 MiB的Burstable之后。"
    captions["concept-iac-split.svg"] = "对象所有权与状态位置：Argo CD管理集群中受跟踪的声明，从E11起管理自己；OpenTofu管理GitLab门禁，状态由GitLab加锁、客户端加密。原Garage后端因锁测试失败而停用。"

    used_codes, used_figs, used_shots = {}, {}, {}
    code_ids = list(CAT["codes"])
    shot_ids = list(CAT["shots"])

    def code(m):
        key = m.group(1)
        c = CAT["codes"][key]
        content = grounded(c["path"])
        lines = content.splitlines()
        ranges = c.get("ranges")
        if not ranges:
            start = next(i for i, s in enumerate(lines, 1) if s == c["start"])
            end = next(i for i, s in enumerate(lines, 1) if i >= start and s == c["end"])
            ranges = [[start, end]]
        selected = [lines[n - 1] for a, b in ranges for n in range(a, b + 1)]
        indent = min(len(s) - len(s.lstrip(' ')) for s in selected if s.strip())
        cid = f"C{code_ids.index(key) + 1:02}"
        rows, raw, displayed = [], [], []
        for j, (a, b) in enumerate(ranges):
            if not 1 <= a <= b <= len(lines):
                raise ValueError((key, a, b))
            if j:
                rows.append('<span class="line omission"><span class="ln">…</span><span class="txt">[中间源码省略]</span></span>')
            for n in range(a, b + 1):
                s = lines[n - 1]
                focus = n in c.get("focus", []) or any(t in s for t in c.get("focus_text", []))
                visible = s[indent:] if s.strip() else s
                fragments = visual_wrap(visible)
                displayed.append({'line':n, 'fragments':[visible[a:b] for a,b in fragments]})
                assert ((' ' * indent + ''.join(visible[a:b] for a,b in fragments)) if s.strip() else visible) == s
                for v, (a1, b1) in enumerate(fragments):
                    cls = (' focus' if focus else '') + (' continuation' if v else '')
                    anchor = '' if v else f' id="code-{cid}-L{n}"'
                    rows.append(f'<span class="line{cls}" data-source-line="{n}"{anchor}><span class="ln">{"↳" if v else n}</span><span class="txt">{color(visible, a1, b1) or " "}</span></span>')
                raw.append(s)
        steps = []
        for i, (a, b, text) in enumerate(CODE_STEPS[key], 1):
            if not all(any(x <= n <= y for x,y in ranges) for n in range(a,b+1)):
                raise ValueError(f'Annotation outside excerpt: {key} L{a}-{b}')
            label = f'L{a}' + (f'–{b}' if b != a else '')
            steps.append(f'<li><span class="step-no">{i}</span><a href="#code-{cid}-L{a}">{label}</a>　{html.escape(text)}</li>')
        source_url = link(c["path"], ranges[0][0], ranges[-1][1])
        used_codes[key] = {**c, "id":cid, "ranges":ranges, "file_sha256":sha(content.encode()),
                           "excerpt_sha256":sha("\n".join(raw).encode()), "url":source_url,
                           "common_indent_omitted":indent, "display_lines":displayed, "reading_steps":CODE_STEPS[key],
                           "excerpt_lines":len(raw)}
        return (f'<div class="codepanel" id="code-{key}"><div class="codepanel-title">{cid} · {html.escape(c["title"])}</div>'
                + '<pre>' + "".join(rows) + '</pre>'
                + '<ol class="code-steps">' + ''.join(steps) + '</ol>'
                + f'<div class="codepanel-source">来源：<a href="{source_url}">{html.escape(c["path"])}</a> · {BASE[:7]} · '
                + ", ".join(f"L{a}–{b}" for a, b in ranges)
                + f'。共同缩进省略{indent}空格；相对缩进保留，↳为同一原行的视觉续行；绿色为教学强调。</div></div>')

    def figure(m):
        name = m.group(1)
        new = name in illustrations.CAPTIONS
        path = (HERE / "assets" if new else MAN / "figures") / name
        if not path.is_file():
            raise FileNotFoundError(path)
        kind = "机制示意图" if new or name.startswith("concept-") else "模型曲线" if name.startswith("model-") else "历史实测"
        cap = illustrations.CAPTIONS[name] if new else captions.get(name, name)
        rel = path.relative_to(ROOT).as_posix()
        used_figs[name] = {"path":rel, "kind":kind, "caption":cap, "sha256":svg_sha(path), "hash_scope":"UTF-8/LF normalized SVG source"}
        if name in illustrations.DERIVATIONS:
            original = MAN / 'figures' / name
            used_figs[name].update(derived_from=original.relative_to(ROOT).as_posix(),
                original_sha256=svg_sha(original), label_changes=illustrations.DERIVATIONS[name])
        if name in illustrations.REDRAWINGS:
            original = MAN / 'figures' / name
            used_figs[name].update(derived_from=original.relative_to(ROOT).as_posix(),
                original_sha256=svg_sha(original), redraw=illustrations.REDRAWINGS[name])
        return f'<figure id="fig-{Path(name).stem}"><span class="fig-kind">{kind}</span><img class="{"new" if new else "legacy"}" src="{path.as_uri()}" alt="{html.escape(cap)}"><figcaption>{html.escape(cap)}</figcaption></figure>'

    def shot(m):
        key = m.group(1)
        s = CAT["shots"][key]
        aid = SHOT_AIDS[key]
        path = ROOT / s["path"]
        image_size = Image.open(path).size
        width, height = image_size
        views = []
        annotated_views = []
        for i, original_view in enumerate(aid.get('views', s["views"])):
            view = dict(original_view)
            if 'marks' not in view:
                view['marks'] = aid['marks'][i]
            if 'note' not in view:
                view['note'] = aid['notes'][i]
            x, y, w, h = view["rect"]
            if x < 0 or y < 0 or x + w > width or y + h > height:
                raise ValueError(f"Crop outside original: {key} {view['rect']} {image_size}")
            mm = view.get("width_mm", 170)
            overlays = []
            for a, b, c, d in view['marks']:
                if min(a,b,c,d) < 0 or a + c > w or b + d > h:
                    raise ValueError(f'Annotation outside crop: {key} {view}')
                overlays.append(f'<span class="shot-mark" style="left:{100*a/w:.4f}%;top:{100*b/h:.4f}%;width:{100*c/w:.4f}%;height:{100*d/h:.4f}%"></span>')
            label = re.sub(r'^[①②③]\s*', '', view['label'])
            views.append(f'<div class="shot-view"><div class="shot-label"><b>{chr(65+i)}</b> {html.escape(label)}</div>'
                + f'<div class="shot-window" style="width:{mm}mm;height:{mm*h/w:.4f}mm">'
                + f'<img src="{path.as_uri()}" alt="{html.escape(label)}" style="width:{mm*width/w:.4f}mm;height:{mm*height/w:.4f}mm;left:{-mm*x/w:.4f}mm;top:{-mm*y/w:.4f}mm">'
                + ''.join(overlays) + '</div>'
                + f'<p class="shot-observe">{html.escape(view["note"])}</p></div>')
            annotated_views.append(view)
        sid = f"S{shot_ids.index(key)+1:02}"
        used_shots[key] = {**s,"views":annotated_views,"conclusion":aid['conclusion'],"id":sid,"dimensions":image_size,"sha256":sha(path.read_bytes()),"url":link(s["path"])}
        used_shots[key]['figure_parts'] = len(views) if aid.get('split_views') else 1
        if aid.get('split_views'):
            parts = []
            for i, view_html in enumerate(views):
                letter = chr(65+i)
                conclusion = f'<p class="shot-conclusion">{html.escape(aid["conclusion"])}</p>' if i==len(views)-1 else ''
                parts.append(f'<figure class="shot" id="shot-{key}{"" if i==0 else "-"+letter}"><span class="fig-kind">{s["kind"]} · {sid} · {letter}</span>'
                    + view_html + conclusion + f'<figcaption>{html.escape(s["caption"])}（局部{letter}）</figcaption>'
                    + f'<div class="source">原图：<a href="{link(s["path"])}">{sid}</a>；CSS裁剪与出版边框，原PNG未修改；A/B来自同一原图。</div></figure>')
            return ''.join(parts)
        return (f'<figure class="shot" id="shot-{key}"><span class="fig-kind">{s["kind"]} · {sid}</span>'
            + ''.join(views) + f'<p class="shot-conclusion">{html.escape(aid["conclusion"])}</p><figcaption>{html.escape(s["caption"])}</figcaption>'
            + f'<div class="source">原图：<a href="{link(s["path"])}">{sid}</a>；CSS视窗裁剪，原PNG字节未修改。金色框与A/B为出版标注；各局部来自同一原图。</div></figure>')

    for p in chapters:
        text = p.read_text(encoding="utf-8")
        text = re.sub(r"\{\{code:([\w-]+)\}\}", code, text)
        text = re.sub(r"\{\{fig:([\w.-]+)\}\}", figure, text)
        text = re.sub(r"\{\{shot:([\w-]+)\}\}", shot, text)
        if re.search(r"\{\{(?:code|fig|shot):", text):
            raise ValueError(f"Unexpanded source directive in {p}")
        # Short ASCII anchors avoid overlong PDF name tokens for Chinese headings.
        heading_no = 0
        def anchor(m):
            nonlocal heading_no
            heading_no += 1
            attrs = m.group(3) or ''
            if re.search(r'(?:^|\s)#', attrs):
                return m.group(0)
            return f'{m.group(1)} {m.group(2)} {{#s-{p.stem}-{heading_no} {attrs}}}'
        text = re.sub(r'^(#{2,6}) ([^\n]+?)(?: \{([^{}\n]+)\})?$', anchor, text, flags=re.M)
        if p.name == '00-guide.md':
            heading, content = text.split('\n',1)
            text = heading + '\n\n::: reading-guide\n' + content + '\n:::\n'
        (BUILD / p.name).write_text(text, encoding="utf-8")

    # Full historical evidence index, retained outside the teaching narrative.
    sys.path.insert(0, str(MAN / "pub"))
    import build_pub
    historical = {}
    for p in sorted((MAN / "chapters").glob("*.md")):
        n = int(p.name[:2])
        refs = {}
        build_pub.evidence_markers(p.read_text(encoding="utf-8"), n, refs)
        paths = []
        for ref in refs:
            if any(c in ref for c in '*?['):
                matches = sorted((ROOT/'v2').glob(ref))
                if not matches:
                    raise FileNotFoundError(f'Historical source pattern has no files: {ref}')
                paths.extend(x.relative_to(ROOT/'v2').as_posix() for x in matches)
            else:
                paths.append(ref)
        historical[f"e{n-1}"] = list(dict.fromkeys(paths))
    appendix = ['# 附录 C　代码、图表与界面来源 {#source-index .unnumbered}',
        f'源码与历史素材锚定提交 `{BASE[:7]}`。下列路径可点击进入固定版本；源码省略处单独标记，面板注明省去的共同缩进，↳只表示同一原行的视觉续行，符号与相对缩进不变。图表源文件与完整来源索引见仓库 `v2/manual/illustrated/SOURCES.md`。\n', '<div class="index">']
    index_md = [f'# Illustrated Edition 来源索引\n\n基线：`{BASE}`。源码与SVG的SHA-256按UTF-8/LF统一后计算；原始PNG按完整原始字节计算。源码不变；出版视图省略共同缩进并按语义分成视觉续行，可重组核对每个字符。步骤对应原行号，不属于可执行源码。\n\n## 代码节选\n']
    for c in used_codes.values():
        ranges = ', '.join(f'L{a}–{b}' for a,b in c['ranges'])
        item = f'**{c["id"]}　{c["title"]}**　[{c["path"]}]({c["url"]}) · {ranges}'
        appendix.append(item + '\n')
        index_md.append(item + f'\n\n文件 SHA-256 `{c["file_sha256"]}`；节选 SHA-256 `{c["excerpt_sha256"]}`。共同缩进省略{c["common_indent_omitted"]}空格；步骤：'+str(c['reading_steps'])+'。\n')
    appendix.append('**界面与终端素材**\n')
    index_md.append('\n## 界面与终端素材\n')
    for s in used_shots.values():
        item = f'**{s["id"]}　{s["kind"]}**　[{s["path"]}]({s["url"]})'
        appendix.append(item + '\n')
        index_md.append(item + f'\n\n原图 SHA-256 `{s["sha256"]}`；视窗（左、上、宽、高，原始像素）：' + str([v['rect'] for v in s['views']]) + '。金色框坐标相对各视窗：'+str([v['marks'] for v in s['views']])+'。仅出版视图裁剪/边框标注，原PNG未编辑。\n')
    appendix += ['**实验与完整实现**\n', '[实验脚本索引]('+link('v2/docs/experiment-index.md')+')、[考核与恢复入口]('+link('v2/assessment/README.md')+')、[复现环境与安全边界]('+link('v2/docs/REPRODUCE.md')+')。本轮未运行实验环境。\n', '</div>']
    (BUILD / '92-sources.md').write_text('\n\n'.join(appendix), encoding='utf-8')

    appendix_d = ['# 附录 D　实验与 Evidence 索引 {#evidence-index .unnumbered}',
        '正文的E0–E12编号指向这里。第一组列本版关键观察，随后保留旧版正文引用的完整文件索引；路径均链接到固定基线。历史原始数据没有改动，本轮只核对存档，不声称重新运行。\n', '<div class="index">']
    for key, e in CAT['evidence'].items():
        appendix_d.append(f'## {key.upper()}　{e["title"]} {{#ev-{key} .unnumbered .unlisted}}\n')
        for p in e['paths']:
            if not (ROOT / p).exists():
                raise FileNotFoundError(p)
        appendix_d.append('关键记录：' + '；'.join(f'[{p.removeprefix("v2/evidence/")}]({link(p)})' for p in e['paths']) + '。\n')
        for p in historical[key]:
            appendix_d.append(f'[{p.removeprefix("evidence/")}]({link("v2/"+p)})\n')
    appendix_d.append('</div>')
    (BUILD / '93-evidence.md').write_text('\n\n'.join(appendix_d), encoding='utf-8')

    refs = ['# 附录 E　技术来源与真实性说明 {#references .unnumbered}',
        '框架机制使用官方资料交叉核对；动态文档访问日期为2026-11-16，不能替代固定实验版本的源码与历史结果。\n']
    for r in CAT['references']:
        refs.append(f'**{r["id"]}**　[{r["title"]}]({r["url"]})\n')
    refs.append('历史云迁移分析（原核对日期2026-11-10）见[仓库文档]('+link('v2/docs/cloud-migration.md')+')；本版不更新云产品支持或价格结论。\n')
    refs.append('**教学参考。**已阅读全文并逐页审读用户提供的《高中物理·加速度》四页样章，借鉴其情境导入、图像辨析、分步计算与迁移练习；第4、5、10章据此补强了量纲、分母、控制条件与结论边界。参考件识别信息见来源索引，对照评估见仓库 `v2/docs/illustrated/REFERENCE-REVIEW.md`。\n')
    refs.append('**界面素材边界。**真实网页素材集中于Grafana/Tempo；GitLab状态锁、漂移与考核素材是终端记录，不是网页。\n')
    refs.append('**已收紧的历史表述。**Outbox不保证任意副作用恰好一次；notifier的检查与标记非原子；支付自动对账尚未实现；RetryBudget有10令牌初始突发；同步复制零丢失仅指特定运行；归档超时不构成无条件RPO上限。旧章节与证据保持原样。\n')
    refs.append('**仍未验证。**第三方独立复现、真实多可用区容量、长期运行、未知考生的排查能力、P1真实长时密封演练、当前运行环境健康、虚拟机外密钥的恢复能力均不由本次出版建立。\n')
    (BUILD / '94-references.md').write_text('\n\n'.join(refs), encoding='utf-8')

    # Existing figure registry already records the measurements behind reused charts.
    import figures as legacy_figures
    import figreg
    legacy_registry = {f['name']+'.svg':f for f in figreg.FIGS}
    index_md.append('\n## 图表与机制源文件\n')
    for name, f in used_figs.items():
        reg = legacy_registry.get(name, {})
        f['evidence_sources'] = reg.get('sources', [])
        f['classification'] = reg.get('kind','ILLUSTRATIVE')
        index_md.append(f'### {name}\n\n{f["kind"]}；{f["caption"]}\n\n源：`{f["path"]}`；SHA-256 `{f["sha256"]}`。\n\n历史数据源：'+str(f['evidence_sources'])+'。新增图的机制依据见 illustrations.py 与相邻代码节选。\n')
        if 'derived_from' in f:
            index_md.append(f'本版教学修订源于 `{f["derived_from"]}`，原图 SHA-256 `{f["original_sha256"]}`。原图保持不变；文字更正：'+json.dumps(f.get('label_changes',{}),ensure_ascii=False)+'；重绘说明：'+json.dumps(f.get('redraw',{}),ensure_ascii=False)+'。\n')
    design_ref = CAT['design_reference']
    index_md.append(f'\n## 教学设计参考\n\n{design_ref["title"]}，文件 `{design_ref["file_name"]}`，{design_ref["pages"]}页。{design_ref["role"]}。审读日期：{design_ref["reviewed_on"]}；完整原文件SHA-256 `{design_ref["sha256"]}`。\n\n对照评估：`{design_ref["review"]}`。该样章不是工程运行证据。\n')
    (HERE / 'SOURCES.md').write_text('\n'.join(index_md), encoding='utf-8')
    provenance = {'baseline':BASE,'chapters':len(body_chapters),'codes':used_codes,'shots':used_shots,'figures':used_figs,
                  'historical_evidence':historical,'references':CAT['references'],'design_reference':design_ref}
    (HERE / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    print(f'SOURCE CHECK PASS: {len(body_chapters)} chapters, {len(used_codes)} exact excerpts, {len(used_figs)} diagrams/charts, {len(used_shots)} source captures, {sum(map(len,historical.values()))} historical evidence entries')
    if args.sources_only:
        return 0
    cmd = [sys.executable,str(ROOT/'manual/tools/build.py'),'--chapters',str(BUILD/'*.md'),
           '--template',str(HERE/'template.html'),'--metadata',str(HERE/'metadata.yaml'),
           '--math','mathml','--toc-depth','2','--lua-filter',str(MAN/'pub/codebreak.lua'),
           '--out',str(args.out),'--subject','Source-grounded Chinese engineering textbook, all 13 chapters, Illustrated Edition',
           '--keywords','DevOps, SRE, storefront, Saga, Outbox, Kubernetes, GitOps, observability']
    subprocess.run(cmd,check=True,cwd=ROOT)
    writer = PdfWriter(clone_from=str(args.out))
    writer.add_metadata({'/Author':'Weilai Wang / miku-wwl; teaching reconstruction and publication with Codex','/Creator':'DevOps Delivery Illustrated Edition build.py'})
    with args.out.open('wb') as f:
        writer.write(f)
    reader = PdfReader(str(args.out))
    print(f'FINAL: {len(reader.pages)} searchable A4 pages; {args.out}; sha256={sha(args.out.read_bytes())}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
