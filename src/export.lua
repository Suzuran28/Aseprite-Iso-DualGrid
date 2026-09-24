return function(load)
  local Errors = load("src/errors.lua")
  local Preview = load("src/preview.lua")
  local M = {}

  local function invalid(code)
    return {ok=false, code=code, message=Errors.message(code)}
  end

  local function pngPath(filename)
    if filename:lower():match("%.png$") then return filename end
    return filename .. ".png"
  end

  function M.findTopLevelGroup(sprite, name)
    if not sprite then return nil end
    local found, count = nil, 0
    for _, layer in ipairs(sprite.layers) do
      if layer.isGroup and layer.name == name then
        found, count = layer, count + 1
      end
    end
    if count == 1 then return found end
    return nil
  end

  function M.validate(sprite)
    if not sprite then return invalid("NO_ACTIVE_SPRITE") end
    if #sprite.frames ~= 1 then return invalid("FRAME_COUNT_INVALID") end
    local artwork = M.findTopLevelGroup(sprite, "Artwork")
    if not artwork then return invalid("ARTWORK_GROUP_INVALID") end
    local guides = M.findTopLevelGroup(sprite, "Guides")
    if not guides then return invalid("GUIDES_GROUP_INVALID") end
    return {ok=true, artwork=artwork, guides=guides}
  end

  function M.save(source, filename, includeGuides, saveImage)
    local validation = M.validate(source)
    if not validation.ok then return nil, validation.code end

    local ok, err = xpcall(function()
      local image = Preview.flattenSource(source,includeGuides)
      local save = saveImage or function(i, path) return i:saveAs(path) end
      if save(image, filename) ~= true then error("Image:saveAs did not succeed") end
    end, debug.traceback)
    if not ok then return nil, "SAVE_FAILED", err end
    return true
  end

  function M.showDialog(dependencies)
    dependencies = dependencies or {}
    local alert = dependencies.alert or app.alert
    local isFile = dependencies.isFile or app.fs.isFile
    local createDialog = dependencies.createDialog or Dialog
    if type(createDialog) ~= "function" then return nil, "UI_UNAVAILABLE" end
    local source = app.activeSprite
    local validation = M.validate(source)
    if not validation.ok then
      alert(validation.message)
      return nil, validation.code
    end

    local dlg = createDialog{title="导出等视距双网格 PNG"}
    if not dlg then return nil, "UI_UNAVAILABLE" end
    dlg:file{id="filename", label="PNG", save=true, filetypes={"png"}}
    dlg:check{id="includeGuides", label="包含辅助线", selected=true}
    dlg:button{
      id="export", text="导出",
      onclick=function()
        local filename = dlg.data.filename
        if not filename or filename == "" then
          alert(Errors.message("PATH_REQUIRED"))
          return
        end
        filename = pngPath(filename)
        if isFile(filename) then
          local answer = alert{
            title="覆盖 PNG", text="目标文件已存在，是否覆盖？",
            buttons={"覆盖", "取消"}
          }
          if answer ~= 1 then return end
        end
        local ok, code, detail = M.save(source, filename, dlg.data.includeGuides)
        if not ok then
          alert(Errors.message(code) .. "\n" .. tostring(detail or filename))
          return
        end
        dlg:close()
      end
    }
    dlg:button{id="cancel", text="取消", onclick=function() dlg:close() end}
    dlg:show{wait=false}
    return dlg
  end

  return M
end
