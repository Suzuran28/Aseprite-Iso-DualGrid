local M = {}

function M.new(root)
  local cache = {}
  local loading = {}
  local function load(relativePath)
    if cache[relativePath] ~= nil then return cache[relativePath] end
    if loading[relativePath] then
      error("circular module dependency: " .. relativePath)
    end
    loading[relativePath] = true
    local ok, exported = xpcall(function()
      local value = dofile(app.fs.joinPath(root, relativePath))
      if type(value) == "function" then value = value(load) end
      return value
    end, debug.traceback)
    loading[relativePath] = nil
    if not ok then error(exported) end
    cache[relativePath] = exported
    return exported
  end
  return load
end

return M
