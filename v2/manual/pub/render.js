// Publication Edition of volume 2: manual/assets/render.js with the book's own Mermaid theme (one palette for
// every diagram). Runs inside the HTML before printing: render Mermaid, wait for images and fonts, flag ready.
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
      theme: 'base',
      securityLevel: 'strict',
      fontFamily: '"Microsoft YaHei", "Noto Sans SC", sans-serif',
      fontSize: 13,
      themeVariables: {
        fontSize: '13px', textColor: '#1b2430', lineColor: '#5b6776', titleColor: '#1b2430',
        primaryColor: '#eaf2fb', primaryBorderColor: '#5b93cf', primaryTextColor: '#1b2430',
        secondaryColor: '#e8f5f2', secondaryBorderColor: '#0f8a7e', secondaryTextColor: '#1b2430',
        tertiaryColor: '#f7f9fc', tertiaryBorderColor: '#b9c6d4', tertiaryTextColor: '#1b2430',
        mainBkg: '#eaf2fb', nodeBorder: '#5b93cf', clusterBkg: '#f7f9fc', clusterBorder: '#b9c6d4',
        edgeLabelBackground: '#ffffff',
        actorBkg: '#eaf2fb', actorBorder: '#5b93cf', actorTextColor: '#1b2430', actorLineColor: '#9aa5b1',
        signalColor: '#3a4553', signalTextColor: '#1b2430', labelBoxBkgColor: '#f7f9fc', labelBoxBorderColor: '#b9c6d4',
        labelTextColor: '#1b2430', loopTextColor: '#1b2430', noteBkgColor: '#fff8e1', noteBorderColor: '#e0b84c',
        noteTextColor: '#4a3b00', activationBkgColor: '#d7e7f8', activationBorderColor: '#5b93cf',
        sectionBkgColor: '#f7f9fc', altSectionBkgColor: '#ffffff', gridColor: '#d5dde6',
        taskBkgColor: '#5b93cf', taskBorderColor: '#3d7cc9', taskTextColor: '#ffffff', taskTextDarkColor: '#1b2430',
        taskTextOutsideColor: '#1b2430', activeTaskBkgColor: '#0f8a7e', activeTaskBorderColor: '#0b6b62',
        doneTaskBkgColor: '#b9c6d4', doneTaskBorderColor: '#8a94a3', critBkgColor: '#d9534f', critBorderColor: '#b52b27',
        todayLineColor: 'transparent',
      },
      // Natural size: small diagrams are not blown up to the full column width (which
      // made tall diagrams fill a whole page); wide ones are scaled down by the CSS
      // max-width in manual.css.
      flowchart: { curve: 'basis', useMaxWidth: false },
      sequence: { useMaxWidth: false, mirrorActors: false },
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
