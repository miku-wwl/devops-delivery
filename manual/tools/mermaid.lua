-- Pandoc Lua filter: turn ```mermaid fenced code blocks into <pre class="mermaid">
-- so Mermaid.js can render them in the browser before the PDF is printed.
-- Optional caption:  ```{.mermaid caption="交付流水线总览"}
local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function CodeBlock(el)
  if not el.classes:includes("mermaid") then
    return nil
  end
  local html = '<figure class="diagram"><pre class="mermaid">' .. esc(el.text) .. '</pre>'
  local caption = el.attributes["caption"]
  if caption and caption ~= "" then
    html = html .. "<figcaption>" .. esc(caption) .. "</figcaption>"
  end
  return pandoc.RawBlock("html", html .. "</figure>")
end
