return function(T, root, load)
  local Model = load("src/model.lua")
  local Document = load("src/document.lua")
  local Raster = load("src/raster.lua")

  local function sideCopy() return load("src/side_copy.lua") end

  local function walls(sprite)
    local artwork = Document.findTopLevelGroup(sprite,"Artwork")
    for _, layer in ipairs(artwork.layers) do
      if layer.name == "Walls" then return layer end
    end
  end

  local function pixel(image, index, x, y)
    return image:getPixel(index%4*64+x, math.floor(index/4)*64+y)
  end

  T.test("64px same-side masks match the supplied visible reference pixels", function()
    local cfg = Model.defaults()
    for _, mode in ipairs({"transparent","opaque","interlaced"}) do
      local actual = sideCopy().mask(cfg,mode)
      local reference = Image{fromFile=app.fs.joinPath(root,"assets",
        mode .. "_mask.png")}
      for y = 0, 255 do
        for x = 0, 255 do
          local expected = reference:getPixel(x,y)
          if app.pixelColor.rgbaA(expected) == 0 then expected = 0 end
          T.equal(actual:getPixel(x,y),expected,
            mode .. " pixel " .. x .. "," .. y)
        end
      end
    end
  end)

  T.test("opaque copy fills matching side pixels in all sixteen tiles", function()
    local cfg = Model.defaults()
    cfg.sideCopy = "opaque"
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local copy = sideCopy()
    local before = copy.snapshot(sprite,cfg)
    local red = app.pixelColor.rgba(240,20,30,255)
    local image = Image(sprite.width,sprite.height,ColorMode.RGB)
    image:drawPixel(20,43,red)
    sprite:newCel(walls(sprite),1,image,Point(0,0))
    local after = copy.sync(sprite,cfg,before)
    for index = 0, 15 do T.equal(pixel(after,index,20,43),red) end
    T.equal(after:getPixel(10,10),0)
    sprite:close()
  end)

  T.test("transparent copy skips absent and differently colored side regions", function()
    local cfg = Model.defaults()
    cfg.sideCopy = "transparent"
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local copy = sideCopy()
    local before = copy.snapshot(sprite,cfg)
    local red = app.pixelColor.rgba(240,20,30,255)
    local image = Image(sprite.width,sprite.height,ColorMode.RGB)
    image:drawPixel(20,43,red)
    sprite:newCel(walls(sprite),1,image,Point(0,0))
    local after = copy.sync(sprite,cfg,before)
    T.equal(pixel(after,12,20,43),red)
    T.equal(pixel(after,6,20,43),0)
    T.equal(pixel(after,2,20,43),0)
    sprite:close()
  end)

  T.test("interlaced copy preserves the material split and propagates erasure", function()
    local cfg = Model.defaults()
    cfg.sideCopy = "interlaced"
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local copy = sideCopy()
    local blank = copy.snapshot(sprite,cfg)
    local blue = app.pixelColor.rgba(10,20,220,255)
    local image = Image(sprite.width,sprite.height,ColorMode.RGB)
    image:drawPixel(2*64+20,64+43,blue)
    sprite:newCel(walls(sprite),1,image,Point(0,0))
    local painted = copy.sync(sprite,cfg,blank)
    T.equal(pixel(painted,10,20,43),blue)
    T.equal(pixel(painted,0,20,43),0)
    local erased = Image(painted)
    erased:drawPixel(2*64+20,64+43,0)
    walls(sprite):cel(1).image = erased
    local after = copy.sync(sprite,cfg,painted)
    T.equal(pixel(after,10,20,43),0)
    sprite:close()
  end)

  T.test("editing mode copies immediately and shares the stroke undo step", function()
    local cfg = Model.defaults()
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local appEvents = {listeners={}}
    function appEvents:on(name,listener)
      self.listeners[name] = listener
      return name
    end
    function appEvents:off(name) self.listeners[name] = nil end
    local watcher = sideCopy().watch{
      getActive=function() return sprite end,
      appEvents=appEvents
    }
    T.equal(Document.loadConfig(sprite).sideCopy,"off")
    watcher:setMode("opaque")
    T.equal(Document.loadConfig(sprite).sideCopy,"opaque")
    local red = app.pixelColor.rgba(240,20,30,255)
    local beforeSteps = app.apiVersion >= 35 and sprite.undoHistory.undoSteps
    app.useTool{tool="pencil",layer=walls(sprite),
      color=Color{r=240,g=20,b=30,a=255},
      points={Point(20,43),Point(20,44)}}
    T.equal(Image(sprite):getPixel(3*64+20,3*64+43),red)
    T.equal(Image(sprite):getPixel(3*64+20,3*64+44),red)
    if beforeSteps then
      T.equal(sprite.undoHistory.undoSteps,beforeSteps+1)
    end
    app.undo()
    T.equal(walls(sprite):cel(1),nil,
      "one undo removes the source stroke and all copies")
    app.redo()
    T.equal(Image(sprite):getPixel(3*64+20,3*64+43),red)
    watcher:setMode("off")
    T.equal(Document.loadConfig(sprite).sideCopy,"off")
    app.useTool{tool="pencil",layer=walls(sprite),
      color=Color{r=240,g=20,b=30,a=255},points={Point(10,38)}}
    T.equal(Image(sprite):getPixel(3*64+10,3*64+38),0,
      "switching off stops subsequent copies")
    watcher:setMode("transparent")
    app.useTool{tool="pencil",layer=walls(sprite),
      color=Color{r=240,g=20,b=30,a=255},points={Point(21,43)}}
    T.equal(Image(sprite):getPixel(21,3*64+43),red)
    T.equal(Image(sprite):getPixel(2*64+21,64+43),0,
      "switching mode uses transparent mask groups immediately")
    watcher:close()
    T.equal(appEvents.listeners.sitechange,nil)
    sprite:close()
  end)

  T.test("row and shifted stretch atlases copy at their physical cell coordinates", function()
    local copy = sideCopy()
    for _, cfg in ipairs({
      {size=32,elevation=8,sizingMode="fixed",layout="row",
        alignment="center",offsetX=0,offsetY=0,sideCopy="opaque"},
      {size=64,elevation=24,sizingMode="stretch",layout="grid",
        alignment="top",offsetX=-7,offsetY=10,sideCopy="opaque"}
    }) do
      local sprite = Document.create(cfg,Raster.atlas(cfg))
      local before = copy.snapshot(sprite,cfg)
      local mask = copy.mask(cfg)
      local Atlas = load("src/atlas.lua")
      local sheet = Atlas.sheet(cfg)
      local x = cfg.size == 32 and 10 or 20
      local y = cfg.size == 32 and 22 or 37
      local color = app.pixelColor.rgba(10,210,30,255)
      local image = Image(sprite.width,sprite.height,ColorMode.RGB)
      image:drawPixel(x,y,color)
      sprite:newCel(walls(sprite),1,image,Point(0,0))
      local after = copy.sync(sprite,cfg,before,mask)
      local target = Atlas.origin(15,sheet)
      T.equal(after:getPixel(target.x+x,target.y+y),color)
      sprite:close()
    end
  end)

  T.test("site changes during mask preparation cannot reenter binding", function()
    local cfg = Model.defaults()
    cfg.sideCopy = "interlaced"
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local copy = sideCopy()
    local originalMask = copy.mask
    local active, calls = sprite, 0
    local appEvents = {listener=nil}
    function appEvents:on(_,fn) self.listener=fn; return 1 end
    function appEvents:off() self.listener=nil end
    copy.mask = function(config)
      calls = calls + 1
      if calls == 1 then
        active = nil
        appEvents.listener()
        active = sprite
        appEvents.listener()
      end
      return originalMask(config)
    end
    local ok, err = xpcall(function()
      local watcher = copy.watch{getActive=function() return active end,
        appEvents=appEvents}
      T.equal(calls,1,"mask generation must not recursively bind")
      watcher:close()
    end,debug.traceback)
    copy.mask = originalMask
    sprite:close()
    if not ok then error(err) end
  end)

end
