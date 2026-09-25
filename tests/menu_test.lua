return function(T, root)
  T.test("same-side choices register under an Edit insertion group", function()
    local realApp, oldInit, oldExit = app, init, exit
    local events = {}
    function events:on() return 1 end
    function events:off() end
    local menu, commands = nil, {}
    local plugin = {}
    function plugin:newMenuGroup(spec) menu = spec end
    function plugin:newCommand(spec) commands[spec.id] = spec end
    local fakeApp = setmetatable({fs=realApp.fs,apiVersion=38,
      isUIAvailable=true,activeSprite=nil,events=events}, {__index=realApp})
    local ok, err = xpcall(function()
      _G.app = fakeApp
      dofile(realApp.fs.joinPath(root,"main.lua"))
      init(plugin)
      T.truthy(menu,"the Edit menu needs a same-side submenu")
      T.equal(menu.title,"同面复制")
      T.equal(menu.group,"edit_insert")
      for _, mode in ipairs({"off","transparent","opaque","interlaced"}) do
        local command = commands["IsometricDualGridSideCopy" .. mode]
        T.truthy(command,mode .. " must be registered")
        T.equal(command.group,menu.id)
      end
      exit(plugin)
    end,debug.traceback)
    _G.app, _G.init, _G.exit = realApp, oldInit, oldExit
    if not ok then error(err) end
  end)
end
