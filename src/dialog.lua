return function(load)
  local Errors = load("src/errors.lua")
  local Model = load("src/model.lua")
  local Preview = load("src/preview.lua")
  local Raster = load("src/raster.lua")
  local Document = load("src/document.lua")
  local PreviewWindow = load("src/preview_window.lua")
  local M = {}

  local choices = {
    sizingMode={fixed="固定",stretch="扩展"},
    layout={row="横排 16×1",grid="方阵 4×4"},
    alignment={center="居中",top="顶部"},
    previewMode={extruded="立体",top="平面"}
  }

  function M.displayValue(field, value)
    local map = choices[field]
    return map and map[value] or value
  end

  function M.internalValue(field, label)
    local map = choices[field]
    if map then
      for value, text in pairs(map) do
        if text == label then return value end
      end
    end
    return label
  end

  local function copyTable(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
  end

  local function describe(validation)
    if validation.ok then
      return tostring(validation.sheet.width) .. "×" .. tostring(validation.sheet.height)
    end
    return validation.message
  end

  local function describeCell(validation)
    if not validation.ok then return nil end
    return tostring(validation.cell.width) .. "×" .. tostring(validation.cell.height)
  end

  function M.statusLines(state)
    local validation = state.validation
    local config = state.config
    if not validation.ok then
      local lines
      if validation.code == "FIXED_OVERFLOW" then
        local limit = config.alignment == "top"
          and config.size / 2 or math.floor(config.size / 4)
        lines = {
          "高度超出固定尺寸范围：当前 " .. tostring(config.elevation) .. " px",
          "尺寸 " .. tostring(config.size) .. " px、" ..
            M.displayValue("alignment",config.alignment or "center") ..
            " 对齐时上限 " ..
            tostring(limit) .. " px"
        }
      else
        lines = {"参数错误：" .. validation.message, "请修改参数后再生成"}
      end
      if config.size ~= 64 then
        lines[3] = "! 非 64 px 按参考图最近邻缩放"
      end
      return lines
    end
    local sheet, cell = validation.sheet, validation.cell
    local lines = {
      "图集：宽 " .. sheet.width .. " × 高 " .. sheet.height .. " px",
      "单格：宽 " .. cell.width .. " × 高 " .. cell.height .. " px"
    }
    if config.size ~= 64 then
      lines[3] = "! 非 64 px 按参考图最近邻缩放"
    end
    return lines
  end

  function M.sizeLabel(state)
    return state.config.size == 64 and "尺寸" or "尺寸 !"
  end

  local function baseState()
    local config = Model.defaults()
    return {
      config=config,
      elevationTouched=false,
      validation=Model.validate(config),
      previewMode="extruded",
      previewImage=nil,
      lastValidPreviewImage=nil,
      summary=nil,
      cellSummary=nil,
      generateEnabled=false
    }
  end

  function M.reduce(state, event)
    local fields = {
      SET_SIZE="size",SET_ELEVATION="elevation",
      SET_SIZING_MODE="sizingMode",SET_LAYOUT="layout",
      SET_ALIGNMENT="alignment",SET_OFFSET_X="offsetX",
      SET_OFFSET_Y="offsetY"
    }
    local field = fields[event.type]
    if state.lastValidPreviewImage then
      if field and state.config[field] == event.value then return state end
      if event.type == "SET_PREVIEW_MODE"
          and state.previewMode == event.value then return state end
    end
    local nextState = copyTable(state)
    local config = copyTable(state.config)
    nextState.config = config

    if event.type == "SET_SIZE" then
      config.size = event.value
    elseif event.type == "SET_ELEVATION" then
      config.elevation = event.value
      nextState.elevationTouched = true
    elseif event.type == "SET_SIZING_MODE" then
      config.sizingMode = event.value
    elseif event.type == "SET_LAYOUT" then
      config.layout = event.value
    elseif event.type == "SET_ALIGNMENT" then
      config.alignment = event.value
    elseif event.type == "SET_OFFSET_X" then
      config.offsetX = event.value
    elseif event.type == "SET_OFFSET_Y" then
      config.offsetY = event.value
    elseif event.type == "SET_PREVIEW_MODE" then
      nextState.previewMode = event.value
    else
      error("unknown dialog event: " .. tostring(event.type))
    end

    nextState.validation = Model.validate(config)
    nextState.summary = describe(nextState.validation)
    nextState.cellSummary = describeCell(nextState.validation)
    nextState.generateEnabled = nextState.validation.ok
    if nextState.validation.ok then
      local ok, image = pcall(Preview.render, config, nextState.previewMode)
      if ok then
        nextState.previewImage = image
        nextState.lastValidPreviewImage = image
      end
    end
    return nextState
  end

  function M.initialState()
    local state = baseState()
    return M.reduce(state, {type="SET_PREVIEW_MODE", value=state.previewMode})
  end

  local function fittedRectangle(bounds, image)
    local scale = math.min(bounds.width / image.width, bounds.height / image.height)
    local width = math.max(1, math.floor(image.width * scale + 0.5))
    local height = math.max(1, math.floor(image.height * scale + 0.5))
    return Rectangle(
      bounds.x + math.floor((bounds.width - width) / 2),
      bounds.y + math.floor((bounds.height - height) / 2),
      width, height)
  end

  function M.canvasBounds(gc)
    return Rectangle(0, 0, gc.width, gc.height)
  end

  function M.sideBySide(control, preview, windowWidth, windowHeight)
    local gap = 8
    local x, y = control.x, control.y
    if windowWidth and windowHeight then
      x = math.max(0,math.floor((windowWidth-control.width-gap-preview.width)/2))
      y = math.max(0,math.floor((windowHeight-
        math.max(control.height,preview.height))/2))
    end
    return Rectangle(x,y,control.width,control.height),
      Rectangle(x+control.width+gap,y,preview.width,preview.height)
  end

  function M.showGenerate(dependencies)
    if type(Dialog) ~= "function" then return nil, "UI_UNAVAILABLE" end
    dependencies = dependencies or {}
    local appEvents = dependencies.appEvents or app.events
    local apiVersion = dependencies.apiVersion or app.apiVersion
    local dlg, previewDlg
    local cancelListener
    local comboTimer
    local closing = false
    local function closeBoth(origin)
      if closing then return end
      closing = true
      if cancelListener then
        appEvents:off(cancelListener)
        cancelListener = nil
      end
      if comboTimer then comboTimer:stop() end
      if previewDlg and origin ~= previewDlg then previewDlg:close() end
      if dlg and origin ~= dlg then dlg:close() end
    end
    dlg = Dialog{title="生成等距双网格模板",onclose=function() closeBoth(dlg) end}
    if not dlg then return nil, "UI_UNAVAILABLE" end

    local state = M.initialState()
    local controlsBounds, previewBounds
    local function repaint()
      dlg:modify{id="generate", enabled=state.generateEnabled}
      dlg:modify{id="size",label=M.sizeLabel(state)}
      if controlsBounds then dlg.bounds = controlsBounds end
      if previewDlg then
        local lines = M.statusLines(state)
        previewDlg:modify{id="atlasStatus",text=lines[1] or ""}
        previewDlg:modify{id="cellStatus",text=lines[2] or ""}
        previewDlg:modify{id="scaleStatus",text=lines[3] or ""}
        if previewBounds then previewDlg.bounds = previewBounds end
        previewDlg:repaint()
      end
    end
    local function dispatch(event)
      local nextState = M.reduce(state, event)
      if nextState == state then return end
      state = nextState
      repaint()
    end

    local pendingChanges = {}
    local incompleteOffsets = {}
    local function flushChanges(force)
      if comboTimer then comboTimer:stop() end
      if #pendingChanges == 0 then return end
      local pending = pendingChanges
      pendingChanges = {}
      local latest, order = {}, {}
      for _, event in ipairs(pending) do
        if not latest[event.type] then order[#order+1] = event.type end
        latest[event.type] = event
      end
      local changed = false
      for _, eventType in ipairs(order) do
        local event = latest[eventType]
        if force or (event.value ~= nil and event.value ~= "") then
          local nextState = M.reduce(state,event)
          if nextState ~= state then
            state, changed = nextState, true
          end
        end
      end
      if changed then repaint() end
    end
    local createTimer = dependencies.createTimer or function(options)
      return Timer(options)
    end
    comboTimer = createTimer{interval=0.15,ontick=function() flushChanges(false) end}
    local function queueChange(event)
      if event.type == "SET_OFFSET_X" or event.type == "SET_OFFSET_Y" then
        incompleteOffsets[event.type] =
          event.value == nil or event.value == ""
      end
      pendingChanges[#pendingChanges+1] = event
      comboTimer:stop()
      comboTimer:start()
    end

    local function generateTemplate()
      flushChanges(true)
      for _, name in ipairs({"SET_OFFSET_X","SET_OFFSET_Y"}) do
        if incompleteOffsets[name] then
          dispatch{type=name,value=nil}
          return
        end
      end
      if closing or not state.validation.ok then return end
      local ok, result = xpcall(function()
        return Document.create(state.config, Raster.atlas(state.config))
      end, debug.traceback)
      if not ok then
        app.alert(result)
      else
        closeBoth()
        PreviewWindow.open(result,state.config)
      end
    end

    dlg:number{
      id="size", label=M.sizeLabel(state), text=tostring(state.config.size),
      focus=true,
      onchange=function()
        dispatch{type="SET_SIZE", value=dlg.data.size}
        if state.config.size ~= 64 and app.apiVersion >= 35
            and type(app.tip) == "function" then
          app.tip("非 64 px 尺寸使用最近邻缩放",3)
        end
      end
    }
    dlg:number{
      id="elevation", label="高度", text=tostring(state.config.elevation),
      onchange=function() dispatch{type="SET_ELEVATION", value=dlg.data.elevation} end
    }
    dlg:combobox{
      id="sizingMode", label="模式",
      option=M.displayValue("sizingMode",state.config.sizingMode),
      options={"固定", "扩展"},
      onchange=function() queueChange{type="SET_SIZING_MODE",
        value=M.internalValue("sizingMode",dlg.data.sizingMode)} end
    }
    dlg:combobox{
      id="layout", label="布局",
      option=M.displayValue("layout",state.config.layout),
      options={"横排 16×1", "方阵 4×4"},
      onchange=function() queueChange{type="SET_LAYOUT",
        value=M.internalValue("layout",dlg.data.layout)} end
    }
    dlg:combobox{
      id="alignment", label="对齐",
      option=M.displayValue("alignment",state.config.alignment),
      options={"居中", "顶部"},
      onchange=function() queueChange{type="SET_ALIGNMENT",
        value=M.internalValue("alignment",dlg.data.alignment)} end
    }
    dlg:number{
      id="offsetX", label="偏移 X", text=tostring(state.config.offsetX),
      onchange=function() queueChange{type="SET_OFFSET_X", value=dlg.data.offsetX} end
    }
    dlg:number{
      id="offsetY", label="偏移 Y", text=tostring(state.config.offsetY),
      onchange=function() queueChange{type="SET_OFFSET_Y", value=dlg.data.offsetY} end
    }
    dlg:combobox{
      id="previewMode", label="预览",
      option=M.displayValue("previewMode",state.previewMode),
      options={"立体", "平面"},
      onchange=function() queueChange{type="SET_PREVIEW_MODE",
        value=M.internalValue("previewMode",dlg.data.previewMode)} end
    }
    previewDlg = Dialog{title="模板预览",onclose=function() closeBoth(previewDlg) end}
    if not previewDlg then
      closeBoth()
      return nil, "UI_UNAVAILABLE"
    end
    local initialLines = M.statusLines(state)
    previewDlg:label{id="atlasStatus",text=initialLines[1] or ""}
    previewDlg:newrow{always=true}
    previewDlg:label{id="cellStatus",text=initialLines[2] or ""}
    previewDlg:newrow{always=true}
    previewDlg:label{id="scaleStatus",text=initialLines[3] or ""}
    previewDlg:newrow{always=true}
    previewDlg:canvas{
      id="preview", width=320, height=200,
      onpaint=function(ev)
        local gc = ev.context
        local bounds = M.canvasBounds(gc)
        gc.color = Color{r=158,g=154,b=154,a=255}
        gc:fillRect(bounds)
        local image = state.lastValidPreviewImage
        if image then
          gc:drawImage(image, Rectangle(0, 0, image.width, image.height),
            fittedRectangle(bounds, image))
        end
      end,
      onkeydown=function(ev)
        if ev.code == "Escape" then
          closeBoth()
          if ev.stopPropagation then ev:stopPropagation() end
        elseif ev.code == "Enter" or ev.code == "NumpadEnter" then
          generateTemplate()
          if ev.stopPropagation then ev:stopPropagation() end
        end
      end
    }
    dlg:button{
      id="generate", text="生成", enabled=state.generateEnabled,
      focus=true, onclick=generateTemplate
    }
    dlg:button{id="cancel", text="取消", onclick=function() closeBoth() end}
    -- Keep the preview modeless, then show the controls modally so the
    -- editor cannot steal Tab focus while the generator is open.
    previewDlg:show{wait=false}
    local windowWidth, windowHeight
    if app.apiVersion >= 25 and app.window then
      windowWidth, windowHeight = app.window.width, app.window.height
    end
    controlsBounds, previewBounds = M.sideBySide(
      dlg.bounds,previewDlg.bounds,windowWidth,windowHeight)
    previewDlg.bounds = previewBounds
    if apiVersion >= 24 and appEvents then
      cancelListener = appEvents:on("beforecommand",function(ev)
        if ev.name == "Cancel" then
          closeBoth()
          if ev.stopPropagation then ev.stopPropagation() end
        end
      end)
    end
    dlg:show{wait=true,bounds=controlsBounds}
    return dlg
  end

  return M
end
