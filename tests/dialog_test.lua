return function(T, root, load)
  local DialogUI = load("src/dialog.lua")
  local Model = load("src/model.lua")

  local function initialState()
    local config = Model.defaults()
    return {
      config=config,
      elevationTouched=false,
      validation=Model.validate(config),
      previewMode="extruded",
      previewImage=nil,
      lastValidPreviewImage=nil
    }
  end

  T.test("size changes preserve elevation and revalidate the fixed limit", function()
    local state = DialogUI.reduce(initialState(), {type="SET_SIZE", value=32})
    T.equal(state.config.size, 32)
    T.equal(state.config.elevation, 16)
    T.equal(state.validation.code,"FIXED_OVERFLOW")
    T.equal(state.generateEnabled,false)
    T.equal(state.elevationTouched, false)
  end)

  T.test("touched elevation survives later size changes", function()
    local state = DialogUI.reduce(initialState(), {type="SET_ELEVATION", value=12})
    state = DialogUI.reduce(state, {type="SET_SIZE", value=32})
    T.equal(state.config.elevation, 12)
    T.equal(state.elevationTouched, true)
  end)

  T.test("invalid fixed height retains the last valid preview and disables generation", function()
    local valid = DialogUI.reduce(initialState(), {type="SET_ELEVATION", value=8})
    valid = DialogUI.reduce(valid, {type="SET_SIZE", value=32})
    local preview = valid.lastValidPreviewImage
    T.truthy(preview)
    local invalid = DialogUI.reduce(valid, {type="SET_ELEVATION", value=32})
    T.equal(invalid.validation.ok, false)
    T.equal(invalid.validation.code, "FIXED_OVERFLOW")
    T.equal(invalid.lastValidPreviewImage, preview)
    T.equal(invalid.previewImage, preview)
    T.equal(invalid.generateEnabled, false)
  end)

  T.test("stretch accepts a full-size elevation and reports its output dimensions", function()
    local state = DialogUI.reduce(initialState(), {type="SET_SIZE", value=32})
    state = DialogUI.reduce(state, {type="SET_ELEVATION", value=32})
    state = DialogUI.reduce(state, {type="SET_SIZING_MODE", value="stretch"})
    T.truthy(state.validation.ok)
    T.equal(state.cellSummary, "32×56")
    T.equal(state.generateEnabled, true)
  end)

  T.test("layout updates the output summary", function()
    local state = DialogUI.reduce(initialState(), {type="SET_SIZE", value=32})
    state = DialogUI.reduce(state, {type="SET_ELEVATION", value=0})
    T.equal(state.summary, "128×128")
    state = DialogUI.reduce(state, {type="SET_LAYOUT", value="row"})
    T.equal(state.summary, "512×32")
  end)

  T.test("alignment and offsets flow into generation state", function()
    local state = DialogUI.reduce(initialState(), {type="SET_ALIGNMENT", value="top"})
    state = DialogUI.reduce(state, {type="SET_OFFSET_X", value=-4})
    state = DialogUI.reduce(state, {type="SET_OFFSET_Y", value=6})
    T.equal(state.config.alignment, "top")
    T.equal(state.config.offsetX, -4)
    T.equal(state.config.offsetY, 6)
    T.truthy(state.generateEnabled)
  end)

  T.test("showGenerate reports unavailable UI when Dialog construction fails", function()
    local original = Dialog
    Dialog = function() return nil end
    local result, code = DialogUI.showGenerate()
    Dialog = original
    T.equal(result, nil)
    T.equal(code, "UI_UNAVAILABLE")
  end)

  T.test("unchanged offset input does not regenerate the preview", function()
    local state = DialogUI.initialState()
    T.equal(DialogUI.reduce(state,{type="SET_OFFSET_X",value=0}),state)
    T.equal(DialogUI.reduce(state,{type="SET_OFFSET_Y",value=0}),state)
  end)

  T.test("generator choices show Chinese labels while keeping internal values", function()
    T.equal(DialogUI.displayValue("sizingMode","fixed"),"固定")
    T.equal(DialogUI.displayValue("sizingMode","stretch"),"扩展")
    T.equal(DialogUI.internalValue("sizingMode","扩展"),"stretch")
    T.equal(DialogUI.displayValue("alignment","center"),"居中")
    T.equal(DialogUI.internalValue("layout","方阵 4×4"),"grid")
    T.equal(DialogUI.displayValue("previewMode","extruded"),"立体")
  end)

  T.test("switching fixed alignment changes the elevation limit", function()
    local state = DialogUI.reduce(initialState(), {type="SET_ELEVATION", value=32})
    T.equal(state.validation.code,"FIXED_OVERFLOW")
    state = DialogUI.reduce(state,{type="SET_ALIGNMENT",value="top"})
    T.truthy(state.validation.ok)
    T.equal(state.cellSummary,"64×64")
    state = DialogUI.reduce(state,{type="SET_ALIGNMENT",value="center"})
    T.equal(state.validation.code,"FIXED_OVERFLOW")
  end)

  T.test("status names dimensions and gives the actual height limit", function()
    local valid = DialogUI.initialState()
    local lines = DialogUI.statusLines(valid)
    T.match(lines[1],"图集")
    T.match(lines[1],"256")
    T.match(lines[2],"单格")
    local invalid = DialogUI.reduce(valid,{type="SET_SIZE",value=32})
    lines = DialogUI.statusLines(invalid)
    T.match(lines[1],"16")
    T.match(lines[2],"8")
    T.match(lines[2],"居中")
    local scaled = DialogUI.reduce(valid,{type="SET_SIZE",value=128})
    lines = DialogUI.statusLines(scaled)
    T.match(lines[3],"最近邻")
  end)

  T.test("preview canvas derives its rectangle from the graphics context", function()
    local bounds = DialogUI.canvasBounds({width=320,height=220})
    T.equal(bounds.x, 0)
    T.equal(bounds.y, 0)
    T.equal(bounds.width, 320)
    T.equal(bounds.height, 220)
  end)

  T.test("side-by-side generator panels fit a 1244 by 640 window", function()
    local controls, preview = DialogUI.sideBySide(
      Rectangle(0,0,300,360),Rectangle(0,0,640,500),1244,640)
    T.truthy(controls.x >= 0 and controls.y >= 0)
    T.truthy(preview.x >= controls.x + controls.width)
    T.truthy(preview.x + preview.width <= 1244)
    T.truthy(preview.y + preview.height <= 640)
  end)

  T.test("warning recovery does not resize the generator dialog", function()
    local originalDialog = Dialog
    local dialogs = {}
    Dialog = function(options)
      local dlg = {options=options,data={},widgets={},modified={},
        bounds=Rectangle(10,10,400,500)}
      for _, method in ipairs({"number","combobox","label","canvas",
          "button","newrow"}) do
        dlg[method] = function(self, spec)
          if spec and spec.id then self.widgets[spec.id] = spec end
          return self
        end
      end
      function dlg:modify(spec)
        self.modifyCount = (self.modifyCount or 0) + 1
        if spec.id then self.modified[spec.id] = spec end
        if spec.text or spec.label then
          self.bounds = Rectangle(self.bounds.x,self.bounds.y,
            400 + #(spec.text or spec.label),self.bounds.height)
        end
        return self
      end
      function dlg:repaint() return self end
      function dlg:show() return self end
      function dlg:close()
        if self.options.onclose then self.options.onclose() end
      end
      dialogs[#dialogs+1] = dlg
      return dlg
    end
    local ok, err = xpcall(function()
      local controls = DialogUI.showGenerate()
      local preview = dialogs[2]
      local width = controls.bounds.width
      local modifications = controls.modifyCount or 0
      controls.data.offsetX = 0
      controls.widgets.offsetX.onchange()
      T.equal(controls.modifyCount or 0,modifications)
      controls.data.elevation = 32
      controls.widgets.elevation.onchange()
      T.equal(controls.bounds.width,width)
      T.match(preview.modified.cellStatus.text,"居中")
      controls.data.elevation = 16
      controls.widgets.elevation.onchange()
      T.equal(controls.bounds.width,width)
      T.match(preview.modified.atlasStatus.text,"图集")
      controls.data.size = 128
      controls.widgets.size.onchange()
      T.match(controls.modified.size.label,"!")
      T.match(preview.modified.scaleStatus.text,"最近邻")
      controls.data.size = 64
      controls.widgets.size.onchange()
      T.equal(controls.modified.size.label,"尺寸")
      controls:close()
    end,debug.traceback)
    Dialog = originalDialog
    if not ok then error(err) end
  end)

  T.test("generator keeps native status beside a horizontal preview panel", function()
    local originalDialog = Dialog
    local Document = load("src/document.lua")
    local PreviewWindow = load("src/preview_window.lua")
    local originalCreate, originalOpen = Document.create, PreviewWindow.open
    local dialogs, shown = {}, {}
    Dialog = function(options)
      local dlg = {options=options,widgets={},order={},data={},closeCount=0,
        bounds=Rectangle(10,10,300,360)}
      for _, method in ipairs({"number","combobox","label","canvas",
          "button","newrow"}) do
        dlg[method] = function(self, spec)
          if spec and spec.id then
            self.widgets[spec.id] = spec
            self.order[#self.order+1] = spec.id
          end
          return self
        end
      end
      function dlg:modify(spec)
        if spec and spec.focus then
          T.equal(shown[#shown],self)
          self.focusedId = spec.id
        end
        return self
      end
      function dlg:repaint() return self end
      function dlg:show(options)
        if options and options.bounds then self.bounds = options.bounds end
        self.showOptions = options
        shown[#shown+1] = self
        return self
      end
      function dlg:close()
        self.closeCount = self.closeCount + 1
        if self.options.onclose then self.options.onclose() end
      end
      dialogs[#dialogs+1] = dlg
      return dlg
    end
    local ok, err = xpcall(function()
      local controls = DialogUI.showGenerate()
      T.equal(#dialogs,2)
      local preview = dialogs[2]
      T.equal(shown[1],preview)
      T.equal(shown[2],controls)
      T.equal(preview.showOptions.wait,false)
      T.equal(controls.showOptions.wait,true)
      T.truthy(controls.widgets.size.focus)
      T.equal(controls.showOptions.bounds.x,controls.bounds.x)
      T.equal(controls.order[1],"size")
      T.equal(controls.order[2],"elevation")
      T.equal(controls.order[3],"sizingMode")
      T.equal(controls.widgets.sizingMode.label,"模式")
      T.equal(controls.widgets.sizingMode.option,"固定")
      T.equal(controls.widgets.sizingMode.options[2],"扩展")
      T.equal(controls.widgets.previewMode.options[1],"立体")
      T.equal(controls.widgets.preview,nil)
      T.truthy(preview.widgets.preview)
      T.truthy(preview.widgets.atlasStatus)
      T.truthy(preview.widgets.cellStatus)
      T.truthy(preview.bounds.x >= controls.bounds.x + controls.bounds.width)
      T.truthy(controls.widgets.generate.focus)
      local key = {code="Escape",stopped=false}
      function key:stopPropagation() self.stopped = true end
      preview.widgets.preview.onkeydown(key)
      T.truthy(key.stopped)
      T.equal(controls.closeCount,1)
      T.equal(preview.closeCount,1)
      local generated, opened = 0, 0
      Document.create = function()
        generated = generated + 1
        return {}
      end
      PreviewWindow.open = function()
        opened = opened + 1
      end
      local nextControls = DialogUI.showGenerate()
      local nextPreview = dialogs[4]
      local enter = {code="Enter",stopped=false}
      function enter:stopPropagation() self.stopped = true end
      nextPreview.widgets.preview.onkeydown(enter)
      T.equal(generated,1)
      T.equal(opened,1)
      T.truthy(enter.stopped)
      T.equal(nextControls.closeCount,1)
      T.equal(nextPreview.closeCount,1)
      nextPreview.widgets.preview.onkeydown{code="Enter"}
      T.equal(generated,1)
      local cancelHandler, unsubscribed
      local appEvents = {
        on=function(self,name,handler)
          T.equal(name,"beforecommand")
          cancelHandler = handler
          return 1
        end,
        off=function(self,id)
          T.equal(id,1)
          unsubscribed = true
        end
      }
      local finalControls = DialogUI.showGenerate{
        appEvents=appEvents,apiVersion=39}
      local finalPreview = dialogs[6]
      T.truthy(cancelHandler)
      local stopped = false
      cancelHandler{name="Cancel",stopPropagation=function() stopped=true end}
      T.equal(finalControls.closeCount,1)
      T.equal(finalPreview.closeCount,1)
      T.truthy(unsubscribed)
      T.truthy(stopped)
    end,debug.traceback)
    Dialog = originalDialog
    Document.create, PreviewWindow.open = originalCreate, originalOpen
    if not ok then error(err) end
  end)

  T.test("combobox selection updates after its popup has closed", function()
    local originalDialog = Dialog
    local dialogs, popupOpen, timer = {}, false, nil
    Dialog = function(options)
      local dlg = {options=options,data={},widgets={},modified={},
        bounds=Rectangle(10,10,300,360)}
      for _, method in ipairs({"number","combobox","label","canvas",
          "button","newrow"}) do
        dlg[method] = function(self,spec)
          if spec and spec.id then self.widgets[spec.id] = spec end
          return self
        end
      end
      function dlg:modify(spec)
        if popupOpen then error("dialog relayout while combobox popup is open") end
        self.modifyCount = (self.modifyCount or 0) + 1
        if spec.id then self.modified[spec.id] = spec end
        return self
      end
      function dlg:repaint() return self end
      function dlg:show() return self end
      function dlg:close()
        if self.options.onclose then self.options.onclose() end
      end
      dialogs[#dialogs+1] = dlg
      return dlg
    end
    local ok, err = xpcall(function()
      local controls = DialogUI.showGenerate{createTimer=function(options)
        timer = {options=options,isRunning=false}
        function timer:start() self.isRunning=true end
        function timer:stop() self.isRunning=false end
        function timer:fire() self.options.ontick() end
        return timer
      end}
      popupOpen = true
      controls.data.sizingMode = "扩展"
      controls.widgets.sizingMode.onchange()
      popupOpen = false
      T.truthy(timer and timer.isRunning)
      timer:fire()
      T.match(dialogs[2].modified.atlasStatus.text,"高 256 px")
      T.match(dialogs[2].modified.cellStatus.text,"高 64 px")
      local modifications = controls.modifyCount or 0
      controls.data.offsetX = nil
      controls.widgets.offsetX.onchange()
      timer:fire()
      T.equal(controls.modifyCount or 0,modifications)
      controls.data.offsetX = -4
      controls.widgets.offsetX.onchange()
      timer:fire()
      T.truthy((controls.modifyCount or 0) > modifications)
      controls:close()
      T.equal(timer.isRunning,false)
    end,debug.traceback)
    Dialog = originalDialog
    if not ok then error(err) end
  end)
end
