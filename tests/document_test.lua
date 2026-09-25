return function(T, root, load)
  local Document = load("src/document.lua")
  local Model = load("src/model.lua")
  local Raster = load("src/raster.lua")

  local function config()
    local result = Model.defaults()
    result.size, result.elevation = 64, 16
    result.sizingMode, result.layout = "fixed", "grid"
    return result
  end

  -- Aseprite exposes a group's children bottom-to-top; assert the required
  -- top-down stack without coupling the contract to its storage direction.
  local function layer(group, index, name)
    local result = group.layers[#group.layers - index + 1]
    T.equal(result.name, name)
    return result
  end

  local function guide(sprite, name)
    local guides = Document.findTopLevelGroup(sprite, "Guides")
    for _, child in ipairs(guides.layers) do
      if child.name == name then return child end
    end
  end

  local function transparent(image, x, y)
    return image:getPixel(x, y) == app.pixelColor.rgba(0, 0, 0, 0)
  end

  T.test("creates the required layered transparent RGB template", function()
    local cfg = config()
    local pixels = Raster.atlas(cfg)
    local sprite = Document.create(cfg, pixels)
    local sheet = Model.validate(cfg).sheet

    T.equal(sprite.width, sheet.width)
    T.equal(sprite.height, sheet.height)
    T.equal(sprite.colorMode, ColorMode.RGB)
    T.equal(#sprite.frames, 1)
    T.equal(#sprite.layers, 2)

    local artwork = layer(sprite, 1, "Artwork")
    local guides = layer(sprite, 2, "Guides")
    T.truthy(guides.isGroup)
    T.truthy(artwork.isGroup)
    T.equal(guides.isEditable, false)
    T.equal(artwork.isEditable, true)

    local border = layer(guides, 1, "SliceBorder")
    local height = layer(guides, 2, "SliceHeightHint")
    local borderBottom = layer(guides, 3, "SliceBorderBottom")
    local topGuide = layer(guides, 4, "Top")
    local bottom = layer(guides, 5, "Bottom")
    for _, guide in ipairs({bottom, topGuide, borderBottom, height, border}) do
      T.equal(guide.isEditable, false)
      T.equal(#guide.cels, 1)
      T.truthy(not guide:cel(1).image:isEmpty())
    end

    local top = layer(artwork, 1, "Top")
    local walls = layer(artwork, 2, "Walls")
    for _, editable in ipairs({top, walls}) do
      T.equal(editable.isEditable, true)
      T.equal(#editable.cels, 0)
    end
    T.truthy(transparent(sprite.cels[1].image, 0, 0))
    T.equal(app.activeSprite, sprite)
    T.equal(app.activeLayer, top)
    T.equal(Document.findTopLevelGroup(sprite, "Guides"), guides)
    T.equal(Document.findTopLevelGroup(sprite, "missing"), nil)
    local nested = sprite:newGroup()
    nested.name, nested.parent = "Guides", artwork
    T.equal(Document.findTopLevelGroup(sprite, "Guides"), guides)
    sprite:close()
  end)

  T.test("fixed offsets crop sheets while stretch expands them", function()
    local fixed = config()
    fixed.offsetX, fixed.offsetY = -7, 30
    local fixedSprite = Document.create(fixed,Raster.atlas(fixed))
    T.equal(fixedSprite.width,256)
    T.equal(fixedSprite.height,256)
    local topGuide = guide(fixedSprite,"Top"):cel(1).image
    T.truthy(app.pixelColor.rgbaA(topGuide:getPixel(23,46)) > 0)
    fixedSprite:close()

    local stretch = config()
    stretch.sizingMode = "stretch"
    stretch.offsetX, stretch.offsetY = -7, 30
    local stretchedSprite = Document.create(stretch,Raster.atlas(stretch))
    T.equal(stretchedSprite.width,284)
    T.equal(stretchedSprite.height,376)
    stretchedSprite:close()
  end)

  T.test("artwork pixels cover guide pixels", function()
    local cfg = config()
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    local artwork = Document.findTopLevelGroup(sprite,"Artwork")
    local top
    for _, child in ipairs(artwork.layers) do
      if child.name == "Top" then top = child end
    end
    local image = Image(1,1,ColorMode.RGB)
    local green = app.pixelColor.rgba(0,255,0,255)
    image:drawPixel(0,0,green)
    sprite:newCel(top,1,image,Point(32,16))
    T.equal(Image(sprite):getPixel(32,16),green)
    sprite:close()
  end)

  T.test("guides are five genuinely separate layers like the reference slice group", function()
    local cfg = config()
    local sprite = Document.create(cfg, Raster.atlas(cfg))
    local images = {}
    local colors = {
      Bottom={217,87,99,255}, Top={172,50,50,255},
      SliceBorderBottom={50,60,57,255}, SliceHeightHint={223,113,38,255},
      SliceBorder={0,0,0,255}
    }
    for name, color in pairs(colors) do
      local image = guide(sprite, name):cel(1).image
      images[name] = image
      local target = app.pixelColor.rgba(color[1],color[2],color[3],color[4])
      local seen, foreign = false, 0
      for it in image:pixels() do
        local pixel = it()
        if app.pixelColor.rgbaA(pixel) > 0 then
          if pixel == target then seen = true
          else foreign = foreign + 1 end
        end
      end
      T.truthy(seen, name .. " must paint its own reference color")
      T.equal(foreign, 0, name .. " must not contain other guides' pixels")
    end
    local function signature(image)
      local parts = {}
      for it in image:pixels() do
        if app.pixelColor.rgbaA(it()) > 0 then parts[#parts + 1] = it.x * 4096 + it.y end
      end
      return table.concat(parts, ",")
    end
    for a in pairs(images) do
      for b in pairs(images) do
        if a ~= b then
          T.truthy(signature(images[a]) ~= signature(images[b]),
            a .. " and " .. b .. " must not be the same flattened composite")
        end
      end
    end
    sprite:close()
  end)

  T.test("closes a partial sprite and preserves the prior active document", function()
    local original = Sprite(1, 1, ColorMode.RGB)
    local before = #app.sprites
    T.truthy(pcall(function() app.activeSprite = original end),
      "Aseprite must support restoring the prior active sprite")
    local cfg = config()
    local ok = pcall(function()
      Document.create(cfg, Raster.atlas(cfg), {
        afterLayer=function(name)
          if name == "SliceBorderBottom" then error("injected build failure") end
        end
      })
    end)
    T.equal(ok, false)
    T.equal(#app.sprites, before)
    T.equal(app.activeSprite, original)
    original:close()
  end)

  T.test("populates the guides in one undoable transaction", function()
    local sprite = Document.create(config(), Raster.atlas(config()))
    T.equal(#sprite.cels, 5)
    if app.apiVersion >= 35 then
      T.equal(sprite.undoHistory.undoSteps, 1)
    else
      app.undo()
      T.equal(#sprite.cels, 0)
    end
    sprite:close()
  end)

  T.test("uses a copy of the default palette and saves preview configuration", function()
    local cfg = config()
    cfg.alignment, cfg.offsetX, cfg.offsetY = "top", -3, 7
    local sprite = Document.create(cfg, Raster.atlas(cfg))
    local saved = Document.loadConfig(sprite)

    T.equal(sprite.colorMode, ColorMode.RGB)
    T.equal(#sprite.palettes[1], #app.defaultPalette)
    T.equal(sprite.palettes[1]:getColor(0).rgbaPixel,
      app.defaultPalette:getColor(0).rgbaPixel)
    T.equal(saved.alignment, "top")
    T.equal(saved.offsetX, -3)
    T.equal(saved.offsetY, 7)
    T.truthy(Document.isTemplate(sprite))
    local duplicate = sprite:newGroup()
    duplicate.name = "Guides"
    T.truthy(not Document.isTemplate(sprite))
    sprite:close()
  end)

  T.test("persists same-side mode and treats older templates as disabled", function()
    local cfg = config()
    cfg.sideCopy = "interlaced"
    local sprite = Document.create(cfg,Raster.atlas(cfg))
    T.equal(Document.loadConfig(sprite).sideCopy,"interlaced")
    sprite.properties["isometric-dual-grid.config.v1"] =
      "v1|64|16|fixed|grid|center|0|0"
    T.equal(Document.loadConfig(sprite).sideCopy,"off")
    sprite:close()
  end)

  T.test("guide height hints scale with the requested elevation", function()
    local function bottomOpaque(image)
      local result = -1
      for it in image:pixels() do
        if app.pixelColor.rgbaA(it()) > 0 then result = math.max(result,it.y) end
      end
      return result
    end
    local short = config()
    short.elevation = 8
    local tall = config()
    tall.elevation = 16
    local stretched = config()
    stretched.elevation = 32
    stretched.sizingMode = "stretch"
    short.layout, tall.layout, stretched.layout = "row", "row", "row"
    short.alignment, tall.alignment, stretched.alignment = "top", "top", "top"
    local shortSprite = Document.create(short,Raster.atlas(short))
    local tallSprite = Document.create(tall,Raster.atlas(tall))
    local stretchedSprite = Document.create(stretched,Raster.atlas(stretched))
    T.equal(bottomOpaque(guide(tallSprite,"SliceHeightHint"):cel(1).image)
      - bottomOpaque(guide(shortSprite,"SliceHeightHint"):cel(1).image),8)
    T.equal(bottomOpaque(guide(tallSprite,"Bottom"):cel(1).image)
      - bottomOpaque(guide(shortSprite,"Bottom"):cel(1).image),8)
    T.equal(bottomOpaque(guide(stretchedSprite,"SliceHeightHint"):cel(1).image)
      - bottomOpaque(guide(tallSprite,"SliceHeightHint"):cel(1).image),16)
    shortSprite:close()
    tallSprite:close()
    stretchedSprite:close()
  end)
end
