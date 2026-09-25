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

  function M.newState(sprite,config)
    return {sprite=sprite,config=config,ground=Placement.new(),tool=nil,
      terrain=1,
      zoom=1,panX=0,panY=0,tiles=nil,dirty=true}
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
    for _,record in ipairs(Placement.tiles(state.ground)) do
      local image = state.tiles[record.mask]
      if image then
        local cx,cy = Placement.screenCenter(record.x,record.y,
          size,scale,originX,originY)
        local x = math.floor(cx-size*scale/2+0.5)
        local y = math.floor(cy-baseTop*scale+0.5)
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
    local sceneWidth,sceneHeight,toolbarWidth=480,320,480

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
        if ok then state.tiles=result else state.tiles=nil; print(result) end
      else
        state.tiles=nil
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
    local function pick(ev)
      local ox,oy=origin()
      return Placement.pick(ev.x,ev.y,state.config.size,state.zoom,ox,oy)
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

    dlg:canvas{id="tools",width=480,height=36,autoscaling=true,
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
        local left=math.floor((gc.width-total)/2)
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
        local left=math.floor((toolbarWidth-total)/2)
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
    dlg:canvas{id="scene",width=480,height=320,autoscaling=true,focus=true,
      onpaint=function(ev)
        local gc=ev.context
        sceneWidth,sceneHeight=gc.width,gc.height
        gc.color=Color{r=74,g=76,b=82,a=255}
        gc:fillRect(Rectangle(0,0,gc.width,gc.height))
        ensureTiles()
        if state.config then
          local ox,oy=origin()
          drawTiles(gc,state,ox,oy)
          if state.tool then
            drawGrid(gc,state,ox,oy)
            drawRectanglePreview(gc,state,drag,ox,oy)
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
        elseif ev.button == MouseButton.LEFT and state.tool then
          local x,y=pick(ev)
          drag={mode=state.tool == "rectangle" and "rectangle" or "paint",
            button=ev.button,x=x,y=y,toX=x,toY=y}
          if drag.mode == "paint" then
            Placement.set(state.ground,x,y,paintTerrain())
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
            if Placement.line(state.ground,drag.toX,drag.toY,x,y,
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
          Placement.rectangle(state.ground,drag.x,drag.y,x,y,
            paintTerrain())
        end
        drag=nil
        repaint()
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
