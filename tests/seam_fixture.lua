-- Shared test-owned fixture definition. Never generates or updates the golden.
local M = {}

function M.render(load)
  local Raster = load("src/raster.lua")
  local Variants = load("src/variants.lua")
  local config = {
    size=64, elevation=16, sizingMode="fixed", layout="row",
    previewMode="extruded"
  }
  local layers = Raster.tile(config,Variants.build(10))
  local image = Image(64,64,ColorMode.RGB)
  image:clear()
  -- Explicit bottom-to-top order; labels are excluded from the canonical tile.
  for _, name in ipairs({"grid","seams","ground","height"}) do
    local layer = layers[name]
    local color = app.pixelColor.rgba(table.unpack(layer.color))
    for _, p in ipairs(layer.points) do image:drawPixel(p.x,p.y,color) end
  end
  return image
end

return M
