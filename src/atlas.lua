return function(load)
  local Geometry = load("src/geometry.lua")
  local M = {}

  function M.cell(config)
    return Geometry.layout(config).cell
  end

  function M.sheet(config)
    local cell = M.cell(config)
    local columns = config.layout == "row" and 16 or 4
    local rows = config.layout == "row" and 1 or 4
    return {
      width=columns*cell.width, height=rows*cell.height,
      columns=columns, rows=rows, cell=cell
    }
  end

  function M.origin(index, sheet)
    assert(index >= 0 and index <= 15 and index == math.floor(index))
    return {
      x=(index % sheet.columns)*sheet.cell.width,
      y=math.floor(index/sheet.columns)*sheet.cell.height
    }
  end

  return M
end
