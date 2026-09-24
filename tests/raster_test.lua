return function(T, root, load)
  local Raster = load("src/raster.lua")
  local Model = load("src/model.lua")
  local Atlas = load("src/atlas.lua")
  local Document = load("src/document.lua")
  local Variants = load("src/variants.lua")
  local Font = load("src/font.lua")
  local layerNames = {"grid", "seams", "height", "labels"}

  local function config(size, elevation, mode, layout)
    local result = Model.defaults()
    result.size, result.elevation = size, elevation
    result.sizingMode, result.layout = mode or "fixed", layout or "row"
    return result
  end

  local function coordinateKey(x,y)
    return string.format("%d,%d",x,y)
  end
  local function key(p) return coordinateKey(p.x,p.y) end
  local function pointSet(points)
    local result = {}
    for _, p in ipairs(points) do result[key(p)] = true end
    return result
  end
  local function sameSet(actual, expected, message)
    for p in pairs(actual) do T.truthy(expected[p], message .. " unexpected " .. p) end
    for p in pairs(expected) do T.truthy(actual[p], message .. " missing " .. p) end
  end
  local function contains(points, x, y)
    return pointSet(points)[coordinateKey(x,y)] == true
  end
  local function inBounds(layers, width, height)
    for _, name in ipairs(layerNames) do
      local seen = {}
      for _, p in ipairs(layers[name].points) do
        T.equal(p.x, math.floor(p.x), name .. " integer x")
        T.equal(p.y, math.floor(p.y), name .. " integer y")
        T.truthy(p.x >= 0 and p.x < width, name .. " x bounds")
        T.truthy(p.y >= 0 and p.y < height, name .. " y bounds")
        T.truthy(not seen[key(p)], name .. " duplicate pixel")
        seen[key(p)] = true
      end
    end
  end

  T.test("rounds canonical points independently to the nearest integer", function()
    local p = Raster.scalePoint({x=32,y=16}, 32)
    T.equal(p.x, 16)
    T.equal(p.y, 8)
    p = Raster.scalePoint({x=1,y=3}, 32)
    T.equal(p.x, 1)
    T.equal(p.y, 2)
    p = Raster.scalePoint({x=32,y=16}, 128)
    T.equal(p.x, 64)
    T.equal(p.y, 32)
  end)

  T.test("rasterizes inclusive 8-connected lines in every octant", function()
    local expected = {{0,0},{1,0},{2,1},{3,1},{4,2},{5,2}}
    local line = Raster.line8({x=0,y=0}, {x=5,y=2})
    T.equal(#line, #expected)
    for i, p in ipairs(line) do
      T.equal(p.x, expected[i][1])
      T.equal(p.y, expected[i][2])
    end
    for _, endpoint in ipairs({{5,2},{2,5},{-2,5},{-5,2},
        {-5,-2},{-2,-5},{2,-5},{5,-2},{0,5},{5,0},{0,0}}) do
      line = Raster.line8({x=0,y=0}, {x=endpoint[1],y=endpoint[2]})
      T.equal(#line, math.max(math.abs(endpoint[1]),math.abs(endpoint[2]))+1)
      T.equal(line[1].x, 0)
      T.equal(line[1].y, 0)
      T.equal(line[#line].x, endpoint[1])
      T.equal(line[#line].y, endpoint[2])
      for i = 2, #line do
        T.truthy(math.abs(line[i].x-line[i-1].x) <= 1)
        T.truthy(math.abs(line[i].y-line[i-1].y) <= 1)
        T.truthy(key(line[i]) ~= key(line[i-1]))
      end
    end
  end)

  T.test("paths collapse scaled vertices and emit each segment join once", function()
    local path = Raster.path({{x=0,y=0},{x=1,y=0},{x=8,y=0},{x=8,y=8}}, 16)
    local expected = {{0,0},{1,0},{2,0},{2,1},{2,2}}
    T.equal(#path, #expected)
    for i, p in ipairs(path) do
      T.equal(p.x, expected[i][1])
      T.equal(p.y, expected[i][2])
    end
    T.equal(#Raster.path({}, 64), 0)
    T.equal(#Raster.path({{x=1,y=1},{x=1,y=1}}, 64), 1)
  end)

  T.test("tile layers use the required colors and translated top surface", function()
    local layers = Raster.tile(config(64,16), Variants.build(10))
    local colors = {
      grid={255,82,102,255}, seams={76,128,255,255},
      height={238,112,35,255}, labels={255,255,255,255}
    }
    for name, color in pairs(colors) do
      for i = 1, 4 do T.equal(layers[name].color[i], color[i]) end
    end
    T.truthy(contains(layers.grid.points, 32,16))
    T.truthy(contains(layers.grid.points, 0,32))
    T.equal(#layers.seams.points,0,"reference construction has no visible wave seams")
    T.truthy(contains(layers.height.points, 32,61))
    T.truthy(contains(layers.ground.points, 32,32), "bottom-grid top vertex")
    T.truthy(contains(layers.ground.points, 0,48), "bottom-grid left vertex")
    T.truthy(not contains(layers.height.points, 32,35), "hidden north wall")
    T.equal(#layers.labels.points, 40)
    inBounds(layers,64,64)
  end)

  T.test("64px zero-elevation variants contain only the reference grid", function()
    local cfg = config(64,0,"fixed","grid")
    for _, variant in ipairs(Variants.all()) do
      local layers = Raster.tile(cfg,variant)
      T.equal(#layers.seams.points,0,"mask " .. variant.index .. " has no visible seam")
      T.equal(#layers.height.points,0,"mask " .. variant.index .. " has no height")
    end
  end)

  T.test("64px zero-elevation Top outline is a 2px isometric diamond", function()
    local SliceRef = load("src/slice_ref.lua")
    local cfg = config(64,0,"fixed","grid")
    local layers = SliceRef.tile(cfg, Variants.build(0))
    T.equal(#layers.top.points, 128)
    T.equal(#layers.bottom.points, 128)
    T.equal(#layers.sliceBorder.points, 0)
    T.equal(#layers.sliceHeightHint.points, 0)
    local seen = {}
    for _, p in ipairs(layers.top.points) do
      seen[string.format("%d,%d", p.x, p.y)] = true
    end
    T.truthy(seen["30,16"] and seen["31,16"] and seen["32,16"] and seen["33,16"])
    T.truthy(seen["0,31"] and seen["1,31"] and seen["62,31"] and seen["63,31"])
    T.truthy(seen["30,47"] and seen["33,47"])
  end)

  T.test("64px 16px-elevation SliceHeightHint sits between Top and Bottom", function()
    local SliceRef = load("src/slice_ref.lua")
    local cfg = config(64,16,"fixed","grid")
    local layers = SliceRef.tile(cfg, Variants.build(15))
    T.equal(#layers.top.points, 128)
    T.equal(#layers.bottom.points, 128)
    T.truthy(#layers.sliceBorder.points > 0)
    T.truthy(#layers.sliceHeightHint.points > 0)
    local function extent(points)
      local minY, maxY = math.huge, -1
      for _, p in ipairs(points) do
        minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
      end
      return minY, maxY
    end
    local topMin, topMax = extent(layers.top.points)
    local bottomMin, bottomMax = extent(layers.bottom.points)
    local heightMin, heightMax = extent(layers.sliceHeightHint.points)
    T.equal(topMin, 16)
    T.equal(bottomMin, 32)
    T.equal(topMax, 47)
    T.equal(bottomMax, 63)
    T.truthy(heightMin > topMin)
    T.truthy(heightMax < bottomMax)
  end)

  T.test("mask 8 keeps separate height-hint runs below the reference elevation", function()
    local SliceRef = load("src/slice_ref.lua")
    local cfg = config(64,8,"fixed","grid")
    cfg.alignment = "top"
    local hint = SliceRef.tile(cfg,Variants.build(8)).sliceHeightHint.points
    T.truthy(contains(hint,20,7))
    T.truthy(contains(hint,20,13))
    T.truthy(not contains(hint,20,20),"the gap between walls stays empty")
    T.truthy(contains(hint,20,26))
    T.truthy(contains(hint,20,32))
    T.truthy(not contains(hint,25,20),"the second split column also stays empty")
  end)

  T.test("fixed horizontal offsets clip while stretch keeps shifted guide pixels", function()
    local SliceRef = load("src/slice_ref.lua")
    local cfg = config(64,16,"fixed","grid")
    cfg.offsetX = -7
    local fixed = SliceRef.tile(cfg,Variants.build(0))
    T.truthy(contains(fixed.top.points,23,16))
    T.truthy(not contains(fixed.top.points,30,16))
    for _, point in ipairs(fixed.top.points) do
      T.truthy(point.x >= 0 and point.x < 64)
    end
    cfg.sizingMode = "stretch"
    local stretch = SliceRef.tile(cfg,Variants.build(0))
    T.equal(Atlas.cell(cfg).width,71)
    T.truthy(contains(stretch.top.points,30,16))
  end)

  T.test("enlarged nearest-neighbor seams keep connected source paths", function()
    local SliceRef = load("src/slice_ref.lua")
    local cfg = config(128,16,"fixed","grid")
    local layers = SliceRef.tile(cfg,Variants.build(1))
    local function components(points)
      local remaining = pointSet(points)
      local count = 0
      for _, point in ipairs(points) do
        if remaining[key(point)] then
          count = count + 1
          local stack = {point}
          remaining[key(point)] = nil
          while #stack > 0 do
            local current = table.remove(stack)
            for dx = -1, 1 do
              for dy = -1, 1 do
                local neighbor = coordinateKey(current.x+dx,current.y+dy)
                if remaining[neighbor] then
                  remaining[neighbor] = nil
                  stack[#stack+1] = {x=current.x+dx,y=current.y+dy}
                end
              end
            end
          end
        end
      end
      return count
    end
    T.equal(components(layers.sliceBorder.points),1)
    T.equal(components(layers.sliceBorderBottom.points),1)
    for _, xy in ipairs({{84,44},{85,44},{84,45},{85,45}}) do
      T.truthy(contains(layers.sliceBorder.points,xy[1],xy[2]),
        "128px nearest-neighbor scaling keeps the full 2x2 source pixel")
    end
    T.truthy(contains(layers.sliceHeightHint.points,66,74))
    T.truthy(contains(layers.sliceHeightHint.points,67,74),
      "scaled vertical hints keep the source pixel width")
  end)

  T.test("all even sizes place guides and preview on integer pixels", function()
    local SliceRef = load("src/slice_ref.lua")
    local Preview = load("src/preview.lua")
    for _, size in ipairs({18,22}) do
      local cfg = config(size,math.floor(size/4),"fixed","grid")
      T.truthy(Model.validate(cfg).ok)
      local cell = Atlas.cell(cfg)
      T.equal(cell.topY,math.floor(cell.topY))
      local tile = SliceRef.tile(cfg,Variants.build(15))
      local rows = {}
      for name, layer in pairs(tile) do
        for _, point in ipairs(layer.points) do
          T.equal(point.x,math.floor(point.x),name .. " integer x")
          T.equal(point.y,math.floor(point.y),name .. " integer y")
          if name == "top" then rows[point.y] = true end
        end
      end
      for y = cell.topY, cell.topY + size/2 - 1 do
        T.truthy(rows[y],"top outline must reach row " .. y)
      end
      for _, record in ipairs(Preview.placements(cfg)) do
        T.equal(record.y,math.floor(record.y))
      end
      local image = Preview.render(cfg,"extruded")
      T.truthy(image.width > 0 and image.height > 0)
      local sprite = Document.create(cfg,Raster.atlas(cfg))
      T.truthy(sprite.width > 0)
      sprite:close()
    end
  end)

  T.test("64px generated Guides flatten to SliceRef.atlas pixels", function()
    local SliceRef = load("src/slice_ref.lua")
    for _, elevation in ipairs({0, 16}) do
      local cfg = config(64,elevation,"fixed","grid")
      local sprite = Document.create(cfg, Raster.atlas(cfg))
      local actual = Image(sprite)
      local expected = Image(sprite.width, sprite.height, ColorMode.RGB)
      expected:clear()
      local atlas = SliceRef.atlas(cfg)
      local order = {"bottom","top","sliceBorderBottom","sliceHeightHint","sliceBorder"}
      for _, name in ipairs(order) do
        local color = atlas[name].color
        local pixel = app.pixelColor.rgba(color[1],color[2],color[3],color[4])
        for _, p in ipairs(atlas[name].points) do
          expected:drawPixel(p.x, p.y, pixel)
        end
      end
      for y = 0, 255 do
        for x = 0, 255 do
          T.equal(actual:getPixel(x,y), expected:getPixel(x,y),
            "E=" .. elevation .. " pixel " .. x .. "," .. y)
        end
      end
      sprite:close()
    end
  end)

  T.test("height uses selected edge runs and only their endpoint connectors", function()
    local variant = {label="0000",inverted=false,paths={{
      points={{x=8,y=8},{x=16,y=8},{x=24,y=8},{x=32,y=8},{x=40,y=8}},
      wallEdges={normal={true,true,false,true},inverted={false,false,true,false}}
    }}}
    local cfg = config(64,4)
    local walls = Raster.tile(cfg,variant).height.points
    -- Center alignment fixes the diamond top at y=16: top edge y=24, bottom y=28.
    T.truthy(contains(walls,16,28))
    T.truthy(contains(walls,8,26))
    T.truthy(contains(walls,24,26))
    T.truthy(contains(walls,32,26))
    T.truthy(contains(walls,40,26))
    T.truthy(not contains(walls,16,26), "no connector at interior join")
    variant.inverted = true
    walls = Raster.tile(cfg,variant).height.points
    T.truthy(contains(walls,28,28))
  end)

  T.test("collapsed selected edges do not create dangling wall connectors", function()
    local variant = {label="0000",inverted=false,paths={{
      points={{x=8,y=8},{x=9,y=8},{x=16,y=8}},
      wallEdges={normal={true,false},inverted={false,true}}
    }}}
    local baseline = pointSet(Raster.tile(config(16,4),Variants.build(15)).height.points)
    sameSet(pointSet(Raster.tile(config(16,4),variant).height.points),baseline,
      "collapsed edges emit only the bottom grid")
    variant.paths[1].wallEdges.normal = {true,true}
    local walls = Raster.tile(config(16,4),variant).height.points
    T.truthy(contains(walls,2,8))
    T.truthy(contains(walls,4,8))
    T.truthy(not contains(walls,3,8))
  end)

  T.test("all variants stay inside fixed and stretched cells at height limits", function()
    for _, size in ipairs({16,32,64,128}) do
      for _, elevation in ipairs({0,size/2}) do
        local cfg = config(size,elevation)
        local cell = Atlas.cell(cfg)
        for _, variant in ipairs(Variants.all()) do
          local layers = Raster.tile(cfg,variant)
          inBounds(layers,cell.width,cell.height)
          if elevation == 0 then T.equal(#layers.height.points,0) end
          for _, path in ipairs(variant.paths) do
            for _, p in ipairs(Raster.path(path.points,size)) do
              T.truthy(p.x >= 0 and p.x < size)
              T.truthy(p.y+Atlas.cell(cfg).topY >= 0)
              T.truthy(p.y+Atlas.cell(cfg).topY < cell.height)
            end
          end
        end
      end
    end
    local cfg = config(32,32,"stretch")
    for _, variant in ipairs(Variants.all()) do
      inBounds(Raster.tile(cfg,variant),32,64)
    end
    T.truthy(contains(Raster.tile(cfg,Variants.build(10)).height.points,16,55))
  end)

  T.test("offsets translate raster layers inside padded physical cells", function()
    local cfg = config(64,16,"fixed","row")
    cfg.offsetX, cfg.offsetY = 7, 9
    local cell = Atlas.cell(cfg)
    local tile = Raster.tile(cfg,Variants.build(15))
    inBounds(tile,cell.width,cell.height)
    T.truthy(contains(tile.grid.points,39,25))
  end)

  T.test("font renders complete zero and one glyphs with one-pixel spacing", function()
    local points = {}
    Font.draw("01",3,2,function(x,y) points[#points+1]={x=x,y=y} end)
    T.equal(#points,20)
    T.truthy(contains(points,3,2))
    T.truthy(not contains(points,4,3))
    T.truthy(contains(points,8,2))
    T.truthy(contains(points,7,3))
    T.truthy(contains(points,9,6))
    for _, p in ipairs(points) do T.truthy(p.x ~= 6) end
    local labels = Raster.tile(config(16,4),Variants.build(0)).labels.points
    local labelTop = Atlas.cell(config(16,4)).topY
    T.equal(#labels,48)
    for _, p in ipairs(labels) do
      T.truthy(p.x >= 1 and p.x <= 15
        and p.y >= labelTop + 1 and p.y <= labelTop + 5)
    end
  end)

  T.test("atlas translates all sixteen independent tile layers without cell leaks", function()
    for _, layout in ipairs({"row","grid"}) do
      for _, cfg in ipairs({config(32,0,"fixed",layout),
          config(64,32,"fixed",layout),config(128,32,"fixed",layout),
          config(32,32,"stretch",layout)}) do
        local sheet = Atlas.sheet(cfg)
        local atlas = Raster.atlas(cfg)
        inBounds(atlas,sheet.width,sheet.height)
        for index = 0, 15 do
          local origin = Atlas.origin(index,sheet)
          local tile = Raster.tile(cfg,Variants.build(index))
          for _, name in ipairs(layerNames) do
            local actual = {}
            for _, p in ipairs(atlas[name].points) do
              if p.x >= origin.x and p.x < origin.x+sheet.cell.width
                  and p.y >= origin.y and p.y < origin.y+sheet.cell.height then
                actual[coordinateKey(p.x-origin.x,p.y-origin.y)] = true
              end
            end
            sameSet(actual,pointSet(tile[name].points),name .. " cell " .. index)
          end
        end
      end
    end
  end)

  T.test("render records cannot mutate subsequent tiles or other layers", function()
    local cfg = config(64,16)
    local first = Raster.tile(cfg,Variants.build(10))
    first.grid.color[1] = 0
    first.grid.points[1].x = -100
    local second = Raster.tile(cfg,Variants.build(10))
    T.equal(second.grid.color[1],255)
    T.truthy(contains(second.grid.points,32,16))
    inBounds(second,64,64)
    T.equal(first.seams.color[1],76)
  end)

  T.test("canonical RGBA tile matches the visually approved 64x64 golden image", function()
    local Fixture = dofile(app.fs.joinPath(root,"tests","seam_fixture.lua"))
    local actual = Fixture.render(load)
    local golden = Image{fromFile=app.fs.joinPath(root,"tests","fixtures","seam-64-golden.png")}
    T.equal(actual.width,64)
    T.equal(actual.height,64)
    T.equal(golden.width,actual.width)
    T.equal(golden.height,actual.height)
    T.equal(golden.colorMode,ColorMode.RGB)
    for y = 0, 63 do
      for x = 0, 63 do
        T.equal(actual:getPixel(x,y),golden:getPixel(x,y),"golden pixel " .. x .. "," .. y)
      end
    end
  end)
end
