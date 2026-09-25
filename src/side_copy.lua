return function(load)
  local Atlas = load("src/atlas.lua")
  local Geometry = load("src/geometry.lua")
  local MaskData = load("src/side_copy_data.lua")
  local M = {}
  local decoded = {}

  local function scale(value, size)
    return math.floor(value * size / 64 + 0.5)
  end

  local function columns(mode, index)
    decoded[mode] = decoded[mode] or {}
    if decoded[mode][index] then return decoded[mode][index] end
    local hex = MaskData[mode][index+1]
    local position = 1
    local function byte()
      local value = tonumber(hex:sub(position,position+1),16)
      position = position + 2
      return value
    end
    local result = {}
    for x = 1, 64 do
      local count = byte()
      local runs = {}
      for i = 1, count do
        runs[i] = {start=byte(),length=byte(),color=byte()}
      end
      result[x] = runs
    end
    decoded[mode][index] = result
    return result
  end

  local function wallLayer(sprite)
    for _, group in ipairs(sprite.layers) do
      if group.isGroup and group.name == "Artwork" then
        for _, layer in ipairs(group.layers) do
          if not layer.isGroup and layer.name == "Walls" then return layer end
        end
      end
    end
  end

  function M.mask(config, mode)
    mode = mode or config.sideCopy or "off"
    if mode == "off" or config.elevation == 0 then return nil end
    local sheet = Atlas.sheet(config)
    local layout = Geometry.layout(config)
    local result = Image(sheet.width,sheet.height,ColorMode.RGB)
    result:clear()
    local palette = {}
    for id, color in ipairs(MaskData.colors) do
      palette[id] = app.pixelColor.rgba(color[1],color[2],color[3],color[4])
    end
    local xShift = layout.translation.x
    local yShift = layout.cell.topY - scale(16,config.size)
    for index = 0, 15 do
      local origin = Atlas.origin(index,sheet)
      local sourceColumns = columns(mode,index)
      for x = 0, config.size-1 do
        local sourceX = math.floor(x*64/config.size)
        for _, run in ipairs(sourceColumns[sourceX+1]) do
          local top = scale(run.start,config.size) + yShift
          local length = math.floor(run.length*config.elevation/16+0.5)
          for depth = 0, length-1 do
            local px = origin.x + x + xShift
            local py = origin.y + top + depth
            if px >= origin.x and px < origin.x+sheet.cell.width
                and py >= origin.y and py < origin.y+sheet.cell.height then
              result:drawPixel(px,py,palette[run.color])
            end
          end
        end
      end
    end
    return result
  end

  function M.snapshot(sprite, config)
    local sheet = Atlas.sheet(config)
    local image = Image(sheet.width,sheet.height,ColorMode.RGB)
    image:clear()
    local layer = wallLayer(sprite)
    local cel = layer and layer:cel(1)
    if cel then image:drawImage(cel.image,cel.position) end
    return image
  end

  function M.sync(sprite, config, previous, mask)
    local current = M.snapshot(sprite,config)
    if not previous or config.sideCopy == nil or config.sideCopy == "off"
        or config.elevation == 0 then return current end
    mask = mask or M.mask(config)
    local sheet = Atlas.sheet(config)
    local result, changed = nil, false
    for y = 0, sheet.height-1 do
      for x = 0, sheet.width-1 do
        local value = current:getPixel(x,y)
        if value ~= previous:getPixel(x,y) then
          local group = mask:getPixel(x,y)
          if app.pixelColor.rgbaA(group) > 0 then
            local localX, localY = x%sheet.cell.width,y%sheet.cell.height
            for index = 0, 15 do
              local origin = Atlas.origin(index,sheet)
              local targetX, targetY = origin.x+localX,origin.y+localY
              if mask:getPixel(targetX,targetY) == group then
                if not result then result = Image(current) end
                if result:getPixel(targetX,targetY) ~= value then
                  result:drawPixel(targetX,targetY,value)
                  changed = true
                end
              end
            end
          end
        end
      end
    end
    if changed then
      local layer = wallLayer(sprite)
      local cel = layer and layer:cel(1)
      if cel then
        cel.image = result
        cel.position = Point(0,0)
      end
      return result
    end
    return current
  end

  function M.watch(services)
    services = services or {}
    local Document = load("src/document.lua")
    local getActive = services.getActive or function() return app.activeSprite end
    local appEvents = services.appEvents or app.events
    local sprite, config, mask, previous, spriteListener
    local appListener
    local syncing, binding, closed = false, false, false

    local function unbind()
      if sprite and spriteListener then sprite.events:off(spriteListener) end
      sprite, config, mask, previous, spriteListener = nil,nil,nil,nil,nil
    end

    local function bindActive(force)
      if closed or binding then return end
      binding = true
      local ok, err = xpcall(function()
        local active = getActive()
        if active == sprite and not force then return end
        unbind()
        if not active or not Document.isTemplate(active) then return end
        local nextConfig = Document.loadConfig(active)
        if nextConfig.sideCopy == "off" or nextConfig.elevation == 0 then return end
        sprite, config = active, nextConfig
        mask = M.mask(config)
        previous = M.snapshot(sprite,config)
        spriteListener = sprite.events:on("change",function(ev)
          if syncing then return end
          if ev and ev.fromUndo then
            previous = M.snapshot(sprite,config)
            return
          end
          syncing = true
          local copied, result = xpcall(function()
            return M.sync(sprite,config,previous,mask)
          end,debug.traceback)
          syncing = false
          if copied then previous = result else print(result) end
        end)
      end,debug.traceback)
      binding = false
      if not ok then unbind(); error(err) end
    end

    appListener = appEvents:on("sitechange",function() bindActive(false) end)
    bindActive()
    return {
      setMode=function(_,mode)
        if mode ~= "off" and mode ~= "transparent"
            and mode ~= "opaque" and mode ~= "interlaced" then
          return nil,"SIDE_COPY_INVALID"
        end
        local active = getActive()
        if not Document.isTemplate(active) then return nil,"PREVIEW_CONFIG_INVALID" end
        local nextConfig = Document.loadConfig(active)
        nextConfig.sideCopy = mode
        Document.saveConfig(active,nextConfig)
        bindActive(true)
        return true
      end,
      close=function()
        if closed then return end
        closed = true
        appEvents:off(appListener)
        unbind()
      end
    }
  end

  return M
end
