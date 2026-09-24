local source = debug.getinfo(1, "S").source
local file = source:sub(1, 1) == "@" and source:sub(2) or source
local testsDir = app.fs.filePath(file)
local root = app.fs.normalizePath(app.fs.joinPath(testsDir, ".."))

local Bootstrap = dofile(app.fs.joinPath(root, "src", "bootstrap.lua"))
local M = { root = root, module = Bootstrap.new(root) }
function M.test(relativePath)
  return dofile(app.fs.joinPath(root, relativePath))
end
return M
