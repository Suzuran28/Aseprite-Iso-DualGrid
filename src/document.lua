return function(load)
  local Atlas = load("src/atlas.lua")
  local Errors = load("src/errors.lua")
  local Model = load("src/model.lua")
  local SliceRef = load("src/slice_ref.lua")
  local M = {}
  local CONFIG_KEY = "isometric-dual-grid.config.v1"

  -- The five Guide layers mirror the Slice group of the reference document
  -- (docs/references/isometric.aseprite): a filled Bottom/Top slice pair,
  -- black SliceBorder / dark SliceBorderBottom outlines, and orange
  -- SliceHeightHint walls. They are genuine layered content, not one flat
  -- composite, so users can toggle each guide on its own.
  local guideLayers = {
    {name="Bottom", slice="bottom", fallback="ground", always=true},
    {name="Top", slice="top", fallback="grid", always=true},
    {name="SliceBorderBottom", slice="sliceBorderBottom", fallback=nil, always=false},
    {name="SliceHeightHint", slice="sliceHeightHint", fallback=nil, always=false},
    {name="SliceBorder", slice="sliceBorder", fallback=nil, always=false}
  }

  local function attachRecord(sprite, layer, record, sheet)
    local image = Image(sheet.width, sheet.height, ColorMode.RGB)
    local color = record.color
    local rgba = app.pixelColor.rgba(color[1], color[2], color[3], color[4])
    for _, point in ipairs(record.points) do
      image:drawPixel(point.x, point.y, rgba)
    end
    sprite:newCel(layer, 1, image, Point(0, 0))
  end

  function M.findTopLevelGroup(sprite, name)
    for _, layer in ipairs(sprite.layers) do
      if layer.isGroup and layer.name == name then return layer end
    end
    return nil
  end

  function M.saveConfig(sprite, config)
    sprite.properties[CONFIG_KEY] = table.concat({
      "v1", config.size, config.elevation, config.sizingMode, config.layout,
      config.alignment or "center", config.offsetX or 0, config.offsetY or 0
    }, "|")
  end

  function M.loadConfig(sprite)
    if not sprite then return nil, "PREVIEW_CONFIG_INVALID" end
    local raw = sprite.properties[CONFIG_KEY]
    if type(raw) ~= "string" then return nil, "PREVIEW_CONFIG_INVALID" end
    local values = {}
    for value in raw:gmatch("[^|]+") do values[#values + 1] = value end
    if #values ~= 8 or values[1] ~= "v1" then return nil, "PREVIEW_CONFIG_INVALID" end
    local config = {
      size=tonumber(values[2]), elevation=tonumber(values[3]),
      sizingMode=values[4], layout=values[5], alignment=values[6],
      offsetX=tonumber(values[7]), offsetY=tonumber(values[8])
    }
    local validation = Model.validate(config)
    if not validation.ok then return nil, "PREVIEW_CONFIG_INVALID" end
    return config
  end

  function M.isTemplate(sprite)
    if not sprite then return false end
    local counts = {Artwork=0,Guides=0}
    for _, layer in ipairs(sprite.layers) do
      if layer.isGroup and counts[layer.name] ~= nil then
        counts[layer.name] = counts[layer.name] + 1
      end
    end
    if counts.Artwork ~= 1 or counts.Guides ~= 1 then return false end
    return M.loadConfig(sprite) ~= nil
  end

  function M.create(config, pixelLayers, hooks)
    local previous = app.activeSprite
    local sprite
    local ok, result = xpcall(function()
      local sheet = Atlas.sheet(config)
      local spec = ImageSpec{
        width=sheet.width, height=sheet.height, colorMode=ColorMode.RGB,
        colorSpace=ColorSpace{sRGB=true}
      }
      sprite = Sprite(spec)
      app.transaction("Generate Isometric Dual Grid", function()
        sprite:setPalette(Palette(app.defaultPalette))
        sprite:deleteLayer(sprite.layers[1])

        local guides = sprite:newGroup()
        guides.name, guides.isEditable = "Guides", false
        local sliceLayers = SliceRef.atlas(config)
        for _, spec in ipairs(guideLayers) do
          local layer = sprite:newLayer()
          layer.name, layer.parent, layer.isEditable = spec.name, guides, false
          if hooks and hooks.afterLayer then hooks.afterLayer(spec.name) end
          local record = sliceLayers[spec.slice]
          if (not record or #record.points == 0) and spec.fallback then
            record = pixelLayers[spec.fallback]
          end
          if record and #record.points > 0 then
            attachRecord(sprite, layer, record, sheet)
          else
            sprite:newCel(layer, 1, Image(sheet.width, sheet.height, ColorMode.RGB), Point(0,0))
          end
        end

        local artwork = sprite:newGroup()
        artwork.name = "Artwork"
        local walls = sprite:newLayer()
        walls.name, walls.parent = "Walls", artwork
        local top = sprite:newLayer()
        top.name, top.parent = "Top", artwork

        M.saveConfig(sprite, config)
        app.activeLayer = top
      end)
      return sprite
    end, debug.traceback)
    if not ok then
      if sprite then sprite:close() end
      if previous then app.activeSprite = previous end
      print(result)
      error(Errors.message("SPRITE_CREATE_FAILED"))
    end
    return result
  end

  return M
end
