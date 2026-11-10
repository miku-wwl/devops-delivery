# E12: page-by-page review of the final PDF

File: `v2/manual/dist/Enterprise-Platform-SRE-Simulation-Vol2.pdf` - 172 PDF pages (cover + 171 numbered
pages), 13 chapters, built 2026-11-10 with `manual/tools/build.py --chapters "v2/manual/chapters/*.md"
--metadata v2/manual/metadata.yaml --math mathml`.

Method: every page tiled onto contact sheets (`manual/tools/contact_sheet.py`, 12 pages per sheet, 15
sheets) and looked at; pages with a finding rendered at full size (`manual/tools/pdf2png.py`). Looked for:
text or tables past the margin, cut or broken figures, unreadable diagrams, orphaned headings and boxes,
blank or near-empty pages, wrong cover or headers. Automatic checks next to it: `layout_check.py`
(margins, gaps, blank pages) and `verify_evidence.py --root v2` (images, evidence paths, secrets,
exercises, 572 spot checks of the text against the evidence).

| Pages | Content | Result |
|---|---|---|
| 1 | cover | flow line of volume 1 ("... Scan → Sign ...", no signing in volume 2) - **fixed**: the template takes the line from the metadata, volume 1's default unchanged (checked: volume 1's HTML still renders its line) |
| 2-8 | table of contents | complete, chapters 1-13, page numbers filled |
| 9-19 | chapter 1 (E0) | ok; 19 is the short end of the chapter |
| 20-35 | chapter 2 (E1) | p24: the diagram "services and data" small (left-to-right over 7 levels) - **fixed**: top-to-bottom; 35 short end of the chapter |
| 36-51 | chapter 3 (E2) | ok; p41 the reviewed gap (55 % used, the full-page Grafana figure follows) - accepted, `v2/manual/layout-accepted-gaps.txt` |
| 52-68 | chapter 4 (E3) | ok; 68 short end |
| 69-84 | chapter 5 (E4) | ok; 84 short end |
| 85-96 | chapter 6 (E5) | ok; the limitation note on the single unseal key now points to incident E11-1 |
| 97-106 | chapter 7 (E6) | ok; 106 short end |
| 107-118 | chapter 8 (E7) | ok; the limitation note on key custody now points to incident E11-1 |
| 119-134 | chapter 9 (E8) | ok |
| 135-145 | chapter 10 (E9) | ok |
| 146-158 | chapter 11 (E10) | figures 11-1 to 11-5 readable (architecture, two xy charts, terminal image, memory chart); p157: the exercise box began at the foot of the page with only its label - **fixed** with a page break before the exercises (volume 2 only) |
| 159-168 | chapter 12 (E11) | figures 12-1 to 12-5 readable (two diagrams after shortening the labels, three terminal images); tables ok |
| 169-172 | chapter 13 (E12) | tables and the terminal image of T3 readable |

After the fixes: `layout_check.py` PASS (one accepted gap, page 41; no overflow, no blank page),
`verify_evidence.py --root v2` PASS (572 spot checks, 15 images, 238 evidence paths, 836 secret scans,
82 exercises); the pages of every fix looked at again at full size.

Not done in this review: reading every sentence again for language (the text was reviewed chapter by
chapter when each phase was written); the figures of chapters 1-10 are those accepted in their phases.
