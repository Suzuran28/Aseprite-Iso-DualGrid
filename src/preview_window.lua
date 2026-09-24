return function(load)
  local Document = load("src/document.lua")
  local Preview = load("src/preview.lua")
  local M = {}
  local activeWindow

  function M.newState(sprite, config)
    return {sprite=sprite,config=config,includeGuides=true,zoom=0,
      panX=0,panY=0,dirty=true,image=nil}
  end

  function M.reduce(state, event)
    local nextState = {}
    for key, value in pairs(state) do nextState[key] = value end
    if event.type == "RENDERED" then
      nextState.image, nextState.dirty = event.image, false
    elseif event.type == "SOURCE_CHANGED" or event.type == "REFRESH" then
      nextState.dirty = true
    elseif event.type == "SET_GUIDES" then
      nextState.includeGuides, nextState.dirty = event.value, true
    elseif event.type == "SET_ZOOM" then
      nextState.zoom = event.value
    elseif event.type == "PAN_BY" then
      nextState.panX = state.panX + event.dx
      nextState.panY = state.panY + event.dy
    else
      error("unknown preview event: " .. tostring(event.type))
    end
    return nextState
  end

  function M.fitZoom(viewWidth, viewHeight, imageWidth, imageHeight)
    local fit = math.min(viewWidth/imageWidth,viewHeight/imageHeight)
    if fit >= 1 then return math.floor(fit) end
    return fit
  end

  local function drawImage(gc, image, zoom, panX, panY)
    if not image then return end
    local scale = zoom == 0
      and M.fitZoom(gc.width,gc.height,image.width,image.height) or zoom
    local width = math.max(1, math.floor(image.width * scale + 0.5))
    local height = math.max(1, math.floor(image.height * scale + 0.5))
    gc:drawImage(image,Rectangle(0,0,image.width,image.height),Rectangle(
      math.floor((gc.width-width)/2)+panX,
      math.floor((gc.height-height)/2)+panY,width,height))
  end

  function M.wheelZoom(zoom, deltaY, fit)
    if not deltaY or deltaY == 0 then return zoom end
    local current = zoom == 0 and fit or zoom
    local factor = deltaY < 0 and 1.25 or 0.8
    local minimum = math.min(0.125,fit/8)
    local maximum = math.max(16,fit*8)
    local result = current * factor
    if result >= 1 then
      result = factor > 1 and math.ceil(result) or math.floor(result)
    end
    return math.max(minimum,math.min(maximum,result))
  end

  local function withServices(overrides)
    overrides = overrides or {}
    return {
      apiVersion=overrides.apiVersion or app.apiVersion,
      getActive=overrides.getActive or function() return app.activeSprite end,
      appEvents=overrides.appEvents or app.events,
      isTemplate=overrides.isTemplate or Document.isTemplate,
      loadConfig=overrides.loadConfig or Document.loadConfig,
      renderSource=overrides.renderSource or Preview.renderSource,
      createTimer=overrides.createTimer or function(options) return Timer(options) end
    }
  end

  function M.open(sprite, config, overrides)
    if type(Dialog) ~= "function" then return nil, "UI_UNAVAILABLE" end
    local services = withServices(overrides)
    local state = M.newState(sprite, config)
    local dlg, timer, appListener
    local closed, rendering = false, false
    local boundSprite, spriteListeners = nil, {}
    local currentSite = sprite
    local viewWidth, viewHeight = 480, 320
    local dragging, lastX, lastY = false, 0, 0

    local function unbindSprite()
      if boundSprite then
        for _, listener in ipairs(spriteListeners) do
          boundSprite.events:off(listener)
        end
      end
      boundSprite, spriteListeners = nil, {}
    end
    local function release()
      if closed then return end
      closed = true
      if timer then timer:stop() end
      if appListener then services.appEvents:off(appListener); appListener = nil end
      unbindSprite()
      if activeWindow and activeWindow.dialog == dlg then activeWindow = nil end
    end
    local options = {title="等距双网格预览",onclose=release}
    if app.apiVersion >= 35 then options.resizeable = true end
    dlg = Dialog(options)
    if not dlg then return nil, "UI_UNAVAILABLE" end
    if activeWindow then
      local previous = activeWindow
      previous.release()
      previous.dialog:close()
    end

    local function schedule()
      if not closed and timer and not timer.isRunning then timer:start() end
    end
    local function sourceChanged()
      if closed or rendering then return end
      state.dirty = true
      schedule()
    end
    local function bindSprite(nextSprite, nextConfig)
      if boundSprite == nextSprite then
        state.config = nextConfig
        return
      end
      unbindSprite()
      boundSprite = nextSprite
      state.sprite, state.config = nextSprite, nextConfig
      state.image, state.dirty, state.zoom = nil, true, 0
      state.panX, state.panY = 0, 0
      dragging = false
      if nextSprite then
        local names = {"change"}
        if services.apiVersion >= 34 then
          names[#names+1] = "layervisibility"
          names[#names+1] = "layeropacity"
          names[#names+1] = "layerblendmode"
        end
        for _, name in ipairs(names) do
          spriteListeners[#spriteListeners+1] =
            nextSprite.events:on(name,sourceChanged)
        end
      end
    end
    local function syncActive()
      local current = services.getActive()
      if current == currentSite then return end
      currentSite = current
      if current and services.isTemplate(current) then
        bindSprite(current,services.loadConfig(current))
      else
        bindSprite(nil,nil)
      end
    end

    timer = services.createTimer{interval=0.1,ontick=function()
      timer:stop()
      if not closed then
        syncActive()
        dlg:repaint()
      end
    end}
    bindSprite(sprite,config)
    appListener = services.appEvents:on("sitechange",function()
      if not rendering then schedule() end
    end)
    activeWindow = {dialog=dlg,release=release}
    dlg:check{id="guides",text="辅助线",selected=true,onclick=function()
      state = M.reduce(state,{type="SET_GUIDES",value=dlg.data.guides})
      dlg:repaint()
    end}
    dlg:newrow()
    dlg:canvas{id="preview",width=480,height=320,autoscaling=true,
      onpaint=function(ev)
        local gc = ev.context
        viewWidth, viewHeight = gc.width, gc.height
        gc.color = Color{r=96,g=88,b=96,a=255}
        gc:fillRect(Rectangle(0,0,gc.width,gc.height))
        syncActive()
        if state.dirty then
          if state.sprite and services.isTemplate(state.sprite) then
            state.config = services.loadConfig(state.sprite)
            rendering = true
            local ok, image = pcall(services.renderSource,state.sprite,
              state.config,state.includeGuides)
            rendering = false
            if ok then
              state = M.reduce(state,{type="RENDERED",image=image})
            else
              state.image, state.dirty = nil, false
              print(image)
            end
          else
            state.image, state.dirty = nil, false
          end
        end
        if state.image then
          drawImage(gc,state.image,state.zoom,state.panX,state.panY)
        else
          gc.color = Color{r=240,g=240,b=240,a=255}
          gc:fillText("请选择活动中的等距双网格模板",8,8)
        end
      end,
      onwheel=function(ev)
        local fit = state.image
          and M.fitZoom(viewWidth,viewHeight,state.image.width,state.image.height)
          or 1
        state = M.reduce(state,{type="SET_ZOOM",
          value=M.wheelZoom(state.zoom,ev.deltaY,fit)})
        dlg:repaint()
      end,
      onmousedown=function(ev)
        if ev.button == MouseButton.RIGHT then
          dragging, lastX, lastY = true, ev.x, ev.y
        end
      end,
      onmousemove=function(ev)
        if dragging then
          local dx, dy = ev.x-lastX, ev.y-lastY
          lastX, lastY = ev.x, ev.y
          if dx ~= 0 or dy ~= 0 then
            state = M.reduce(state,{type="PAN_BY",dx=dx,dy=dy})
            dlg:repaint()
          end
        end
      end,
      onmouseup=function(ev)
        if ev.button == MouseButton.RIGHT then dragging = false end
      end
    }
    dlg:show{wait=false}
    return dlg
  end

  function M.openActive()
    local sprite = app.activeSprite
    local config = Document.loadConfig(sprite)
    if not config or not Document.isTemplate(sprite) then return nil, "PREVIEW_CONFIG_INVALID" end
    return M.open(sprite,config)
  end

  return M
end
