return function(load)
  local Atlas = load("src/atlas.lua")
  local Document = load("src/document.lua")
  local Placement = load("src/placement.lua")
  local Preview = load("src/preview.lua")
  local M = {}
  local activeWindow

  local tools = {
    {id="brush",label="画笔 (B)"},
    {id="rectangle",label="矩形填充 (M)"},
    {id="eraser",label="橡皮擦 (E)"}
  }
  local toolWidth,toolGap,toolHeight = 94,6,26
  local terrainButtons = {
    {value=0,mask=0,x=6,shortcut="1"},
    {value=1,mask=15,x=48,shortcut="2"}
  }
  local terrainKeys = {Digit1=0,Numpad1=0,Digit2=1,Numpad2=1}
  local layerWidth,layerHeader,layerRow = 140,26,22

  function M.newState(sprite,config)
    local stack=Placement.newStack()
    return {sprite=sprite,config=config,stack=stack,
      tool=nil,terrain=1,zoom=1,panX=0,panY=0,
      tiles=nil,fadedTiles=nil,dirty=true}
  end

  function M.selectTool(state,tool)
    assert(tool == "brush" or tool == "rectangle" or tool == "eraser")
    if state.tool == tool then state.tool=nil else state.tool=tool end
  end

  function M.selectTerrain(state,terrain)
    assert(terrain == 0 or terrain == 1)
    state.terrain=terrain
  end

  local function sourceTiles(sprite,config)
    local flattened = Preview.flattenSource(sprite,false)
    local sheet = Atlas.sheet(config)
    local result = {}
    for mask=0,15 do
      local origin = Atlas.origin(Placement.atlasIndex(mask,config.layout),sheet)
      result[mask] = Image(flattened,Rectangle(origin.x,origin.y,
        sheet.cell.width,sheet.cell.height))
    end
    return result
  end

  local function servicesFor(overrides)
    overrides=overrides or {}
    return {
      apiVersion=overrides.apiVersion or app.apiVersion,
      getActive=overrides.getActive or function() return app.activeSprite end,
      appEvents=overrides.appEvents or app.events,
      isTemplate=overrides.isTemplate or Document.isTemplate,
      loadConfig=overrides.loadConfig or Document.loadConfig,
      confirmDelete=overrides.confirmDelete or function(layer)
        return app.alert{title="删除图层",
          text="确定删除“" .. layer.name .. "”？",
          buttons={"删除","取消"}} == 1
      end,
      makeTiles=overrides.makeTiles or sourceTiles
    }
  end

  local function drawGrid(gc,state,originX,originY)
    local size,scale = state.config.size,state.zoom
    local minX,maxX,minY,maxY = math.huge,-math.huge,math.huge,-math.huge
    for _,point in ipairs({{0,0},{gc.width,0},{0,gc.height},
        {gc.width,gc.height}}) do
      local x,y = Placement.pick(point[1],point[2],size,scale,originX,originY)
      minX,maxX = math.min(minX,x),math.max(maxX,x)
      minY,maxY = math.min(minY,y),math.max(maxY,y)
    end
    gc.color = Color{r=220,g=230,b=240,a=100}
    gc.strokeWidth = 1
    gc:beginPath()
    for x=minX-2,maxX+2 do
      local x1,y1=Placement.screenCenter(x+0.5,minY-3,
        size,scale,originX,originY)
      local x2,y2=Placement.screenCenter(x+0.5,maxY+3,
        size,scale,originX,originY)
      gc:moveTo(x1,y1)
      gc:lineTo(x2,y2)
    end
    for y=minY-2,maxY+2 do
      local x1,y1=Placement.screenCenter(minX-3,y+0.5,
        size,scale,originX,originY)
      local x2,y2=Placement.screenCenter(maxX+3,y+0.5,
        size,scale,originX,originY)
      gc:moveTo(x1,y1)
      gc:lineTo(x2,y2)
    end
    gc:stroke()
  end

  local function drawTiles(gc,state,originX,originY)
    if not state.tiles then return end
    local size,scale = state.config.size,state.zoom
    local baseTop = state.config.alignment == "top" and 0
      or math.floor(size/4)
    for index,layer in ipairs(state.stack.layers) do
      local images=state.stack.selected and state.stack.selected ~= index
        and state.fadedTiles or state.tiles
      for _,record in ipairs(Placement.tiles(layer.ground)) do
        local image = images and images[record.mask]
        if image then
          local cx,cy = Placement.screenCenter(record.x,record.y,
            size,scale,originX,originY)
          local x = math.floor(cx-size*scale/2+0.5)
          local y = math.floor(cy+Placement.layerOffset(index,
            state.config.elevation,scale)
            -baseTop*scale+0.5)
          local width = math.max(1,math.floor(image.width*scale+0.5))
          local height = math.max(1,math.floor(image.height*scale+0.5))
          if x < gc.width and y < gc.height and x+width > 0
              and y+height > 0 then
            gc:drawImage(image,Rectangle(0,0,image.width,image.height),
              Rectangle(x,y,width,height))
          end
        end
      end
    end
  end

  local function fadeTiles(tiles)
    local faded={}
    for mask=0,15 do
      local source=tiles[mask]
      if source and source.pixels then
        local image=Image(source)
        for pixel in image:pixels() do
          local color=pixel()
          local alpha=app.pixelColor.rgbaA(color)
          if alpha > 0 then
            pixel(app.pixelColor.rgba(app.pixelColor.rgbaR(color),
              app.pixelColor.rgbaG(color),app.pixelColor.rgbaB(color),
              math.floor(alpha*0.3+0.5)))
          end
        end
        faded[mask]=image
      else
        faded[mask]=source
      end
    end
    return faded
  end

  local function drawRectanglePreview(gc,state,drag,originX,originY)
    if not drag or drag.mode ~= "rectangle" then return end
    local minX,maxX = math.min(drag.x,drag.toX),math.max(drag.x,drag.toX)
    local minY,maxY = math.min(drag.y,drag.toY),math.max(drag.y,drag.toY)
    gc.color = Color{r=255,g=218,b=94,a=255}
    gc.strokeWidth = 2
    gc:beginPath()
    for y=minY,maxY do
      for x=minX,maxX do
        local cx,cy = Placement.screenCenter(x,y,state.config.size,
          state.zoom,originX,originY)
        local rx,ry = state.config.size*state.zoom/2,
          state.config.size*state.zoom/4
        gc:moveTo(cx,cy-ry)
        gc:lineTo(cx+rx,cy)
        gc:lineTo(cx,cy+ry)
        gc:lineTo(cx-rx,cy)
        gc:closePath()
      end
    end
    gc:stroke()
  end

  function M.open(sprite,config,overrides)
    if type(Dialog) ~= "function" then return nil,"UI_UNAVAILABLE" end
    local services=servicesFor(overrides)
    local state=M.newState(sprite,config)
    local dlg,appListener,boundSprite,spriteListeners
    local closed,rendering=false,false
    local drag
    local sceneWidth,sceneHeight,toolbarWidth=480,320,620
    local layerCanvasHeight,layerScroll,layerDrag=320,0,nil
    local pointerTarget

    local function unbind()
      if boundSprite then
        for _,listener in ipairs(spriteListeners) do
          boundSprite.events:off(listener)
        end
      end
      boundSprite,spriteListeners=nil,{}
    end
    local function release()
      if closed then return end
      closed=true
      if appListener then services.appEvents:off(appListener) end
      unbind()
      if activeWindow and activeWindow.dialog == dlg then activeWindow=nil end
    end
    local options={title="等距双网格铺设测试",onclose=release}
    if services.apiVersion >= 35 then options.resizeable=true end
    dlg=Dialog(options)
    if not dlg then return nil,"UI_UNAVAILABLE" end
    if activeWindow then
      local previous=activeWindow
      previous.release()
      previous.dialog:close()
    end

    local function bind(nextSprite,nextConfig)
      if boundSprite == nextSprite then
        state.config=nextConfig
        state.dirty=true
        return
      end
      unbind()
      boundSprite=nextSprite
      state=M.newState(nextSprite,nextConfig)
      drag=nil
      layerScroll,layerDrag=0,nil
      pointerTarget=nil
      if nextSprite then
        local names={"change"}
        if services.apiVersion >= 34 then
          names[#names+1]="layervisibility"
          names[#names+1]="layeropacity"
          names[#names+1]="layerblendmode"
        end
        for _,name in ipairs(names) do
          spriteListeners[#spriteListeners+1]=nextSprite.events:on(name,function()
            if not closed and not rendering then
              state.dirty=true
              dlg:repaint()
            end
          end)
        end
      end
    end
    local function syncActive()
      local current=services.getActive()
      if current == boundSprite then return end
      if current and services.isTemplate(current) then
        bind(current,services.loadConfig(current))
      else
        bind(nil,nil)
      end
    end
    local function ensureTiles()
      syncActive()
      if not state.dirty then return end
      if state.sprite then
        local latest=services.loadConfig(state.sprite)
        if latest then state.config=latest end
        rendering=true
        local ok,result=pcall(services.makeTiles,state.sprite,state.config)
        rendering=false
        if ok then
          state.tiles=result
          state.fadedTiles=fadeTiles(result)
        else
          state.tiles,state.fadedTiles=nil,nil
          print(result)
        end
      else
        state.tiles,state.fadedTiles=nil,nil
      end
      state.dirty=false
    end
    local function repaint()
      if not closed then dlg:repaint() end
    end
    local function select(tool)
      M.selectTool(state,tool)
      drag=nil
      repaint()
    end
    local function keydown(ev)
      local tool=({KeyB="brush",KeyM="rectangle",KeyE="eraser"})[ev.code]
      local terrain=terrainKeys[ev.code]
      if terrain ~= nil and not (ev.altKey or ev.ctrlKey
          or ev.metaKey or ev.shiftKey) then
        M.selectTerrain(state,terrain)
        repaint()
      elseif tool then
        select(tool)
      elseif ev.code == "Escape" then
        state.tool=nil
        drag=nil
        repaint()
      else
        return
      end
      if ev.stopPropagation then ev:stopPropagation() end
    end
    local function origin()
      return sceneWidth/2+state.panX,sceneHeight/2+state.panY
    end
    local function layerOrigin()
      local ox,oy=origin()
      if state.stack.selected then
        oy=oy+Placement.layerOffset(state.stack.selected,
          state.config.elevation,state.zoom)
      end
      return ox,oy
    end
    local function pick(ev)
      local ox,oy=layerOrigin()
      return Placement.pick(ev.x,ev.y,state.config.size,state.zoom,ox,oy)
    end
    local function selectedGround()
      local index=state.stack.selected
      return index and state.stack.layers[index].ground or nil
    end
    local function paintTerrain()
      if state.tool == "eraser" then return nil end
      return state.terrain
    end

    bind(sprite,config)
    appListener=services.appEvents:on("sitechange",function()
      if not closed and not rendering then
        syncActive()
        repaint()
      end
    end)
    activeWindow={dialog=dlg,release=release}

    dlg:canvas{id="tools",width=620,height=36,autoscaling=true,
      onpaint=function(ev)
        local gc=ev.context
        toolbarWidth=gc.width
        ensureTiles()
        gc.color=Color{r=55,g=59,b=66,a=255}
        gc:fillRect(Rectangle(0,0,gc.width,gc.height))
        for _,button in ipairs(terrainButtons) do
          gc.color=state.terrain == button.value
            and Color{r=78,g=122,b=170,a=255}
            or Color{r=124,g=128,b=134,a=255}
          gc:fillRect(Rectangle(button.x,2,36,32))
          gc.color=Color{r=83,g=88,b=96,a=255}
          gc:fillRect(Rectangle(button.x+2,4,32,28))
          local image=state.tiles and state.tiles[button.mask]
          if image then
            local fit=math.min(32/image.width,28/image.height)
            local width=math.max(1,math.floor(image.width*fit+0.5))
            local height=math.max(1,math.floor(image.height*fit+0.5))
            gc:drawImage(image,
              Rectangle(0,0,image.width,image.height),
              Rectangle(button.x+2+math.floor((32-width)/2),
                4+math.floor((28-height)/2),width,height))
          end
          gc.color=Color{r=30,g=34,b=40,a=255}
          gc:fillRect(Rectangle(button.x+26,22,9,11))
          gc.color=Color{r=255,g=255,b=255,a=255}
          gc:fillText(button.shortcut,button.x+27,22)
        end
        local total=#tools*toolWidth+(#tools-1)*toolGap
        local left=layerWidth+math.floor((gc.width-layerWidth-total)/2)
        for i,item in ipairs(tools) do
          local x=left+(i-1)*(toolWidth+toolGap)
          gc.color=state.tool == item.id
            and Color{r=78,g=122,b=170,a=255}
            or Color{r=83,g=88,b=96,a=255}
          gc:fillRect(Rectangle(x,5,toolWidth,toolHeight))
          gc.color=Color{r=255,g=255,b=255,a=255}
          gc:fillText(item.label,x+7,10)
        end
      end,
      onmousedown=function(ev)
        if ev.button ~= MouseButton.LEFT then return end
        for _,button in ipairs(terrainButtons) do
          if ev.x >= button.x and ev.x < button.x+36
              and ev.y >= 2 and ev.y < 34 then
            M.selectTerrain(state,button.value)
            repaint()
            return
          end
        end
        local total=#tools*toolWidth+(#tools-1)*toolGap
        local left=layerWidth+math.floor((toolbarWidth-layerWidth-total)/2)
        for i,item in ipairs(tools) do
          local x=left+(i-1)*(toolWidth+toolGap)
          if ev.x >= x and ev.x < x+toolWidth
              and ev.y >= 5 and ev.y < 5+toolHeight then
            select(item.id)
            break
          end
        end
      end,
      onkeydown=keydown
    }
    dlg:newrow{always=true}
    local function visibleLayerCount()
      return math.max(1,math.floor((layerCanvasHeight-layerHeader)/layerRow))
    end
    local function layerAt(y)
      if y < layerHeader then return nil end
      local row=math.floor((y-layerHeader)/layerRow)
      if row >= visibleLayerCount() then return nil end
      local index=#state.stack.layers-layerScroll-row
      if index < 1 then return nil end
      return index
    end
    local layersSpec={
      onpaint=function(ev)
        local gc=ev.context
        layerCanvasHeight=gc.height
        local theme=app.theme.color
        gc.color=theme.window_face
        gc:fillRect(Rectangle(0,0,layerWidth,gc.height))
        gc:drawThemeRect("button_normal",Rectangle(4,3,64,18))
        gc:drawThemeRect("button_normal",Rectangle(72,3,64,18))
        gc.color=theme.button_normal_text
        gc:fillText("+ 新建",10,6)
        gc.color=state.stack.selected and theme.button_normal_text
          or theme.menuitem_disabled_text
        gc:fillText("删选中",84,6)
        for row=0,visibleLayerCount()-1 do
          local index=#state.stack.layers-layerScroll-row
          local layer=state.stack.layers[index]
          if layer then
            local y=layerHeader+row*layerRow
            local selected=index == state.stack.selected
            gc:drawThemeRect(selected and "timeline_clicked"
              or "timeline_normal",Rectangle(1,y,layerWidth-2,layerRow))
            gc:drawThemeImage("tiles",6,y+8)
            gc.color=selected and theme.timeline_clicked_text
              or theme.timeline_active_text
            gc:fillText(layer.name,18,y+5)
            if state.config then
              local height=(index-1)*state.config.elevation
              gc:fillText(height .. "px",79,y+5)
            end
            gc:drawThemeRect("button_normal",
              Rectangle(116,y+2,20,18))
            gc.color=theme.button_normal_text
            gc:fillText("复",121,y+5)
          end
        end
        gc.color=theme.timeline_padding
        gc:fillRect(Rectangle(layerWidth-1,0,1,gc.height))
      end,
      onwheel=function(ev)
        if not ev.deltaY or ev.deltaY == 0 then return end
        local maximum=math.max(0,#state.stack.layers-visibleLayerCount())
        layerScroll=math.max(0,math.min(maximum,
          layerScroll+(ev.deltaY > 0 and 1 or -1)))
        repaint()
      end,
      onmousedown=function(ev)
        if ev.button ~= MouseButton.LEFT then return end
        drag=nil
        layerDrag=nil
        if ev.y < layerHeader then
          if ev.x >= 4 and ev.x < 68 then
            Placement.addLayer(state.stack)
            layerScroll=0
          elseif ev.x >= 72 and ev.x < 136 and state.stack.selected then
            local index=state.stack.selected
            if services.confirmDelete(state.stack.layers[index]) then
              Placement.deleteLayer(state.stack,index)
              layerScroll=math.min(layerScroll,
                math.max(0,#state.stack.layers-visibleLayerCount()))
            end
          end
          repaint()
          return
        end
        local index=layerAt(ev.y)
        if not index then return end
        if ev.x >= 114 then
          Placement.copyLayer(state.stack,index)
          layerScroll=0
        else
          layerDrag={index=index,y=ev.y}
        end
        repaint()
      end,
      onmousemove=function(ev)
        if layerDrag and math.abs(ev.y-layerDrag.y) >= 5 then
          layerDrag.moved=true
        end
      end,
      onmouseup=function(ev)
        if not layerDrag or ev.button ~= MouseButton.LEFT then return end
        local target=layerAt(ev.y)
        if layerDrag.moved and target then
          Placement.moveLayer(state.stack,layerDrag.index,target)
        elseif not layerDrag.moved then
          Placement.selectLayer(state.stack,layerDrag.index)
        end
        layerDrag=nil
        repaint()
      end,
      onkeydown=keydown
    }
    local sceneSpec={
      onpaint=function(ev)
        local gc=ev.context
        sceneWidth,sceneHeight=gc.width,gc.height
        gc.color=Color{r=74,g=76,b=82,a=255}
        gc:fillRect(Rectangle(0,0,gc.width,gc.height))
        ensureTiles()
        if state.config then
          local ox,oy=origin()
          drawTiles(gc,state,ox,oy)
          if state.tool and state.stack.selected then
            local layerX,layerY=layerOrigin()
            drawGrid(gc,state,layerX,layerY)
            drawRectanglePreview(gc,state,drag,layerX,layerY)
          end
        else
          gc.color=Color{r=240,g=240,b=240,a=255}
          gc:fillText("请选择活动中的等距双网格模板",8,8)
        end
      end,
      onwheel=function(ev)
        if not state.config or not ev.deltaY or ev.deltaY == 0 then return end
        local old=state.zoom
        local nextZoom=math.max(0.5,math.min(8,
          old*(ev.deltaY < 0 and 1.25 or 0.8)))
        local mx,my=ev.x or sceneWidth/2,ev.y or sceneHeight/2
        local ox,oy=origin()
        state.zoom=nextZoom
        state.panX=mx+(ox-mx)*nextZoom/old-sceneWidth/2
        state.panY=my+(oy-my)*nextZoom/old-sceneHeight/2
        repaint()
      end,
      onmousedown=function(ev)
        if not state.config then return end
        if (ev.spaceKey and (ev.button == MouseButton.LEFT
            or ev.button == MouseButton.RIGHT))
            or (not state.tool and ev.button == MouseButton.RIGHT) then
          drag={mode="pan",button=ev.button,x=ev.x,y=ev.y}
        elseif ev.button == MouseButton.LEFT and state.tool
            and selectedGround() then
          local x,y=pick(ev)
          drag={mode=state.tool == "rectangle" and "rectangle" or "paint",
            button=ev.button,x=x,y=y,toX=x,toY=y}
          if drag.mode == "paint" then
            Placement.set(selectedGround(),x,y,paintTerrain())
            repaint()
          end
        end
      end,
      onmousemove=function(ev)
        if not drag then return end
        if drag.mode == "pan" then
          state.panX=state.panX+ev.x-drag.x
          state.panY=state.panY+ev.y-drag.y
          drag.x,drag.y=ev.x,ev.y
          repaint()
        elseif state.config then
          local x,y=pick(ev)
          if drag.mode == "paint" then
            if Placement.line(selectedGround(),drag.toX,drag.toY,x,y,
                paintTerrain()) then
              repaint()
            end
          else
            if drag.toX ~= x or drag.toY ~= y then repaint() end
          end
          drag.toX,drag.toY=x,y
        end
      end,
      onmouseup=function(ev)
        if not drag or ev.button ~= drag.button then return end
        if drag.mode == "rectangle" and state.config then
          local x,y=pick(ev)
          Placement.rectangle(selectedGround(),drag.x,drag.y,x,y,
            paintTerrain())
        end
        drag=nil
        repaint()
      end,
      onkeydown=keydown
    }
    local function shiftedContext(gc)
      local shifted={width=math.max(1,gc.width-layerWidth),height=gc.height}
      function shifted:fillRect(rect)
        gc:fillRect(Rectangle(rect.x+layerWidth,rect.y,
          rect.width,rect.height))
      end
      function shifted:fillText(value,x,y)
        gc:fillText(value,x+layerWidth,y)
      end
      function shifted:drawImage(image,source,destination)
        gc:drawImage(image,source,Rectangle(destination.x+layerWidth,
          destination.y,destination.width,destination.height))
      end
      function shifted:beginPath() gc:beginPath() end
      function shifted:moveTo(x,y) gc:moveTo(x+layerWidth,y) end
      function shifted:lineTo(x,y) gc:lineTo(x+layerWidth,y) end
      function shifted:closePath() gc:closePath() end
      function shifted:stroke() gc:stroke() end
      return setmetatable(shifted,{
        __index=function(_,key) return gc[key] end,
        __newindex=function(_,key,value) gc[key]=value end
      })
    end
    local function sceneEvent(ev)
      return setmetatable({x=ev.x and ev.x-layerWidth or nil},{
        __index=function(_,key) return ev[key] end
      })
    end
    dlg:canvas{id="workspace",width=620,height=320,
      autoscaling=true,focus=true,
      onpaint=function(ev)
        sceneSpec.onpaint{context=shiftedContext(ev.context)}
        layersSpec.onpaint(ev)
      end,
      onmousedown=function(ev)
        if ev.x < layerWidth then
          pointerTarget="layers"
          layersSpec.onmousedown(ev)
        else
          pointerTarget="scene"
          sceneSpec.onmousedown(sceneEvent(ev))
        end
      end,
      onmousemove=function(ev)
        if pointerTarget == "layers" then
          layersSpec.onmousemove(ev)
        elseif pointerTarget == "scene" then
          sceneSpec.onmousemove(sceneEvent(ev))
        end
      end,
      onmouseup=function(ev)
        if pointerTarget == "layers" then
          layersSpec.onmouseup(ev)
        elseif pointerTarget == "scene" then
          sceneSpec.onmouseup(sceneEvent(ev))
        end
        pointerTarget=nil
      end,
      onwheel=function(ev)
        if ev.x and ev.x < layerWidth then
          layersSpec.onwheel(ev)
        else
          sceneSpec.onwheel(sceneEvent(ev))
        end
      end,
      onkeydown=keydown
    }
    dlg:show{wait=false}
    return dlg
  end

  function M.openActive()
    local sprite=app.activeSprite
    local config=Document.loadConfig(sprite)
    if not config or not Document.isTemplate(sprite) then
      return nil,"PREVIEW_CONFIG_INVALID"
    end
    return M.open(sprite,config)
  end

  return M
end
