return function(T, root, load)
  local Window = load("src/placement_window.lua")
  local Model = load("src/model.lua")
  local Placement = load("src/placement.lua")

  local function registerCanvas(dlg,spec)
    dlg.widgets[spec.id]=spec
    dlg.canvasIds=dlg.canvasIds or {}
    dlg.canvasIds[#dlg.canvasIds+1]=spec.id
    if spec.id ~= "workspace" then return end
    local function sceneEvent(handler,ev)
      local shifted={}
      for key,value in pairs(ev) do shifted[key]=value end
      if ev.x then shifted.x=ev.x+140 end
      return handler(shifted)
    end
    dlg.widgets.scene={onkeydown=spec.onkeydown}
    for _,name in ipairs({"onmousedown","onmousemove","onmouseup","onwheel"}) do
      dlg.widgets.scene[name]=function(ev)
        return sceneEvent(spec[name],ev)
      end
    end
    dlg.widgets.scene.onpaint=function(ev)
      ev.context.width=620
      return spec.onpaint(ev)
    end
    dlg.widgets.layers={onkeydown=spec.onkeydown,onpaint=spec.onpaint}
    for _,name in ipairs({"onmousedown","onmousemove","onmouseup","onwheel"}) do
      dlg.widgets.layers[name]=spec[name]
    end
  end

  T.test("placement window starts empty and tool selection toggles", function()
    local first = Window.newState({},Model.defaults())
    T.equal(Placement.count(first.stack.layers[1].ground),0)
    T.equal(first.tool,nil)
    T.equal(first.terrain,1)
    Window.selectTerrain(first,0)
    T.equal(first.terrain,0)
    Window.selectTerrain(first,1)
    T.equal(first.terrain,1)
    Window.selectTool(first,"brush")
    T.equal(first.tool,"brush")
    Window.selectTool(first,"brush")
    T.equal(first.tool,nil)
    local second = Window.newState({},Model.defaults())
    T.equal(Placement.count(second.stack.layers[1].ground),0)
  end)

  T.test("placement interaction paints rectangles erases and pans by mode", function()
    local originalDialog = Dialog
    local windows = {}
    local function bus()
      local result = {items={},nextId=0,offCount=0}
      function result:on(name,fn)
        self.nextId=self.nextId+1
        self.items[self.nextId]={name=name,fn=fn}
        return self.nextId
      end
      function result:off(id)
        self.items[id]=nil
        self.offCount=self.offCount+1
      end
      function result:emit(name)
        for _,item in pairs(self.items) do
          if item.name == name then item.fn() end
        end
      end
      return result
    end
    Dialog = function(options)
      local dlg={options=options,widgets={},draws={},closed=false}
      function dlg:canvas(spec) registerCanvas(self,spec); return self end
      function dlg:newrow(options)
        self.rows=self.rows or {}
        self.rows[#self.rows+1]=options
        return self
      end
      function dlg:modify() return self end
      function dlg:show(options) self.showOptions=options; return self end
      function dlg:repaint() self.repaintCount=(self.repaintCount or 0)+1 end
      function dlg:close()
        self.closed=true
        if self.options.onclose then self.options.onclose() end
      end
      function dlg:paint()
        local gc={width=620,height=320,strokes=0,labels={},rects={},
          themeParts={},themeImages={}}
        self.paths={}
        function gc:fillRect(rect)
          self.rects[#self.rects+1]=rect
        end
        function gc:strokeRect() end
        function gc:fillText(value) self.labels[value]=true end
        function gc:drawThemeRect(part,rect)
          self.themeParts[part]=rect
        end
        function gc:drawThemeImage(part)
          self.themeImages[part]=true
        end
        function gc:drawImage(image,source,destination)
          dlg.draws[#dlg.draws+1]={mask=image.mask,x=destination.x,
            y=destination.y,width=destination.width}
        end
        function gc:beginPath() end
        function gc:moveTo(x,y)
          dlg.paths[#dlg.paths+1]={x=x,y=y}
        end
        function gc:lineTo() end
        function gc:closePath() end
        function gc:stroke() self.strokes=self.strokes+1 end
        self.widgets.workspace.onpaint{context=gc}
        return gc
      end
      windows[#windows+1]=dlg
      return dlg
    end
    local sprite={events=bus()}
    local appEvents=bus()
    local cfg=Model.defaults()
    cfg.elevation=12
    local allowDelete=false
    local services={apiVersion=21,appEvents=appEvents,
      getActive=function() return sprite end,
      isTemplate=function(value) return value == sprite end,
      loadConfig=function() return cfg end,
      confirmDelete=function() return allowDelete end,
      makeTiles=function()
        local result={}
        for mask=0,15 do result[mask]={mask=mask,width=64,height=64} end
        return result
      end}
    local ok,err=xpcall(function()
      local first=Window.open(sprite,cfg,services)
      local scene=first.widgets.scene
      local initialPaint=first:paint()
      T.equal(initialPaint.strokes,0)
      T.equal(initialPaint.rects[1].x,140)
      T.equal(initialPaint.rects[1].width,480)
      T.equal(initialPaint.rects[2].x,0)
      T.equal(initialPaint.rects[2].width,140,
        "sidebar background cannot cover the scene")
      T.truthy(initialPaint.themeParts.timeline_clicked,
        "selected row uses the native timeline skin")
      T.equal(initialPaint.themeParts.timeline_clicked.height,22,
        "selected row uses the compact native timeline skin")
      T.truthy(initialPaint.themeImages.tiles,
        "layer row uses the theme's tile icon")
      scene.onkeydown{code="KeyB",stopPropagation=function() end}
      T.truthy(first:paint().strokes>0)
      scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      scene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      first:paint()
      T.equal(#first.draws,4)
      local baseX=first.draws[#first.draws].x
      scene.onmousedown{button=MouseButton.RIGHT,x=100,y=100}
      scene.onmousemove{x=130,y=120}
      scene.onmouseup{button=MouseButton.RIGHT,x=130,y=120}
      first.draws={}
      first:paint()
      T.equal(first.draws[#first.draws].x,baseX)
      scene.onmousedown{button=MouseButton.LEFT,spaceKey=true,x=100,y=100}
      scene.onmousemove{x=130,y=120,spaceKey=true}
      scene.onmouseup{button=MouseButton.LEFT,x=130,y=120}
      first.draws={}
      first:paint()
      T.equal(first.draws[#first.draws].x,baseX+30)
      scene.onmousedown{button=MouseButton.RIGHT,spaceKey=true,x=100,y=100}
      scene.onmousemove{x=120,y=100,spaceKey=true}
      scene.onmouseup{button=MouseButton.RIGHT,x=120,y=100}
      first.draws={}
      first:paint()
      T.equal(first.draws[#first.draws].x,baseX+50)
      scene.onkeydown{code="KeyM",stopPropagation=function() end}
      scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      scene.onmousemove{x=304,y=192}
      scene.onmouseup{button=MouseButton.LEFT,x=304,y=192}
      first.draws={}
      first:paint()
      T.truthy(#first.draws>4)
      scene.onkeydown{code="KeyE",stopPropagation=function() end}
      scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      scene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      scene.onkeydown{code="Escape",stopPropagation=function() end}
      T.equal(first:paint().strokes,0)
      local noToolX=first.draws[#first.draws].x
      scene.onmousedown{button=MouseButton.RIGHT,x=100,y=100}
      scene.onmousemove{x=110,y=100}
      scene.onmouseup{button=MouseButton.RIGHT,x=110,y=100}
      first.draws={}
      first:paint()
      T.equal(first.draws[#first.draws].x,noToolX+10)
      first.widgets.tools.onmousedown{button=MouseButton.LEFT,x=240,y=10}
      T.truthy(first:paint().strokes>0)
      local guideX,guideY=first.paths[1].x,first.paths[1].y
      cfg.offsetX,cfg.offsetY=17,-4
      sprite.events:emit("change")
      first:paint()
      T.equal(first.paths[1].x,guideX)
      T.equal(first.paths[1].y,guideY)
      local beforeZoom=first.draws[#first.draws].width
      scene.onwheel{deltaY=-1,x=240,y=160}
      first.draws={}
      first:paint()
      T.truthy(first.draws[#first.draws].width>beforeZoom)
      local second=Window.open(sprite,cfg,services)
      T.truthy(first.closed)
      T.equal(#second.canvasIds,2,"toolbar and workspace are the only canvases")
      T.equal(second.widgets.workspace.width,620,
        "sidebar and scene share one horizontal canvas")
      second:paint()
      T.equal(#second.draws,0)
      T.equal(second.showOptions.wait,false)
      local secondScene=second.widgets.scene
      local digit1={code="Digit1",stopped=false}
      function digit1:stopPropagation() self.stopped=true end
      secondScene.onkeydown(digit1)
      T.truthy(digit1.stopped)
      secondScene.onkeydown{code="KeyB"}
      secondScene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      secondScene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      second.draws={}
      second:paint()
      T.equal(#second.draws,4)
      for _,draw in ipairs(second.draws) do T.equal(draw.mask,0) end
      local modified={code="Digit2",ctrlKey=true,stopped=false}
      function modified:stopPropagation() self.stopped=true end
      second.widgets.tools.onkeydown(modified)
      T.equal(modified.stopped,false)
      local digit2={code="Digit2",stopped=false}
      function digit2:stopPropagation() self.stopped=true end
      second.widgets.tools.onkeydown(digit2)
      T.truthy(digit2.stopped)
      secondScene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      secondScene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      second.draws={}
      second:paint()
      T.equal(#second.draws,4)
      local road=false
      for _,draw in ipairs(second.draws) do
        if draw.mask == 8 then road=true end
      end
      T.truthy(road)
      local numpad1={code="Numpad1",stopped=false}
      function numpad1:stopPropagation() self.stopped=true end
      secondScene.onkeydown(numpad1)
      T.truthy(numpad1.stopped)
      local numpad2={code="Numpad2",stopped=false}
      function numpad2:stopPropagation() self.stopped=true end
      secondScene.onkeydown(numpad2)
      T.truthy(numpad2.stopped)
      local digit0={code="Digit0",stopped=false}
      function digit0:stopPropagation() self.stopped=true end
      secondScene.onkeydown(digit0)
      T.equal(digit0.stopped,false)
      local layers=second.widgets.layers
      T.truthy(layers,"layer controls appear beside the scene")
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=45}
      layers.onmouseup{button=MouseButton.LEFT,x=10,y=45}
      secondScene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      secondScene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      second.draws={}
      second:paint()
      T.equal(#second.draws,4,"painting needs a selected layer")
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=45}
      layers.onmouseup{button=MouseButton.LEFT,x=10,y=45}
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=10}
      T.truthy(second:paint().labels["12px"])
      second.widgets.tools.onmousedown{button=MouseButton.LEFT,x=18,y=16}
      secondScene.onmousedown{button=MouseButton.LEFT,x=240,y=148}
      secondScene.onmouseup{button=MouseButton.LEFT,x=240,y=148}
      second.draws={}
      second:paint()
      T.equal(#second.draws,8)
      T.equal(second.draws[5].y,second.draws[1].y-12)
      layers.onmousedown{button=MouseButton.LEFT,x=125,y=45}
      second.draws={}
      second:paint()
      T.equal(#second.draws,12,"copy adds a separate visible layer")
      layers.onmousedown{button=MouseButton.LEFT,x=100,y=10}
      second.draws={}
      second:paint()
      T.equal(#second.draws,12,"cancelled deletion keeps the layer")
      allowDelete=true
      layers.onmousedown{button=MouseButton.LEFT,x=100,y=10}
      second.draws={}
      second:paint()
      T.equal(#second.draws,8,"delete removes copied layer")
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=45}
      layers.onmousemove{button=MouseButton.LEFT,x=10,y=55}
      layers.onmouseup{button=MouseButton.LEFT,x=10,y=55}
      second.draws={}
      second:paint()
      T.equal(second.draws[1].mask,0,"drag reorders layer artwork")
      second:close()
      T.truthy(sprite.events.offCount>0)
      T.truthy(appEvents.offCount>0)
    end,debug.traceback)
    Dialog=originalDialog
    if not ok then error(err) end
  end)

  T.test("placement uses documented atlas slots and offers both center terrains", function()
    local Document=load("src/document.lua")
    local Raster=load("src/raster.lua")
    local cfg=Model.defaults()
    local sprite=Document.create(cfg,Raster.atlas(cfg))
    local artwork=Document.findTopLevelGroup(sprite,"Artwork")
    local top
    for _,layer in ipairs(artwork.layers) do
      if layer.name == "Top" then top=layer end
    end
    local green=app.pixelColor.rgba(42,220,70,255)
    local blue=app.pixelColor.rgba(35,92,225,255)
    local gray=app.pixelColor.rgba(130,135,140,255)
    local source=Image(sprite.width,sprite.height,ColorMode.RGB)
    source:clear()
    source:drawPixel(32,3*64+16,green) -- 0:3, top corner only
    source:drawPixel(2*64+32,2*64+16,blue) -- 2:2, all corners
    source:drawPixel(32,16,gray) -- 0:0, center=0
    sprite:newCel(top,1,source,Point(0,0))
    local originalDialog=Dialog
    local dlg
    Dialog=function(options)
      dlg={options=options,widgets={},images={}}
      function dlg:canvas(spec) registerCanvas(self,spec); return self end
      function dlg:newrow() return self end
      function dlg:show() return self end
      function dlg:repaint() end
      function dlg:modify() end
      function dlg:close() self.options.onclose() end
      return dlg
    end
    local appEvents={}
    function appEvents:on() return 1 end
    function appEvents:off() end
    local ok,err=xpcall(function()
      Window.open(sprite,cfg,{apiVersion=21,appEvents=appEvents,
        confirmDelete=function() return true end,
        getActive=function() return sprite end})
      dlg.widgets.scene.onkeydown{code="KeyB"}
      dlg.widgets.scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      local gc={width=480,height=320}
      function gc:fillRect() end
      function gc:fillText() end
      function gc:drawThemeRect() end
      function gc:drawThemeImage() end
      function gc:beginPath() end
      function gc:moveTo() end
      function gc:lineTo() end
      function gc:stroke() end
      function gc:drawImage(image,src,dest)
        dlg.images[#dlg.images+1]={image=image,rect=dest}
      end
      dlg.widgets.scene.onpaint{context=gc}
      T.equal(#dlg.images,4)
      local topOnly
      for _,draw in ipairs(dlg.images) do
        if draw.rect.x == 348 and draw.rect.y == 144 then
          topOnly=draw.image
        else
          T.equal(app.pixelColor.rgbaA(draw.image:getPixel(32,16)),0)
        end
      end
      T.truthy(topOnly)
      T.equal(topOnly:getPixel(32,16),green)
      local layers=dlg.widgets.layers
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=10}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      local fadedTop
      for _,draw in ipairs(dlg.images) do
        if draw.rect.x == 348 and draw.rect.y == 144 then
          fadedTop=draw.image
        end
      end
      T.truthy(fadedTop)
      T.equal(app.pixelColor.rgbaA(fadedTop:getPixel(32,16)),77,
        "unselected artwork uses 30 percent opacity")
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=45}
      layers.onmouseup{button=MouseButton.LEFT,x=10,y=45}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      for _,draw in ipairs(dlg.images) do
        if draw.rect.x == 348 and draw.rect.y == 144 then
          T.equal(app.pixelColor.rgbaA(draw.image:getPixel(32,16)),255,
            "clearing selection restores all artwork opacity")
        end
      end
      layers.onmousedown{button=MouseButton.LEFT,x=10,y=45}
      layers.onmouseup{button=MouseButton.LEFT,x=10,y=45}
      dlg.widgets.scene.onmousedown{button=MouseButton.LEFT,x=240,y=144}
      dlg.widgets.scene.onmouseup{button=MouseButton.LEFT,x=240,y=144}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      T.equal(#dlg.images,8)
      local raised=false
      for _,draw in ipairs(dlg.images) do
        if draw.rect.x == 348 and draw.rect.y == 128 then
          raised=true
        end
      end
      T.truthy(raised,"upper layer uses the configured elevation")
      layers.onmousedown{button=MouseButton.LEFT,x=100,y=10}
      local bar={width=480,height=36}
      dlg.terrainButtons={}
      bar.labels={}
      function bar:fillRect() end
      function bar:strokeRect() end
      function bar:fillText(value)
        self.labels[#self.labels+1]=value
      end
      function bar:drawImage(image,src,dest)
        dlg.terrainButtons[#dlg.terrainButtons+1]={image=image,rect=dest}
      end
      dlg.widgets.tools.onpaint{context=bar}
      T.equal(#dlg.terrainButtons,2)
      T.equal(dlg.terrainButtons[1].image:getPixel(32,16),gray)
      T.equal(dlg.terrainButtons[2].image:getPixel(32,16),blue)
      T.equal(bar.labels[1],"1")
      T.equal(bar.labels[2],"2")
      for _,button in ipairs(dlg.terrainButtons) do
        T.truthy(button.rect.x < 90,"terrain buttons must be at top left")
      end
      dlg.widgets.tools.onmousedown{button=MouseButton.LEFT,x=18,y=16}
      dlg.widgets.scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      dlg.widgets.scene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      T.equal(#dlg.images,4,"painting center=0 places grass tiles")
      for _,draw in ipairs(dlg.images) do
        T.equal(draw.image:getPixel(32,16),gray)
      end
      dlg.widgets.scene.onkeydown{code="KeyE"}
      dlg.widgets.scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      dlg.widgets.scene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      T.equal(#dlg.images,0,"only the eraser clears placed terrain")
      dlg.widgets.scene.onkeydown{code="KeyB"}
      dlg.widgets.tools.onmousedown{button=MouseButton.LEFT,x=60,y=16}
      dlg.widgets.scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      dlg.widgets.scene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      T.equal(#dlg.images,4,"painting center=1 places road tiles")
      dlg.widgets.scene.onkeydown{code="KeyM"}
      dlg.widgets.tools.onmousedown{button=MouseButton.LEFT,x=18,y=16}
      dlg.widgets.scene.onmousedown{button=MouseButton.LEFT,x=240,y=160}
      dlg.widgets.scene.onmouseup{button=MouseButton.LEFT,x=240,y=160}
      dlg.images={}
      dlg.widgets.scene.onpaint{context=gc}
      T.equal(#dlg.images,4,"rectangle fill places grass tiles")
      for _,draw in ipairs(dlg.images) do
        T.equal(draw.image:getPixel(32,16),gray)
      end
      dlg:close()
    end,debug.traceback)
    Dialog=originalDialog
    sprite:close()
    if not ok then error(err) end
  end)
end
