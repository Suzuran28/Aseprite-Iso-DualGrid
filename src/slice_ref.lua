-- Slice-layer renderer. Bottom/Top keep the procedurally-generated 2px
-- diamond-ring grid; the SliceBorder / SliceBorderBottom / SliceHeightHint
-- pixels are applied verbatim from docs/references/isometric.aseprite via
-- slice_data.lua, so the generated Guides match the reference file at 64px
-- exactly instead of re-deriving seam geometry from polylines.
return function(load)
  local Atlas = load("src/atlas.lua")
  local Geometry = load("src/geometry.lua")
  local Variants = load("src/variants.lua")
  local SliceData = load("src/slice_data.lua")
  local M = {}

  local colors = {
    bottom={217,87,99,255}, top={172,50,50,255},
    sliceBorderBottom={50,60,57,255}, sliceHeightHint={223,113,38,255},
    sliceBorder={0,0,0,255}
  }

  function M.colors()
    local result = {}
    for name, color in pairs(colors) do
      result[name] = {color[1],color[2],color[3],color[4]}
    end
    return result
  end

  -- 2px-thick isometric diamond ring (the Bottom/Top grid). Top vertex is
  -- four pixels centered on x = size/2; each row steps 2px outward (2:1
  -- slope) for size/4 rows, then mirrors. Local y=0 is the top vertex.
  local function diamondOutline(size)
    local half = size / 2
    local quarter = math.floor(size / 4)
    local points = {}
    local function add(x, y)
      x, y = math.floor(x), math.floor(y)
      if x >= 0 and x < size then points[#points + 1] = {x=x, y=y} end
    end
    for dy = 0, quarter - 1 do
      local left = (half - 2) - 2 * dy
      local right = half + 2 * dy
      add(left, dy) add(left + 1, dy) add(right, dy) add(right + 1, dy)
    end
    for dy = 0, half - quarter - 1 do
      local left = 2 * dy
      local right = (size - 2) - 2 * dy
      local y = quarter + dy
      add(left, y) add(left + 1, y) add(right, y) add(right + 1, y)
    end
    return points
  end

  local function newLayers()
    local layers, seen = {}, {}
    for name, color in pairs(colors) do
      layers[name] = {color={color[1],color[2],color[3],color[4]}, points={}}
      seen[name] = {}
    end
    return layers, seen
  end

  local function makeEmit(layers, seen, width, height)
    return function(name, x, y)
      if x < 0 or y < 0 or x >= width or y >= height then return end
      local key = y * width + x
      if not seen[name][key] then
        seen[name][key] = true
        local points = layers[name].points
        points[#points + 1] = {x=x, y=y}
      end
    end
  end

  -- slice_data coordinates are authored for 64px, E=16, alignment=top
  -- (topY=0). Scale them to the requested size and shift by topY/baseY.
  local function scaleCoord(v, n)
    return math.floor(v * n / 64 + 0.5)
  end

  local function emitScaledPixels(emit, name, points, n, xOffset, yOffset)
    for _, p in ipairs(points) do
      local x, y = scaleCoord(p[1],n), scaleCoord(p[2],n)
      if n > 64 then
        local right = scaleCoord(p[1]+1,n)-1
        local bottom = scaleCoord(p[2]+1,n)-1
        for targetX = x, right do
          for targetY = y, bottom do
            emit(name,targetX+xOffset,targetY+yOffset)
          end
        end
      else
        emit(name,x+xOffset,y+yOffset)
      end
    end
  end

  function M.tile(config, variant)
    local n = config.size
    local layout = Geometry.layout(config)
    local cell = layout.cell
    local layers, seen = newLayers()
    local emit = makeEmit(layers, seen, cell.width, cell.height)

    local leftX = layout.translation.x
    local topY = cell.topY
    local baseY = cell.topY + config.elevation
    local outline = diamondOutline(n)

    -- Bottom/Top grid: 2px diamond ring on the floor and ceiling.
    for _, p in ipairs(outline) do
      emit("top", p.x + leftX, p.y + topY)
      emit("bottom", p.x + leftX, p.y + baseY)
    end

    -- SliceBorder: the seam polyline on the top surface, verbatim from
    -- the reference file (scaled to n). Drawn at every elevation — the
    -- reference's top border is independent of wall height.
    local idx = variant.index
    local border = SliceData.border[idx] or {}
    emitScaledPixels(emit,"sliceBorder",border,n,leftX,topY)

    if config.elevation > 0 then
      local borderBottom = SliceData.borderBottom[idx] or {}
      local E = config.elevation

      -- SliceBorderBottom: the same polyline projected onto the floor.
      -- At the reference resolution (64px, E=16) use the extracted pixels
      -- directly; otherwise shift the top border down by E.
      if n == 64 and E == 16 then
        for _, p in ipairs(borderBottom) do
          emit("sliceBorderBottom", p[1] + leftX, p[2] + topY)
        end
      else
        emitScaledPixels(emit,"sliceBorderBottom",border,n,leftX,baseY)
      end

      -- SliceHeightHint: vertical orange lines connecting the top border
      -- down to the floor border. slice_data encodes the exact hint pixels
      -- per mask at 64px/E=16; for other sizes/elevations we use separate
      -- vertical runs (x, yTop, yBottom) and move each lower endpoint with E.
      if n == 64 and E == 16 then
        local hint = SliceData.hint[idx] or {}
        for _, p in ipairs(hint) do
          emit("sliceHeightHint", p[1] + leftX, p[2] + topY)
        end
      else
        local hints = SliceData.hintColumns[idx] or {}
        for _, c in ipairs(hints) do
          local cx = scaleCoord(c[1], n)
          local rightX = n > 64 and scaleCoord(c[1]+1,n)-1 or cx
          local cyTop = scaleCoord(c[2], n)
          local cyBottom = scaleCoord(c[3], n)
          -- Keep the top endpoint fixed and move the lower endpoint by the
          -- change in elevation. Scaling the whole span rounds a shortened
          -- 15-pixel hint to eight pixels at E=8, leaving its last pixel one
          -- row below the projected floor border.
          local referenceElevation = scaleCoord(16, n)
          local span = math.max(1,
            cyBottom - cyTop + 1 + E - referenceElevation)
          for h = 0, span - 1 do
            for x = cx, rightX do
              emit("sliceHeightHint", x + leftX, cyTop + h + topY)
            end
          end
        end
      end
    end

    return layers
  end

  function M.atlas(config)
    local sheet = Atlas.sheet(config)
    local layers, seen = newLayers()
    local emit = makeEmit(layers, seen, sheet.width, sheet.height)
    for _, variant in ipairs(Variants.all()) do
      local origin = Atlas.origin(variant.index, sheet)
      local tile = M.tile(config, variant)
      for name in pairs(colors) do
        for _, p in ipairs(tile[name].points) do
          emit(name, p.x + origin.x, p.y + origin.y)
        end
      end
    end
    return layers
  end

  return M
end
