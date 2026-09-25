return function(load)
  local Atlas = load("src/atlas.lua")
  local Errors = load("src/errors.lua")
  local M = {}

  function M.defaults()
    return {
      size=64, elevation=16, sizingMode="fixed",
      layout="grid", previewMode="extruded",
      alignment="center", offsetX=0, offsetY=0, sideCopy="off"
    }
  end

  function M.withValue(config, key, value)
    local result = {}
    for name, current in pairs(config) do result[name] = current end
    result[key] = value
    return result
  end

  local function integer(value)
    return type(value) == "number"
      and value == value
      and value ~= math.huge
      and value ~= -math.huge
      and value == math.floor(value)
  end

  function M.validate(config)
    local function invalid(code)
      return {ok=false, code=code, message=Errors.message(code)}
    end
    if not integer(config.size) then return invalid("SIZE_NOT_INTEGER") end
    if config.size % 2 ~= 0 then return invalid("SIZE_NOT_EVEN") end
    if config.size < 16 or config.size > 1024 then
      return invalid("SIZE_OUT_OF_RANGE")
    end
    if not integer(config.elevation) then
      return invalid("ELEVATION_NOT_INTEGER")
    end
    if config.elevation < 0 then return invalid("ELEVATION_NEGATIVE") end
    if config.sizingMode ~= "fixed" and config.sizingMode ~= "stretch" then
      return invalid("MODE_INVALID")
    end
    if config.layout ~= "row" and config.layout ~= "grid" then
      return invalid("LAYOUT_INVALID")
    end
    local sideCopy = config.sideCopy or "off"
    if sideCopy ~= "off" and sideCopy ~= "transparent"
        and sideCopy ~= "opaque" and sideCopy ~= "interlaced" then
      return invalid("SIDE_COPY_INVALID")
    end
    local alignment = config.alignment or "center"
    if alignment ~= "center" and alignment ~= "top" then
      return invalid("ALIGNMENT_INVALID")
    end
    for _, name in ipairs({"offsetX", "offsetY"}) do
      if config[name] ~= nil and not integer(config[name]) then
        return invalid("OFFSET_NOT_INTEGER")
      end
    end
    local fixedLimit = alignment == "center" and config.size / 4
      or config.size / 2
    if config.sizingMode == "fixed"
        and config.elevation > fixedLimit then
      return invalid("FIXED_OVERFLOW")
    end
    local sheet = Atlas.sheet(config)
    if sheet.width > 16384 or sheet.height > 16384 then
      return invalid("ATLAS_SIDE_LIMIT")
    end
    if sheet.width * sheet.height > 16777216 then
      return invalid("ATLAS_PIXEL_LIMIT")
    end
    return {ok=true, cell=sheet.cell, sheet=sheet}
  end

  return M
end
