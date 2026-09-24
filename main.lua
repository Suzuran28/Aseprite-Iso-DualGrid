local MIN_API = 21
local source = debug.getinfo(1, "S").source
local file = source:sub(1, 1) == "@" and source:sub(2) or source
local ROOT = app.fs.filePath(file)
local Bootstrap = dofile(app.fs.joinPath(ROOT, "src", "bootstrap.lua"))
local load = Bootstrap.new(ROOT)
local DialogUI = load("src/dialog.lua")
local Export = load("src/export.lua")
local Document = load("src/document.lua")
local PreviewWindow = load("src/preview_window.lua")

function init(plugin)
  if not app.apiVersion or app.apiVersion < MIN_API then
    if app.isUIAvailable then
      app.alert("Isometric Dual Grid requires Aseprite API 21+")
    else
      print("Isometric Dual Grid requires Aseprite API 21+")
    end
    return
  end
  if not app.isUIAvailable then
    print("Isometric Dual Grid requires the Aseprite UI")
    return
  end
  plugin:newCommand{
    id="IsometricDualGridGenerate",
    title="生成等距双网格模板…",
    group="file_new",
    onclick=function() DialogUI.showGenerate() end
  }
  plugin:newCommand{
    id="IsometricDualGridExport",
    title="导出等视距双网格 PNG…",
    group="file_export_1",
    onenabled=function() return app.activeSprite ~= nil end,
    onclick=function() Export.showDialog() end
  }
  plugin:newCommand{
    id="IsometricDualGridPreview",
    title="打开等距双网格预览",
    group="view_controls",
    onenabled=function() return Document.isTemplate(app.activeSprite) end,
    onclick=function() PreviewWindow.openActive() end
  }
end

function exit(plugin)
end
