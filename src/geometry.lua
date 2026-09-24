local M = {}

local function value(config, name, fallback)
  local current = config[name]
  if current == nil then return fallback end
  return current
end

function M.layout(config)
  local n = config.size
  local elevation = config.elevation
  local diamondHeight = n / 2
  local alignment = value(config, "alignment", "center")
  local offsetX = value(config, "offsetX", 0)
  local offsetY = value(config, "offsetY", 0)
  local top = (alignment == "top" and 0 or math.floor(n / 4)) + offsetY
  local baseHeight = config.sizingMode == "stretch" and n + elevation or n
  local fixed = config.sizingMode == "fixed"
  local content = {
    minX=offsetX, maxX=offsetX + n,
    minY=top, maxY=top + diamondHeight + elevation
  }
  local origin = {
    x=fixed and 0 or math.max(0, -content.minX),
    y=fixed and 0 or math.max(0, -content.minY)
  }
  local right = fixed and 0 or math.max(0, content.maxX - n)
  local bottom = fixed and 0 or math.max(0, content.maxY - baseHeight)
  return {
    logical={width=n,height=n}, content=content, origin=origin,
    translation={x=offsetX+origin.x,y=top+origin.y},
    cell={
      width=n + origin.x + right,
      height=baseHeight + origin.y + bottom,
      diamondHeight=diamondHeight,
      topY=top + origin.y,
      topBottomY=top + diamondHeight + origin.y,
      wallBottomY=top + diamondHeight + elevation + origin.y
    }
  }
end

function M.toCell(point, layout)
  return {x=point.x + layout.translation.x, y=point.y + layout.translation.y}
end

return M
