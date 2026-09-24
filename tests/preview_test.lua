return function(T, root, load)
  local Preview = load("src/preview.lua")
  local Model = load("src/model.lua")
  local Document = load("src/document.lua")
  local Raster = load("src/raster.lua")

  local function config()
    local result = Model.defaults()
    result.size, result.elevation = 64, 16
    result.sizingMode, result.layout = "fixed", "grid"
    return result
  end

  local function countPixels(image, color)
    local target = app.pixelColor.rgba(color[1], color[2], color[3], color[4])
    local count = 0
    for y = 0, image.height - 1 do
      for x = 0, image.width - 1 do
        if image:getPixel(x, y) == target then count = count + 1 end
      end
    end
    return count
  end

  local function countOpaque(image)
    local count = 0
    for y = 0, image.height - 1 do
      for x = 0, image.width - 1 do
        if app.pixelColor.rgbaA(image:getPixel(x,y)) > 0 then count = count + 1 end
      end
    end
    return count
  end

  T.test("maps preview cells to the connected 4x4 mask topology", function()
    local expected = {
      {3,7,11,15},
      {2,6,10,14},
      {1,5,9,13},
      {0,4,8,12}
    }
    for row = 0, 3 do
      for column = 0, 3 do
        T.equal(Preview.maskAt(column,row),expected[row + 1][column + 1])
      end
    end
  end)

  T.test("places each binary row toward the right-down direction", function()
    local records = Preview.placements(config(), "top")
    T.equal(#records, 16)
    local byGrid = {}
    for _, record in ipairs(records) do
      byGrid[record.gridY] = byGrid[record.gridY] or {}
      byGrid[record.gridY][record.gridX] = record
    end
    for index, record in ipairs(records) do
      T.equal(record.mask,Preview.maskAt(record.gridX,record.gridY))
      if index > 1 then
        local before = records[index - 1]
        T.truthy(before.depth < record.depth
          or (before.depth == record.depth and before.x <= record.x),
          "placements must be depth sorted")
      end
    end
    T.equal(byGrid[0][0].x + 32,byGrid[0][1].x)
    T.equal(byGrid[0][0].y + 16,byGrid[0][1].y)
    T.equal(byGrid[0][0].x - 32,byGrid[1][0].x)
    T.equal(byGrid[0][0].y + 16,byGrid[1][0].y)
  end)

  T.test("renders transparent RGB top and extruded previews", function()
    local cfg = config()
    local flat = config()
    flat.elevation = 0
    local top, topBounds = Preview.render(flat, "top")
    local extruded, extrudedBounds = Preview.render(cfg, "extruded")
    local height = {223,113,38,255}
    local black = {0,0,0,255}

    T.equal(top.colorMode, ColorMode.RGB)
    T.equal(top.width, topBounds.width)
    T.equal(top.height, topBounds.height)
    T.equal(extruded.width, extrudedBounds.width)
    T.equal(extruded.height, extrudedBounds.height)
    T.equal(top.width, 256)
    T.equal(top.height, 128)
    T.equal(extruded.width, 256)
    T.equal(extruded.height, 144)
    T.equal(top:getPixel(0, 0), app.pixelColor.rgba(0, 0, 0, 0),
      "preview border stays transparent")
    T.equal(countPixels(top, height), 0, "top mode excludes height pixels")
    T.truthy(countPixels(top, black) > 0,
      "top mode includes the black slice border like isometric_ref1")
    T.truthy(countPixels(extruded, height) > 0,
      "extruded mode includes exposed height pixels")
    T.truthy(countPixels(extruded, black) > 0,
      "extruded mode includes seam borders and polylines")

    local outputDir = app.fs.joinPath(root, "tests", "output")
    app.fs.makeAllDirectories(outputDir)
    T.truthy(top:saveAs(app.fs.joinPath(outputDir, "preview-top.png")))
    T.truthy(extruded:saveAs(app.fs.joinPath(outputDir, "preview-extruded.png")))
  end)

  T.test("64px previews match the supplied reference PNGs pixel for pixel", function()
    local function matchesReference(actual, filename)
      local expected = Image{fromFile=app.fs.joinPath(root,"docs","references",filename)}
      T.equal(actual.width,expected.width)
      T.equal(actual.height,expected.height)
      for y = 0, actual.height - 1 do
        for x = 0, actual.width - 1 do
          T.equal(actual:getPixel(x,y),expected:getPixel(x,y),
            string.format("%s differs at (%d,%d)",filename,x,y))
        end
      end
    end
    local flat = config()
    flat.elevation = 0
    matchesReference(Preview.render(flat,"top"),"isometric_ref1.png")
    matchesReference(Preview.render(config(),"top"),"isometric_ref1.png")
    matchesReference(Preview.render(config(),"extruded"),"isometric_ref4.png")
  end)

  T.test("nonreference elevations show the top diamond and lower seam", function()
    local flat = Preview.render(config(),"top")
    local black = {0,0,0,255}
    local red = app.pixelColor.rgba(217,87,99,255)
    for _, item in ipairs({{elevation=8,alignment="center"},
        {elevation=32,alignment="top"}}) do
      local cfg = config()
      cfg.elevation, cfg.alignment = item.elevation, item.alignment
      T.truthy(Model.validate(cfg).ok)
      local image = Preview.render(cfg,"extruded")
      T.equal(image:getPixel(126,0),red,
        "the upper diamond remains visible at E=" .. item.elevation)
      T.truthy(countPixels(image,black) > countPixels(flat,black),
        "the lower seam adds visible black pixels at E=" .. item.elevation)
    end
  end)

  T.test("extruded preview leaves the lower diamond interior transparent", function()
    local cfg = config()
    cfg.alignment, cfg.elevation = "top", 32
    local image = Preview.render(cfg,"extruded")
    T.equal(image:getPixel(132,127),app.pixelColor.rgba(0,0,0,0),
      "the floor interior must not acquire a wall-fill wedge")
    cfg.alignment, cfg.elevation = "center", 8
    image = Preview.render(cfg,"extruded")
    T.equal(image:getPixel(122,35),app.pixelColor.rgba(0,0,0,0),
      "short walls must not fill the upper diamond interior")
  end)

  T.test("stretch preview includes guides extended by positive offsets", function()
    local cfg = config()
    cfg.size, cfg.elevation = 32, 8
    cfg.sizingMode, cfg.alignment = "stretch", "top"
    cfg.offsetX, cfg.offsetY = 7, 20
    local image = Preview.render(cfg,"extruded")
    T.truthy(image.width >= 135)
    T.truthy(image.height >= 92)
    T.truthy(app.pixelColor.rgbaA(image:getPixel(134,52)) > 0)
  end)

  T.test("composes source artwork separately from optional guides", function()
    local cfg = config()
    local sprite = Document.create(cfg, Raster.atlas(cfg))
    local guides = Document.findTopLevelGroup(sprite,"Guides")
    local originalVisibility = guides.isVisible
    local withoutGuides = Preview.renderSource(sprite, cfg, false)
    local withGuides = Preview.renderSource(sprite, cfg, true)
    T.equal(countOpaque(withoutGuides), 0)
    T.truthy(countOpaque(withGuides) > 0)
    T.equal(guides.isVisible,originalVisibility)
    sprite:close()
  end)

  T.test("rendering a preview does not switch the active document", function()
    local cfg = config()
    local source = Document.create(cfg,Raster.atlas(cfg))
    local active = Sprite(1,1,ColorMode.RGB)
    app.activeSprite = active
    Preview.renderSource(source,cfg,true)
    T.equal(app.activeSprite,active)
    active:close()
    source:close()
  end)

  T.test("preview composition never allocates an active Sprite clone", function()
    local cfg = config()
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local originalSprite = Sprite
    Sprite = function() error("preview attempted to allocate a Sprite") end
    local ok, result = xpcall(function()
      return Preview.renderSource(sprite,cfg,false)
    end,debug.traceback)
    Sprite = originalSprite
    T.truthy(ok,result)
    sprite:close()
  end)

  T.test("Preview Guides can show hidden source guides without changing them", function()
    local cfg = config()
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local guides = Document.findTopLevelGroup(sprite,"Guides")
    guides.isVisible = false
    local withGuides = Preview.renderSource(sprite,cfg,true)
    local withoutGuides = Preview.renderSource(sprite,cfg,false)
    T.truthy(countOpaque(withGuides) > 0)
    T.equal(countOpaque(withoutGuides),0)
    T.equal(guides.isVisible,false)
    sprite:close()
  end)

  T.test("Artwork remains visible above Guides in both Preview modes", function()
    local cfg = config()
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local artwork = Document.findTopLevelGroup(sprite,"Artwork")
    local top, walls
    for _, layer in ipairs(artwork.layers) do
      if layer.name == "Top" then top = layer end
      if layer.name == "Walls" then walls = layer end
    end
    local pixel = Image(1,1,ColorMode.RGB)
    local green = app.pixelColor.rgba(0,255,0,255)
    pixel:drawPixel(0,0,green)
    sprite:newCel(top,1,pixel,Point(32,16))
    local wallPixel = Image(1,1,ColorMode.RGB)
    wallPixel:drawPixel(0,0,app.pixelColor.rgba(0,0,255,255))
    sprite:newCel(walls,1,wallPixel,Point(32,16))
    local placement
    for _, record in ipairs(Preview.placements(cfg)) do
      if record.mask == 0 then placement = record end
    end
    local withGuides = Preview.renderSource(sprite,cfg,true)
    local withoutGuides = Preview.renderSource(sprite,cfg,false)
    local x, y = placement.x + 32, placement.y + 16
    T.equal(withGuides:getPixel(x,y),green)
    T.equal(withoutGuides:getPixel(x,y),green)
    local guides = Document.findTopLevelGroup(sprite,"Guides")
    guides.isVisible = false
    local forcedGuides = Preview.renderSource(sprite,cfg,true)
    T.equal(forcedGuides:getPixel(x,y),green)
    sprite:close()
  end)
end
