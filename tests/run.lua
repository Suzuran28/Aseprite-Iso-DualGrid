local source = debug.getinfo(1, "S").source
local file = source:sub(1, 1) == "@" and source:sub(2) or source
local testsDir = app.fs.filePath(file)
local B = dofile(app.fs.joinPath(testsDir, "bootstrap.lua"))
local T = B.test("tests/harness.lua")
local suites = {
  "tests/smoke_test.lua",
  "tests/model_test.lua",
  "tests/geometry_test.lua",
  "tests/variants_test.lua",
  "tests/raster_test.lua",
  "tests/document_test.lua",
  "tests/preview_test.lua",
  "tests/preview_window_test.lua",
  "tests/placement_test.lua",
  "tests/placement_window_test.lua",
  "tests/dialog_test.lua",
  "tests/export_test.lua"
}

for _, path in ipairs(suites) do
  B.test(path)(T, B.root, B.module)
end
T.finish()
