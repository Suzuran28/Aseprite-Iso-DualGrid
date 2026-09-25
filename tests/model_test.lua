return function(T, root, load)
local Model = load("src/model.lua")
local Atlas = load("src/atlas.lua")
local Errors = load("src/errors.lua")

local function invalid(config, code)
  local result = Model.validate(config)
  T.equal(result.ok, false)
  T.equal(result.code, code)
  T.equal(result.message, Errors.message(code))
end

T.test("valid fixed and stretch formulas", function()
  local fixed = { size=64, elevation=16, sizingMode="fixed", layout="row" }
  local stretch = { size=32, elevation=32, sizingMode="stretch", layout="grid" }

  local fixedResult = Model.validate(fixed)
  T.truthy(fixedResult.ok)
  T.equal(fixedResult.cell.width, 64)
  T.equal(fixedResult.cell.height, 64)
  T.equal(fixedResult.cell.topY, 16)
  T.equal(fixedResult.sheet.width, 1024)
  T.equal(fixedResult.sheet.height, 64)

  local stretchResult = Model.validate(stretch)
  T.truthy(stretchResult.ok)
  T.equal(stretchResult.cell.height, 64)
  T.equal(stretchResult.cell.topY, 8)
  T.equal(stretchResult.sheet.width, 128)
  T.equal(stretchResult.sheet.height, 256)
end)

T.test("defaults provide the documented fixed grid configuration", function()
  local config = Model.defaults()
  T.equal(config.size, 64)
  T.equal(config.elevation, 16)
  T.equal(config.sizingMode, "fixed")
  T.equal(config.layout, "grid")
  T.equal(config.previewMode, "extruded")
  T.equal(config.alignment, "center")
  T.equal(config.offsetX, 0)
  T.equal(config.offsetY, 0)
  T.equal(config.sideCopy, "off")
end)

T.test("accepts only the four same-side copy modes", function()
  for _, mode in ipairs({"off", "transparent", "opaque", "interlaced"}) do
    local cfg = Model.withValue(Model.defaults(), "sideCopy", mode)
    T.truthy(Model.validate(cfg).ok, mode)
  end
  invalid(Model.withValue(Model.defaults(), "sideCopy", "unknown"),
    "SIDE_COPY_INVALID")
end)

T.test("withValue returns a copy without mutating its input", function()
  local config = Model.defaults()
  local changed = Model.withValue(config, "size", 32)
  T.equal(config.size, 64)
  T.equal(changed.size, 32)
  T.equal(changed.elevation, 16)
end)

T.test("fixed cell exposes diamond and wall boundaries", function()
  local cell = Atlas.cell({ size=64, elevation=16, sizingMode="fixed" })
  T.equal(cell.diamondHeight, 32)
  T.equal(cell.topY, 16)
  T.equal(cell.topBottomY, 48)
  T.equal(cell.wallBottomY, 64)
end)

T.test("atlas origins use row and grid slot geometry", function()
  local row = Atlas.sheet({ size=16, elevation=0, sizingMode="fixed", layout="row" })
  local grid = Atlas.sheet({ size=16, elevation=0, sizingMode="fixed", layout="grid" })
  local rowOrigin = Atlas.origin(15, row)
  local gridOrigin = Atlas.origin(6, grid)
  T.equal(rowOrigin.x, 240)
  T.equal(rowOrigin.y, 0)
  T.equal(gridOrigin.x, 32)
  T.equal(gridOrigin.y, 16)
end)

T.test("stable errors return Chinese messages", function()
  T.equal(Errors.message("SIZE_NOT_INTEGER"), "基础尺寸必须是整数。")
  T.equal(Errors.message("SAVE_FAILED"), "PNG 保存失败。")
end)

T.test("returns the evenness error before range error for size 15", function()
  invalid({ size=15, elevation=0, sizingMode="fixed", layout="row" }, "SIZE_NOT_EVEN")
end)

T.test("rejects odd size after integer validation", function()
  invalid({ size=17, elevation=0, sizingMode="fixed", layout="row" }, "SIZE_NOT_EVEN")
end)

T.test("rejects decimal size", function()
  invalid({ size=18.5, elevation=0, sizingMode="fixed", layout="row" }, "SIZE_NOT_INTEGER")
end)

T.test("rejects NaN-like size", function()
  invalid({ size=0/0, elevation=0, sizingMode="fixed", layout="row" }, "SIZE_NOT_INTEGER")
end)

T.test("rejects string size without coercion", function()
  invalid({ size="64", elevation=0, sizingMode="fixed", layout="row" }, "SIZE_NOT_INTEGER")
end)

T.test("rejects zero size after evenness check", function()
  invalid({ size=0, elevation=0, sizingMode="fixed", layout="row" }, "SIZE_OUT_OF_RANGE")
end)

T.test("rejects infinite size", function()
  invalid({ size=math.huge, elevation=0, sizingMode="fixed", layout="row" }, "SIZE_NOT_INTEGER")
end)

T.test("rejects negative elevation", function()
  invalid({ size=16, elevation=-1, sizingMode="fixed", layout="row" }, "ELEVATION_NEGATIVE")
end)

T.test("rejects decimal elevation", function()
  invalid({ size=16, elevation=1.25, sizingMode="fixed", layout="row" }, "ELEVATION_NOT_INTEGER")
end)

T.test("fixed elevation limit follows the vertical alignment", function()
  local center = { size=64, elevation=16, sizingMode="fixed",
    layout="row", alignment="center" }
  T.truthy(Model.validate(center).ok)
  invalid(Model.withValue(center,"elevation",17), "FIXED_OVERFLOW")
  local top = Model.withValue(center,"alignment","top")
  top.elevation = 32
  T.truthy(Model.validate(top).ok)
  invalid(Model.withValue(top,"elevation",33), "FIXED_OVERFLOW")
  invalid({ size=18, elevation=5, sizingMode="fixed", layout="row",
    alignment="center" }, "FIXED_OVERFLOW")
end)

T.test("rejects invalid sizing mode before layout", function()
  invalid({ size=16, elevation=0, sizingMode="other", layout="other" }, "MODE_INVALID")
end)

T.test("rejects invalid layout", function()
  invalid({ size=16, elevation=0, sizingMode="fixed", layout="other" }, "LAYOUT_INVALID")
end)

T.test("accepts atlas side boundary", function()
  local result = Model.validate({ size=16, elevation=4080, sizingMode="stretch", layout="grid" })
  T.truthy(result.ok)
  T.equal(result.sheet.height, 16384)
end)

T.test("rejects the first atlas side overflow", function()
  invalid({ size=16, elevation=4081, sizingMode="stretch", layout="grid" }, "ATLAS_SIDE_LIMIT")
end)

T.test("accepts atlas pixel boundary", function()
  local result = Model.validate({ size=1024, elevation=0, sizingMode="stretch", layout="grid" })
  T.truthy(result.ok)
  T.equal(result.sheet.width * result.sheet.height, 16777216)
end)

T.test("rejects the first atlas pixel overflow below the side cap", function()
  invalid({ size=1024, elevation=1, sizingMode="stretch", layout="grid" }, "ATLAS_PIXEL_LIMIT")
end)
end
