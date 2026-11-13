-- Publication Edition: let long inline code (paths, flags, metric names) break after a separator.
-- Without a break opportunity a long path jumps to the next line as one word and the justified line before
-- it is stretched (review round 1, finding F-06). <wbr> adds opportunities after / . _ - = : , and, since
-- round 2, between the words of a camelCase identifier (AlertmanagerClusterCrashlooping).
local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function Code(el)
  if #el.text < 14 then
    return nil
  end
  local html = esc(el.text):gsub("(%l)(%u)", "%1<wbr>%2"):gsub("([/._=:,%-])", "%1<wbr>")
  return pandoc.RawInline("html", "<code>" .. html .. "</code>")
end
