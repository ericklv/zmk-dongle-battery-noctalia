--!nonstrict
-- Bar widget: "L 87% R 92%", red at or below LOW_LEVEL, dimmed while the last read failed. Click opens the panel.

local LOW_LEVEL = 20
local PANEL_ID = "eleve/zmk_dongle_stats:panel"

local status = noctalia.state.get("zmk") or { sides = {}, error = "reading..." }

local function tooltip()
  local rows = { { "Keyboard", status.name ~= "" and status.name or "--" } }
  for _, side in ipairs(status.sides or {}) do
    table.insert(rows, { side.label, `{side.level}%` })
  end
  if status.reading then
    table.insert(rows, { "Status", "Reading the dongle..." })
  elseif status.error ~= "" then
    table.insert(rows, { "Error", status.error })
  elseif (status.updatedAt or 0) > 0 then
    table.insert(rows, { "Updated", noctalia.formatTime(noctalia.timeFormat(), status.updatedAt) })
  end
  return rows
end

local function render()
  local vertical = barWidget.isVertical()
  local sides = status.sides or {}
  local stale = status.error ~= ""
  local children = {
    ui.glyph({ name = "keyboard", color = if #sides > 0 then nil else "on_surface_variant" }),
  }

  if #sides == 0 then
    table.insert(children, ui.label({ text = "--", color = "on_surface_variant" }))
  end
  for _, side in ipairs(sides) do
    table.insert(children, ui.label({
      key = `side-{side.source}`,
      text = vertical and `{side.label}{side.level}` or `{side.label} {side.level}%`,
      color = side.level <= LOW_LEVEL and "error" or nil,
      opacity = stale and 0.6 or 1.0,
    }))
  end

  local container = vertical and ui.column or ui.row
  barWidget.render(container({ gap = vertical and 0 or 6, align = "center" }, children))
  barWidget.setTooltip(tooltip())
end

noctalia.state.watch("zmk", function(value)
  status = value or status
  render()
end)

function update()
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

render()
