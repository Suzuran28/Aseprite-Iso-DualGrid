return function(load)
  local source = debug.getinfo(1,"S").source
  local file = source:sub(1,1) == "@" and source:sub(2) or source
  local ROOT = app.fs.filePath(app.fs.filePath(file))
  local Atlas = load("src/atlas.lua")
  local Variants = load("src/variants.lua")
  local SliceRef = load("src/slice_ref.lua")
  local Model = load("src/model.lua")
  local M = {}

  local sceneMasks = {
    {3,7,11,15},
    {2,6,10,14},
    {1,5,9,13},
    {0,4,8,12}
  }

  function M.maskAt(x, y)
    assert(x >= 0 and x < 4 and y >= 0 and y < 4)
    return sceneMasks[y + 1][x + 1]
  end

  local function normalizeWithBorder(records, border)
    local minX, minY = math.huge, math.huge
    for _, record in ipairs(records) do
      minX, minY = math.min(minX, record.x), math.min(minY, record.y)
    end
    for _, record in ipairs(records) do
      record.x = record.x - minX + border
      record.y = record.y - minY + border
    end
    return records
  end

  function M.placements(config, mode)
    local result = {}
    for y = 0, 3 do
      for x = 0, 3 do
        result[#result + 1] = {
          mask=M.maskAt(x, y),
          gridX=x,
          gridY=y,
          x=(x-y)*config.size/2,
          y=math.floor((x+y)*config.size/4+0.5),
          depth=x+y
        }
      end
    end
    table.sort(result, function(a, b)
      if a.depth ~= b.depth then return a.depth < b.depth end
      return a.x < b.x
    end)
    return normalizeWithBorder(result, 0)
  end

  local function rgba(record)
    local color = record.color
    return app.pixelColor.rgba(color[1], color[2], color[3], color[4])
  end

  local function paint(image, record, originX, originY, overrideColor)
    if not record then return end
    local color = overrideColor or rgba(record)
    for _, point in ipairs(record.points) do
      local x, y = originX + point.x, originY + point.y
      if x >= 0 and y >= 0 and x < image.width and y < image.height then
        image:drawPixel(x, y, color)
      end
    end
  end

  function M.render(config, mode)
    -- These two canonical previews are supplied artwork. Use their exact
    -- pixels at 64px; the procedural path below handles other sizes and
    -- elevations.
    if config.size == 64 and (config.offsetX or 0) == 0
        and (config.offsetY or 0) == 0 then
      local filename
      if mode == "top" then
        filename = "preview-top-64.png"
      elseif mode == "extruded" and config.elevation == 16 then
        filename = "preview-extruded-64-e16.png"
      end
      if filename then
        local image = Image{fromFile=app.fs.joinPath(ROOT,"assets",filename)}
        return image, {x=0,y=0,width=image.width,height=image.height}
      end
    end

    local cfg = Model.withValue(config, "alignment", "top")
    if mode == "top" then cfg = Model.withValue(cfg,"elevation",0) end
    local records = M.placements(cfg, mode)
    local cell = Atlas.cell(cfg)

    -- Include the full physical cell so stretch offsets cannot be cropped.
    local minX, minY = math.huge, math.huge
    local maxX, maxY = 0, 0
    for _, record in ipairs(records) do
      minX = math.min(minX, record.x)
      minY = math.min(minY, record.y)
      maxX = math.max(maxX, record.x + cell.width)
      maxY = math.max(maxY, record.y + cell.height)
    end
    local bounds = {x=0, y=0, width=maxX - minX, height=maxY - minY}
    local dx, dy = -minX, -minY
    local image = Image(bounds.width, bounds.height, ColorMode.RGB)
    image:clear()

    -- Build all tiles with shifted positions.
    local tiles = {}
    for _, record in ipairs(records) do
      local variant = Variants.build(record.mask)
      local layers = SliceRef.tile(cfg, variant)
      tiles[record] = {
        x=record.x + dx, y=record.y + dy,
        layers=layers
      }
    end

    local bottomColor = rgba(tiles[records[1]].layers.bottom)

    -- Paint the floor (bottom) outlines, back to front.
    for _, record in ipairs(records) do
      local t = tiles[record]
      paint(image, t.layers.bottom, t.x, t.y)
    end

    if mode ~= "top" then
      -- Keep the upper diamond visible above the floor.
      for _, record in ipairs(records) do
        local t = tiles[record]
        paint(image, t.layers.top, t.x, t.y, bottomColor)
      end
      -- Paint height hints and the seam projected onto the floor.
      for _, record in ipairs(records) do
        local t = tiles[record]
        paint(image, t.layers.sliceHeightHint, t.x, t.y)
      end
      for _, record in ipairs(records) do
        local t = tiles[record]
        paint(image, t.layers.sliceBorderBottom, t.x, t.y,
          rgba(t.layers.sliceBorder))
      end
    end

    -- Paint the top-surface seams last.
    for _, record in ipairs(records) do
      local t = tiles[record]
      paint(image, t.layers.sliceBorder, t.x, t.y)
    end

    return image, bounds
  end

  local function boundsFor(records, cell)
    local maxX, maxY = 0, 0
    for _, record in ipairs(records) do
      maxX = math.max(maxX, record.x + cell.width)
      maxY = math.max(maxY, record.y + cell.height)
    end
    return {x=0,y=0,width=maxX+4,height=maxY+4}
  end

  local function topLevelGroup(sprite, name)
    for _, layer in ipairs(sprite.layers) do
      if layer.isGroup and layer.name == name then return layer end
    end
    return nil
  end

  local function drawCel(canvas, layer)
    local cel = layer:cel(1)
    if not cel then return end
    local opacity = math.floor(layer.opacity * cel.opacity / 255 + 0.5)
    if opacity <= 0 then return end
    if opacity == 255 then
      canvas:drawImage(cel.image,cel.position)
      return
    end
    local faded = Image(cel.image)
    for pixel in faded:pixels() do
      local color = pixel()
      local alpha = app.pixelColor.rgbaA(color)
      if alpha > 0 then
        pixel(app.pixelColor.rgba(
          app.pixelColor.rgbaR(color),
          app.pixelColor.rgbaG(color),
          app.pixelColor.rgbaB(color),
          math.floor(alpha * opacity / 255 + 0.5)))
      end
    end
    canvas:drawImage(faded,cel.position)
  end

  local function drawLayer(canvas, layer, forceVisible)
    if not forceVisible and not layer.isVisible then return end
    if layer.isGroup then
      for _, child in ipairs(layer.layers) do drawLayer(canvas,child,false) end
    else
      drawCel(canvas,layer)
    end
  end

  function M.flattenSource(sprite, includeGuides)
    local guides = topLevelGroup(sprite,"Guides")
    if includeGuides and (not guides or guides.isVisible) then
      return Image(sprite)
    end
    local image = Image(sprite.width,sprite.height,ColorMode.RGB)
    image:clear()
    for _, layer in ipairs(sprite.layers) do
      if layer == guides then
        if includeGuides then drawLayer(image,layer,true) end
      else
        drawLayer(image,layer,false)
      end
    end
    return image
  end

  function M.renderSource(sprite, config, includeGuides)
    local flattened = M.flattenSource(sprite,includeGuides)
    local sheet = Atlas.sheet(config)
    local records = M.placements(config)
    local bounds = boundsFor(records, sheet.cell)
    local image = Image(bounds.width,bounds.height,ColorMode.RGB)
    image:clear()
    for _, record in ipairs(records) do
      local origin = Atlas.origin(record.mask,sheet)
      local cell = Image(flattened,Rectangle(origin.x,origin.y,
        sheet.cell.width,sheet.cell.height))
      image:drawImage(cell,Point(record.x,record.y))
    end
    return image,bounds
  end

  return M
end
