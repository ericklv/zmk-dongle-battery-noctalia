--!nonstrict
-- Popout: device chips, refresh button and the outline of each half with its level.
-- ui.* has no canvas, so each outline is written as an SVG named by its content hash and shown with ui.image.

local shapes = require("./shapes.luau")

local LOW_LEVEL = 20
local HALF_WIDTH = 160

local status = noctalia.state.get("zmk") or { sides = {}, devices = {}, error = "reading..." }
local isOpen = false
local closeButton = true
local svgDir = (noctalia.pluginDataDir() or "/tmp") .. "/svg"
local shownSvgs = {}

local function send(action, device)
  noctalia.state.set("zmk.cmd", { id = noctalia.nowMs(), action = action, device = device })
end

local function shapeFor(name)
  local key = string.gsub(string.lower(name or ""), "[^a-z0-9]", "")
  for k, shape in pairs(shapes) do
    if string.find(key, k, 1, true) then
      return shape
    end
  end
  return shapes.corne
end

local function levelOf(label)
  for _, side in ipairs(status.sides or {}) do
    if side.label == label then
      return side.level
    end
  end
  return -1
end

local function xmlEscape(s)
  return (string.gsub(s, "[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

local function hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + string.byte(s, i)) % 4294967296
  end
  return string.format("%08x", h)
end

local function fmt(n)
  return string.format("%.1f", n)
end

-- Closed outline with corners rounded by quadratic curves, each radius capped at half of its shorter edge
local function outlinePath(pts, radius)
  local n = #pts
  local function dist(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
  end
  local function toward(from, to, d)
    local len = dist(from, to)
    if len == 0 then
      return from
    end
    return { from[1] + (to[1] - from[1]) * d / len, from[2] + (to[2] - from[2]) * d / len }
  end
  local first, last = pts[1], pts[n]
  local parts = { `M{fmt((first[1] + last[1]) / 2)},{fmt((first[2] + last[2]) / 2)}` }
  for i = 1, n do
    local prev, cur, nxt = pts[(i - 2) % n + 1], pts[i], pts[i % n + 1]
    local r = math.min(radius, dist(prev, cur) / 2, dist(cur, nxt) / 2)
    local a, b = toward(cur, prev, r), toward(cur, nxt, r)
    table.insert(parts, `L{fmt(a[1])},{fmt(a[2])}Q{fmt(cur[1])},{fmt(cur[2])} {fmt(b[1])},{fmt(b[2])}`)
  end
  table.insert(parts, "Z")
  return table.concat(parts, "")
end

local function halfSvg(shape, mirrored, label, level, dimmed)
  local W = 1000
  local H = W * shape.aspect
  local pad = 12.5
  local s = W - pad * 2
  local outline = mirrored and shape.right or shape.left
  local thick = mirrored and shape.thick.right or shape.thick.left
  local known = level >= 0
  local low = known and level <= LOW_LEVEL

  local pts = {}
  for _, p in ipairs(outline) do
    table.insert(pts, { pad + p[1] * s, pad + p[2] * s })
  end
  local d = outlinePath(pts, 0.03 * s)

  local color = function(role, fallback)
    return noctalia.getColor(role) or fallback
  end
  local fill = color("surface_container_high", "#2b2b2b")
  local stroke = low and color("error", "#ff5555") or color("outline_variant", "#777777")
  local text = low and color("error", "#ff5555") or color("on_surface", "#eeeeee")
  local muted = color("on_surface_variant", "#aaaaaa")
  local font = xmlEscape(tostring(noctalia.getSetting("shell.font_family") or "sans-serif"))
  local cx, cy = thick[1] * W, thick[2] * W
  local levelText = known and (tostring(level) .. "%") or "--"

  local tint = low and `<path d="{d}" fill="{color("error", "#ff5555")}" fill-opacity="0.3"/>` or ""
  return table.concat({
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {fmt(H)}" width="{W}" height="{fmt(H)}">`,
    `<g opacity="{(dimmed or not known) and 0.6 or 1}">`,
    `<path d="{d}" fill="{fill}"/>{tint}`,
    `<path d="{d}" fill="none" stroke="{stroke}" stroke-width="12.5" stroke-linejoin="round"/>`,
    `</g>`,
    `<text x="{fmt(cx)}" y="{fmt(cy + 4)}" text-anchor="middle" font-family="{font}" font-weight="bold" font-size="150" fill="{text}">{levelText}</text>`,
    `<text x="{fmt(cx)}" y="{fmt(cy + 104)}" text-anchor="middle" font-family="{font}" font-size="75" fill="{muted}">{xmlEscape(label)}</text>`,
    `</svg>`,
  }, "")
end

local function halfImage(shape, mirrored, label, level, dimmed)
  local svg = halfSvg(shape, mirrored, label, level, dimmed)
  local file = `{hash(svg)}.svg`
  local path = `{svgDir}/{file}`
  if not noctalia.fileExists(path) then
    noctalia.mkdirAll(svgDir)
    noctalia.writeFile(path, svg)
  end
  shownSvgs[file] = true
  return ui.image({
    key = label,
    path = path,
    width = HALF_WIDTH,
    height = math.floor(HALF_WIDTH * shape.aspect + 0.5),
    fit = "contain",
  })
end

-- Drops outlines from older states or themes
local function pruneSvgs()
  local files = noctalia.listDir(svgDir)
  for _, file in ipairs(files or {}) do
    if string.sub(file, -4) == ".svg" and not shownSvgs[file] then
      noctalia.removeFile(`{svgDir}/{file}`)
    end
  end
end

local function details()
  if status.reading then
    return "Reading the dongle..."
  elseif (status.error or "") ~= "" then
    return status.error
  elseif (status.updatedAt or 0) > 0 then
    return "Updated " .. noctalia.formatTime(noctalia.timeFormat(), status.updatedAt)
  end
  return ""
end

local function render()
  shownSvgs = {}
  local reading = status.reading == true
  local dimmed = (status.error or "") ~= ""
  local shape = shapeFor(status.name)

  local header = {
    ui.label({ text = status.name ~= "" and status.name or "Keyboard", fontSize = 16, fontWeight = "bold", flexGrow = 1, maxLines = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", tooltip = "Read again", enabled = not reading, onClick = function() send("refresh") end }),
  }
  if closeButton then
    table.insert(header, ui.button({ glyph = "x", variant = "ghost", onClick = function() panel.close() end }))
  end

  local body = {
    ui.column({ gap = 2 }, {
      ui.row({ align = "center", gap = 4 }, header),
      ui.label({ text = details(), color = "on_surface_variant", maxLines = 2 }),
    }),
  }

  -- Only shown when more than one ZMK keyboard with Studio is plugged in
  local devices = status.devices or {}
  if #devices > 1 then
    local active = (status.selected or "") ~= "" and status.selected or status.name
    local chips = {}
    for _, name in ipairs(devices) do
      table.insert(chips, ui.button({
        key = name,
        text = name,
        controlSize = "sm",
        variant = name == active and "primary" or "outline",
        enabled = not reading,
        onClick = function() send("select", name) end,
      }))
    end
    table.insert(body, ui.row({ gap = 6, align = "center" }, chips))
  end

  table.insert(body, ui.row({ gap = 16, align = "center", justify = "center", paddingV = 8 }, {
    halfImage(shape, false, "Left", levelOf("L"), dimmed),
    halfImage(shape, true, "Right", levelOf("R"), dimmed),
  }))

  panel.render(ui.column({ gap = 12 }, body))
end

noctalia.state.watch("zmk", function(value)
  status = value or status
  if isOpen then
    render()
  end
end)

function onOpen(_context)
  isOpen = true
  closeButton = noctalia.getSetting("shell.show_close_buttons") ~= false
  send("refresh")
  render()
  pruneSvgs()
end

function onClose()
  isOpen = false
end
