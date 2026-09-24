return function(T, root, load)
  local PreviewWindow = load("src/preview_window.lua")
  local Model = load("src/model.lua")

  T.test("preview state becomes dirty after a source change", function()
    local state = PreviewWindow.newState({}, Model.defaults())
    T.equal(state.dirty, true)
    state = PreviewWindow.reduce(state, {type="RENDERED",image="image"})
    T.equal(state.dirty, false)
    state = PreviewWindow.reduce(state, {type="SOURCE_CHANGED"})
    T.equal(state.dirty, true)
  end)

  T.test("preview controls update zoom and guide visibility", function()
    local state = PreviewWindow.newState({}, Model.defaults())
    state = PreviewWindow.reduce(state, {type="SET_ZOOM",value=2})
    state = PreviewWindow.reduce(state, {type="SET_GUIDES",value=false})
    T.equal(state.zoom, 2)
    T.equal(state.includeGuides, false)
    T.truthy(state.dirty)
  end)

  T.test("preview pan accumulates drag offsets", function()
    local state = PreviewWindow.newState({},Model.defaults())
    state = PreviewWindow.reduce(state,{type="PAN_BY",dx=30,dy=20})
    T.equal(state.panX,30)
    T.equal(state.panY,20)
    state = PreviewWindow.reduce(state,{type="PAN_BY",dx=-5,dy=7})
    T.equal(state.panX,25)
    T.equal(state.panY,27)
  end)

  T.test("wheel zoom can move both directions from very small and large fit scales", function()
    T.truthy(PreviewWindow.wheelZoom(0,1,0.1) < 0.1)
    T.truthy(PreviewWindow.wheelZoom(0,-1,20) > 20)
  end)

  T.test("fitted enlargements use whole-pixel multiples", function()
    T.equal(PreviewWindow.fitZoom(480,320,256,128),1)
    T.equal(PreviewWindow.fitZoom(480,320,100,50),4)
    T.truthy(PreviewWindow.fitZoom(480,320,512,256) < 1)
  end)

  T.test("opening another preview closes the previous window and listener", function()
    local originalDialog = Dialog
    local created = {}
    Dialog = function(options)
      local dlg = {options=options,closeCount=0}
      for _, method in ipairs({"button","check","newrow","canvas","show"}) do
        dlg[method] = function(self) return self end
      end
      function dlg:close()
        self.closeCount = self.closeCount + 1
        if self.options.onclose then self.options.onclose() end
      end
      created[#created + 1] = dlg
      return dlg
    end
    local function fakeSprite()
      local events = {onCount=0,offCount=0}
      function events:on()
        self.onCount = self.onCount + 1
        return self.onCount
      end
      function events:off()
        self.offCount = self.offCount + 1
      end
      return {events=events}
    end
    local ok, err = xpcall(function()
      local firstSprite, secondSprite = fakeSprite(), fakeSprite()
      local first = PreviewWindow.open(firstSprite,Model.defaults())
      T.equal(first.closeCount,0)
      local second = PreviewWindow.open(secondSprite,Model.defaults())
      T.equal(#created,2)
      T.equal(first.closeCount,1)
      T.equal(firstSprite.events.offCount,firstSprite.events.onCount)
      T.equal(second.closeCount,0)
      second:close()
      T.equal(secondSprite.events.offCount,secondSprite.events.onCount)
      local third = PreviewWindow.open(firstSprite,Model.defaults())
      T.equal(third.closeCount,0)
      third:close()
      T.equal(firstSprite.events.offCount,firstSprite.events.onCount)
    end,debug.traceback)
    Dialog = originalDialog
    if not ok then error(err) end
  end)

  T.test("preview follows the active template and updates from events and wheel", function()
    local originalDialog = Dialog
    local function bus()
      local result = {listeners={},nextId=0,offCount=0}
      function result:on(name,fn)
        self.nextId = self.nextId + 1
        self.listeners[self.nextId] = {name=name,fn=fn}
        return self.nextId
      end
      function result:off(id)
        self.listeners[id] = nil
        self.offCount = self.offCount + 1
      end
      function result:emit(name)
        local callbacks = {}
        for _, listener in pairs(self.listeners) do
          if listener.name == name then callbacks[#callbacks+1] = listener.fn end
        end
        for _, fn in ipairs(callbacks) do fn() end
      end
      return result
    end
    local dlg
    Dialog = function(options)
      dlg = {options=options,data={guides=true},widgets={},buttons={},painted={}}
      for _, method in ipairs({"button","check","canvas"}) do
        dlg[method] = function(self, spec)
          if spec.id then self.widgets[spec.id] = spec end
          if method == "button" then self.buttons[#self.buttons+1] = spec.text end
          return self
        end
      end
      function dlg:newrow() return self end
      function dlg:show() return self end
      function dlg:repaint() self.repaintCount=(self.repaintCount or 0)+1 end
      function dlg:close() if self.options.onclose then self.options.onclose() end end
      function dlg:paint()
        local gc = {width=480,height=320}
        function gc:fillRect() end
        function gc:fillText(text) dlg.emptyMessage = text end
        function gc:drawImage(image,source,destination)
          dlg.painted[#dlg.painted+1] = {sprite=image.sprite,
            guides=image.guides,width=destination.width,
            x=destination.x,y=destination.y}
        end
        self.widgets.preview.onpaint{context=gc,bounds=Rectangle(0,0,480,320)}
      end
      return dlg
    end
    local first = {events=bus(),config=Model.defaults()}
    local second = {events=bus(),config=Model.defaults()}
    for _, sprite in ipairs({first,second}) do
      local subscribe = sprite.events.on
      function sprite.events:on(name,fn)
        T.equal(name,"change","API 21 supports the sprite change event")
        return subscribe(self,name,fn)
      end
    end
    local appEvents = bus()
    local active = first
    local timer
    local renders = 0
    local services = {
      apiVersion=21,
      getActive=function() return active end,
      appEvents=appEvents,
      isTemplate=function(sprite) return sprite == first or sprite == second end,
      loadConfig=function(sprite) return sprite.config end,
      renderSource=function(sprite,config,guides)
        renders = renders + 1
        return {width=100,height=50,sprite=sprite,guides=guides}
      end,
      createTimer=function(options)
        timer = {options=options,isRunning=false}
        function timer:start() self.isRunning=true end
        function timer:stop() self.isRunning=false end
        function timer:fire() self.options.ontick() end
        return timer
      end
    }
    local ok, err = xpcall(function()
      PreviewWindow.open(first,first.config,services)
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].sprite,first)
      local initialWidth = dlg.painted[#dlg.painted].width
      active = second
      appEvents:emit("sitechange")
      timer:fire()
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].sprite,second)
      T.truthy(first.events.offCount > 0)
      active = nil
      appEvents:emit("sitechange")
      timer:fire()
      dlg:paint()
      T.match(dlg.emptyMessage,"活动")
      active = second
      appEvents:emit("sitechange")
      timer:fire()
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].sprite,second)
      dlg.data.guides = false
      T.equal(dlg.widgets.guides.text,"辅助线")
      T.truthy(type(dlg.widgets.guides.onclick) == "function")
      dlg.widgets.guides.onclick()
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].guides,false)
      local beforeEdit = renders
      second.events:emit("change")
      timer:fire()
      dlg:paint()
      T.truthy(renders > beforeEdit)
      dlg.widgets.preview.onwheel{deltaY=-1}
      dlg:paint()
      T.truthy(dlg.painted[#dlg.painted].width > initialWidth)
      active = first
      appEvents:emit("sitechange")
      timer:fire()
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].width,initialWidth)
      local baseX, baseY = dlg.painted[#dlg.painted].x,
        dlg.painted[#dlg.painted].y
      dlg.widgets.preview.onmousedown{button=MouseButton.RIGHT,x=100,y=100}
      dlg.widgets.preview.onmousemove{x=130,y=120}
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].x,baseX+30)
      T.equal(dlg.painted[#dlg.painted].y,baseY+20)
      dlg.widgets.preview.onmouseup{button=MouseButton.RIGHT,x=130,y=120}
      dlg.widgets.preview.onmousemove{x=160,y=150}
      dlg:paint()
      T.equal(dlg.painted[#dlg.painted].x,baseX+30)
      for _, name in ipairs(dlg.buttons) do
        T.truthy(name ~= "Fit" and name ~= "100%" and name ~= "200%"
          and name ~= "Refresh")
      end
      dlg:close()
      T.truthy(appEvents.offCount > 0)
      T.truthy(second.events.offCount > 0)
      T.equal(timer.isRunning,false)
    end,debug.traceback)
    Dialog = originalDialog
    if not ok then error(err) end
  end)
end
