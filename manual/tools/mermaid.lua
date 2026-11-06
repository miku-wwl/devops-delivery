-- Pandoc Lua filter: turn ```mermaid fenced code blocks into <pre class="mermaid">
-- so Mermaid.js can render them in the browser before the PDF is printed.
-- Optional caption:  ```{.mermaid caption="交付流水线总览"}
-- Extra classes are copied to the figure, e.g. ```{.mermaid .tall} allows a taller diagram.
local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function CodeBlock(el)
  if not el.classes:includes("mermaid") then
    return nil
  end
  local classes = { "diagram" }
  for _, c in ipairs(el.classes) do
    if c ~= "mermaid" then table.insert(classes, c) end
  end
  local html = '<figure class="' .. table.concat(classes, " ") .. '"><pre class="mermaid">' .. esc(el.text) .. '</pre>'
  local caption = el.attributes["caption"]
  if caption and caption ~= "" then
    html = html .. "<figcaption>" .. esc(caption) .. "</figcaption>"
  end
  return pandoc.RawBlock("html", html .. "</figure>")
end
