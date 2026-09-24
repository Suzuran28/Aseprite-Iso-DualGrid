return function(T, root, load)
  local Export = load("src/export.lua")

  local green = app.pixelColor.rgba(0, 255, 0, 255)
  local red = app.pixelColor.rgba(255, 0, 0, 255)

  local function fixture()
    local sprite = Sprite(4, 4, ColorMode.RGB)
    sprite:deleteLayer(sprite.layers[1])

    local artwork = sprite:newGroup()
    artwork.name = "Artwork"
    local paint = sprite:newLayer()
    paint.name, paint.parent = "Paint", artwork
    local paintImage = Image(4, 4, ColorMode.RGB)
    paintImage:drawPixel(0, 0, green)
    sprite:newCel(paint, 1, paintImage, Point(0, 0))

    local guides = sprite:newGroup()
    guides.name, guides.isEditable = "Guides", false
    local guide = sprite:newLayer()
    guide.name, guide.parent, guide.isEditable = "Grid", guides, false
    local guideImage = Image(4, 4, ColorMode.RGB)
    guideImage:drawPixel(1, 0, red)
    sprite:newCel(guide, 1, guideImage, Point(0, 0))
    local labels = sprite:newLayer()
    labels.name, labels.parent = "Labels", guides
    labels.isVisible, labels.isEditable = false, false
    return sprite, artwork, guides, labels
  end

  local function snapshot(sprite, guides, labels)
    return {
      filename=sprite.filename,
      modified=sprite.isModified,
      guidesVisible=guides.isVisible,
      guidesEditable=guides.isEditable,
      labelsVisible=labels.isVisible,
      undoSteps=app.apiVersion >= 35 and sprite.undoHistory.undoSteps or nil
    }
  end

  local function equalSnapshots(before, after)
    for key, value in pairs(before) do T.equal(after[key], value, key) end
  end

  local function pixel(path, x, y)
    return Image{fromFile=path}:getPixel(x, y)
  end

  local function withFakeDialog(data, run)
    local originalDialog = Dialog
    local controls = {}
    local dialog = {data=data}
    function dialog:file(options) controls[options.id] = options end
    function dialog:check(options) controls[options.id] = options end
    function dialog:button(options) controls[options.id] = options end
    function dialog:show() end
    function dialog:close() self.closed = true end
    Dialog = function() return dialog end
    local ok, err = xpcall(function() run(controls, dialog) end, debug.traceback)
    Dialog = originalDialog
    if not ok then error(err) end
  end

  T.test("exports flattened guide pixels while preserving source state", function()
    local sprite, _, guides, labels = fixture()
    local before = snapshot(sprite, guides, labels)
    local outputDir = app.fs.joinPath(root, "tests", "output")
    app.fs.makeAllDirectories(outputDir)
    local withGuides = app.fs.joinPath(outputDir, "export-with-guides.png")
    local withoutGuides = app.fs.joinPath(outputDir, "export-without-guides.png")

    T.truthy(Export.save(sprite, withGuides, true))
    T.truthy(Export.save(sprite, withoutGuides, false))
    T.equal(pixel(withGuides, 0, 0), green)
    T.equal(pixel(withoutGuides, 0, 0), green)
    T.equal(pixel(withGuides, 1, 0), red)
    T.equal(pixel(withoutGuides, 1, 0), app.pixelColor.rgba(0, 0, 0, 0))
    equalSnapshots(before, snapshot(sprite, guides, labels))
    sprite:close()
  end)

  T.test("PNG export writes a flattened Image without creating a Sprite", function()
    local sprite = fixture()
    local originalSprite = Sprite
    local saved
    Sprite = function() error("export allocated a layered Sprite") end
    local ok, code, detail = Export.save(sprite,"ignored.png",false,
      function(image,path)
        saved = image
        T.equal(path,"ignored.png")
        T.equal(image.colorMode,ColorMode.RGB)
        T.equal(image:getPixel(0,0),green)
        T.equal(image:getPixel(1,0),app.pixelColor.rgba(0,0,0,0))
        return true
      end)
    Sprite = originalSprite
    T.truthy(ok,detail or code)
    T.truthy(saved)
    T.equal(app.activeSprite,sprite)
    sprite:close()
  end)

  T.test("validates only one exact top-level template group and one frame", function()
    local function code(sprite)
      local validation = Export.validate(sprite)
      return validation.ok, validation.code
    end
    local sprite, artwork, guides = fixture()
    T.equal(code(nil), false)
    T.equal(select(2, code(nil)), "NO_ACTIVE_SPRITE")
    sprite:newFrame()
    T.equal(select(2, code(sprite)), "FRAME_COUNT_INVALID")
    sprite:deleteFrame(2)
    sprite:deleteLayer(artwork)
    T.equal(select(2, code(sprite)), "ARTWORK_GROUP_INVALID")
    sprite:close()

    sprite, artwork, guides = fixture()
    sprite:deleteLayer(guides)
    T.equal(select(2, code(sprite)), "GUIDES_GROUP_INVALID")
    sprite:close()

    sprite, artwork, guides = fixture()
    guides.parent = artwork
    T.equal(select(2, code(sprite)), "GUIDES_GROUP_INVALID")
    sprite:close()

    sprite, artwork, guides = fixture()
    local duplicate = sprite:newGroup()
    duplicate.name = "Artwork"
    T.equal(Export.findTopLevelGroup(sprite, "Artwork"), nil)
    T.equal(select(2, code(sprite)), "ARTWORK_GROUP_INVALID")
    sprite:close()
  end)

  T.test("preserves an already hidden Guides group while exporting it from the clone", function()
    local sprite, _, guides, labels = fixture()
    guides.isVisible = false
    local before = snapshot(sprite, guides, labels)
    local output = app.fs.joinPath(root, "tests", "output", "export-hidden-guides.png")
    T.truthy(Export.save(sprite, output, true))
    T.equal(pixel(output, 1, 0), red)
    equalSnapshots(before, snapshot(sprite, guides, labels))
    sprite:close()
  end)

  T.test("does not clone for path cancellation or overwrite refusal and appends png", function()
    local sprite, _, guides, labels = fixture()
    local before = snapshot(sprite, guides, labels)
    local originalSave = Export.save
    local calls = 0
    Export.save = function(_, filename, includeGuides)
      calls = calls + 1
      T.equal(filename, app.fs.joinPath(root, "tests", "output", "chosen.png"))
      T.equal(includeGuides, true)
      return true
    end

    local ok, err = xpcall(function()
      withFakeDialog({filename=app.fs.joinPath(root, "tests", "output", "chosen"), includeGuides=true}, function(controls, dialog)
        Export.showDialog{alert=function() end}
        controls.cancel.onclick()
        T.truthy(dialog.closed)
        T.equal(calls, 0)
      end)

      withFakeDialog({filename="", includeGuides=true}, function(controls)
        Export.showDialog{alert=function() end}
        controls.export.onclick()
        T.equal(calls, 0)
      end)

      withFakeDialog({filename=app.fs.joinPath(root, "tests", "output", "chosen"), includeGuides=true}, function(controls)
        Export.showDialog{isFile=function() return true end, alert=function() return 2 end}
        controls.export.onclick()
        T.equal(calls, 0)
      end)

      withFakeDialog({filename=app.fs.joinPath(root, "tests", "output", "chosen"), includeGuides=true}, function(controls)
        Export.showDialog{isFile=function() return false end, alert=function() end}
        T.truthy(controls.includeGuides.selected)
        T.equal(controls.filename.save, true)
        T.equal(controls.filename.filetypes[1], "png")
        controls.export.onclick()
        T.equal(calls, 1)
      end)
    end, debug.traceback)
    Export.save = originalSave
    if not ok then error(err) end
    equalSnapshots(before, snapshot(sprite, guides, labels))
    sprite:close()
  end)

  T.test("reports Image save failures without changing source state", function()
    local sprite, _, guides, labels = fixture()
    local before, spritesBefore = snapshot(sprite, guides, labels), #app.sprites
    local ok, code, detail = Export.save(sprite, "ignored.png", true,
      function() error("injected Image save failure") end)
    T.equal(ok, nil)
    T.equal(code, "SAVE_FAILED")
    T.match(detail, "injected Image save failure")
    T.equal(#app.sprites, spritesBefore)
    equalSnapshots(before, snapshot(sprite, guides, labels))
    sprite:close()
  end)

  T.test("reports a failed Image save when the writer returns nil", function()
    local sprite = fixture()
    local ok, code = Export.save(sprite,"ignored.png",true,function() return nil end)
    T.equal(ok,nil)
    T.equal(code,"SAVE_FAILED")
    sprite:close()
  end)
end
