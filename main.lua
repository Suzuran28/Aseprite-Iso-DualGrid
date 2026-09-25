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
local PlacementWindow = load("src/placement_window.lua")
local SideCopy = load("src/side_copy.lua")
local sideCopyWatcher

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
  sideCopyWatcher = SideCopy.watch()
  local sideCopyGroup = "edit_insert"
  if app.apiVersion >= 22 and type(plugin.newMenuGroup) == "function" then
    sideCopyGroup = "IsometricDualGridSideCopyMenu"
    plugin:newMenuGroup{
      id=sideCopyGroup, title="同面复制", group="edit_insert"
    }
  end
  for _, choice in ipairs({
    {mode="off",label="不启用"},
    {mode="transparent",label="透明"},
    {mode="opaque",label="不透明"},
    {mode="interlaced",label="交错"}
  }) do
    local selected = choice.mode
    plugin:newCommand{
      id="IsometricDualGridSideCopy" .. selected,
      title=(sideCopyGroup == "edit_insert" and "同面复制：" or "") .. choice.label,
      group=sideCopyGroup,
      onenabled=function() return Document.isTemplate(app.activeSprite) end,
      onchecked=function()
        local config = Document.loadConfig(app.activeSprite)
        return config and config.sideCopy == selected
      end,
      onclick=function() sideCopyWatcher:setMode(selected) end
    }
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
  plugin:newCommand{
    id="IsometricDualGridPlacementTest",
    title="打开等距双网格铺设测试",
    group="view_controls",
    onenabled=function() return Document.isTemplate(app.activeSprite) end,
    onclick=function() PlacementWindow.openActive() end
  }
end

function exit(plugin)
  if sideCopyWatcher then sideCopyWatcher:close(); sideCopyWatcher = nil end
end
