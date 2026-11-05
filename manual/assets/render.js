// Runs inside the manual HTML before printing: render Mermaid diagrams, wait for
// images and fonts, then flag the document as ready for the PDF printer.
(async () => {
  // Colour prompts ("$ cmd", continuation lines), "[exit N]" and comments in ```console blocks.
  document.querySelectorAll('pre.console > code').forEach((code) => {
    if (code.querySelector('span')) return;
    const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    let continuation = false;
    code.innerHTML = code.textContent.split('\n').map((line) => {
      let cls = '';
      if (continuation || line.startsWith('$ ')) {
        cls = 'prompt';
        continuation = line.endsWith('\\');
      } else if (/^\[exit \d+\]$/.test(line)) {
        cls = 'exit';
      } else if (line.startsWith('# ')) {
        cls = 'comment';
      }
      return cls ? `<span class="${cls}">${escape(line)}</span>` : escape(line);
    }).join('\n');
  });
  try {
    mermaid.initialize({
      startOnLoad: false,
      theme: 'neutral',
      securityLevel: 'strict',
      fontFamily: '"Microsoft YaHei", "Noto Sans SC", sans-serif',
      flowchart: { curve: 'basis', useMaxWidth: true },
      sequence: { useMaxWidth: true, mirrorActors: false },
    });
    await mermaid.run({ querySelector: 'pre.mermaid' });
  } catch (e) {
    document.body.dataset.mermaidError = String(e && e.message ? e.message : e);
  }
  const pending = Array.from(document.images)
    .filter((img) => !img.complete)
    .map((img) => new Promise((resolve) => { img.onload = img.onerror = resolve; }));
  await Promise.all(pending);
  const broken = Array.from(document.images).filter((img) => img.naturalWidth === 0).map((img) => img.getAttribute('src'));
  if (broken.length) document.body.dataset.brokenImages = JSON.stringify(broken);
  await document.fonts.ready;
  // Leader dots for the table of contents; the page number goes into data-page.
  document.querySelectorAll('#TOC a').forEach((a) => {
    if (!a.querySelector('.fill')) {
      const fill = document.createElement('span');
      fill.className = 'fill';
      a.appendChild(fill);
    }
  });
  document.body.dataset.ready = '1';
})();
