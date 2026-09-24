return function(load)
  local Atlas = load("src/atlas.lua")
  local Geometry = load("src/geometry.lua")
  local Variants = load("src/variants.lua")
  local Font = load("src/font.lua")
  local M = {}

  local layerNames = {"grid","seams","ground","height","labels"}
  local colors = {
    grid={255,82,102,255}, seams={76,128,255,255},
    ground={238,112,35,255}, height={238,112,35,255}, labels={255,255,255,255}
  }

  local function scale(value, size)
    return math.floor(value * size / 64 + 0.5)
  end

  function M.scalePoint(point, size)
    return {x=scale(point.x,size),y=scale(point.y,size)}
  end

  function M.line8(a, b)
    local points = {}
    local x0, y0, x1, y1 = a.x, a.y, b.x, b.y
    local dx = math.abs(x1 - x0)
    local sx = x0 < x1 and 1 or -1
    local dy = -math.abs(y1 - y0)
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
      points[#points + 1] = {x=x0, y=y0}
      if x0 == x1 and y0 == y1 then break end
      local twice = 2 * err
      if twice >= dy then err, x0 = err + dy, x0 + sx end
      if twice <= dx then err, y0 = err + dx, y0 + sy end
    end
    return points
  end

  local function equalPoint(a,b)
    return a.x == b.x and a.y == b.y
  end

  function M.path(points, size)
    local vertices = {}
    for _, point in ipairs(points) do
      local scaled = M.scalePoint(point,size)
      if #vertices == 0 or not equalPoint(vertices[#vertices],scaled) then
        vertices[#vertices+1] = scaled
      end
    end
    if #vertices < 2 then return vertices end
    local result = {}
    for i = 2, #vertices do
      local segment = M.line8(vertices[i-1],vertices[i])
      for j = (i == 2 and 1 or 2), #segment do
        result[#result+1] = segment[j]
      end
    end
    return result
  end

  -- Stable de-duplication and local clipping happen at the emission boundary.
  -- Each call owns its point/color records; no caller can mutate later renders.
  local function layersFor(width,height)
    local layers, seen = {}, {}
    for _, name in ipairs(layerNames) do
      local color = colors[name]
      layers[name] = {color={color[1],color[2],color[3],color[4]},points={}}
      seen[name] = {}
    end
    local function emit(name,x,y)
      if x < 0 or y < 0 or x >= width or y >= height then return end
      local key = y*width+x
      if not seen[name][key] then
        seen[name][key] = true
        local points = layers[name].points
        points[#points+1] = {x=x,y=y}
      end
    end
    return layers,emit
  end

  local diamond = {
    {x=32,y=0},{x=64,y=16},{x=32,y=32},{x=0,y=16},{x=32,y=0}
  }

  function M.tile(config, variant)
    local cell = Atlas.cell(config)
    local layout = Geometry.layout(config)
    local layers,emit = layersFor(cell.width,cell.height)
    local function emitCanonical(name, point, yOffset)
      local translated = Geometry.toCell({x=point.x,y=point.y+(yOffset or 0)},layout)
      emit(name,translated.x,translated.y)
    end
    for _, p in ipairs(M.path(diamond,config.size)) do
      emitCanonical("grid",p)
    end
    if config.elevation > 0 then
      for _, p in ipairs(M.path(diamond,config.size)) do
        emitCanonical("ground",p,config.elevation)
      end
    end

    for _, path in ipairs(variant.paths) do
      if config.elevation > 0 then
        local selected = variant.inverted and path.wallEdges.inverted or path.wallEdges.normal
        local runStart,runEnd
        local function connector(p)
          for y = p.y, p.y+config.elevation do
            emitCanonical("height",{x=p.x,y=y})
          end
        end
        local function finishRun()
          if runStart then
            connector(runStart)
            connector(runEnd)
            runStart,runEnd = nil,nil
          end
        end
        -- Keep source segment indices until after the edge mask is applied.
        -- Collapsed selected segments cannot begin a run on their own.
        for i = 1, #path.points-1 do
          local a = M.scalePoint(path.points[i],config.size)
          local b = M.scalePoint(path.points[i+1],config.size)
          if selected[i] then
            if not equalPoint(a,b) then
              runStart,runEnd = runStart or a,b
              for _, p in ipairs(M.line8(a,b)) do
                emitCanonical("height",p,config.elevation)
              end
            end
          else
            finishRun()
          end
        end
        finishRun()
      end
    end

    Font.draw(variant.label,1,1,function(x,y)
      emitCanonical("labels",{x=x,y=y})
    end)
    return layers
  end

  function M.atlas(config)
    local sheet = Atlas.sheet(config)
    local layers,emit = layersFor(sheet.width,sheet.height)
    for _, variant in ipairs(Variants.all()) do
      local origin = Atlas.origin(variant.index,sheet)
      local tile = M.tile(config,variant)
      for _, name in ipairs(layerNames) do
        for _, p in ipairs(tile[name].points) do
          emit(name,p.x+origin.x,p.y+origin.y)
        end
      end
    end
    return layers
  end

  return M
end
