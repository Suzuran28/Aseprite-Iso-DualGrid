return function(load)
  local Seams = load("src/seams.lua")
  local M = {}

  local states = {
    [0]={kind="empty", paths={}, inverted=false},
    [1]={kind="cap_sw", paths={"cap_sw"}, inverted=false},
    [2]={kind="cap_se", paths={"cap_se"}, inverted=false},
    [3]={kind="bridge_s", paths={"bridge_down"}, inverted=true},
    [4]={kind="cap_ne", paths={"cap_ne"}, inverted=false},
    [5]={kind="diagonal_ne_sw", paths={"cap_ne","cap_sw"}, inverted=false},
    [6]={kind="bridge_e", paths={"bridge_up"}, inverted=false},
    [7]={kind="missing_nw", paths={"cap_nw"}, inverted=true},
    [8]={kind="cap_nw", paths={"cap_nw"}, inverted=false},
    [9]={kind="bridge_w", paths={"bridge_up"}, inverted=true},
    [10]={kind="diagonal_nw_se", paths={"cap_nw","cap_se"}, inverted=false},
    [11]={kind="missing_ne", paths={"cap_ne"}, inverted=true},
    [12]={kind="bridge_n", paths={"bridge_down"}, inverted=false},
    [13]={kind="missing_se", paths={"cap_se"}, inverted=true},
    [14]={kind="missing_sw", paths={"cap_sw"}, inverted=true},
    [15]={kind="full", paths={}, inverted=false}
  }

  local function validIndex(index)
    return type(index) == "number" and index == math.floor(index)
      and index >= 0 and index <= 15
  end

  local function stateFor(index)
    assert(validIndex(index), "variant index must be an integer from 0 to 15")
    return states[index]
  end

  function M.label(index)
    stateFor(index)
    return string.format("%d%d%d%d",
      math.floor(index / 8) % 2,
      math.floor(index / 4) % 2,
      math.floor(index / 2) % 2,
      index % 2)
  end

  function M.corners(index)
    stateFor(index)
    return {
      nw=math.floor(index / 8) % 2 == 1,
      ne=math.floor(index / 4) % 2 == 1,
      se=math.floor(index / 2) % 2 == 1,
      sw=index % 2 == 1
    }
  end

  function M.build(index)
    local state = stateFor(index)
    local paths = {}
    for i, id in ipairs(state.paths) do
      paths[i] = Seams.path(id)
    end
    return {
      index=index,
      label=M.label(index),
      kind=state.kind,
      paths=paths,
      inverted=state.inverted
    }
  end

  function M.all()
    local result = {}
    for index = 0, 15 do result[index + 1] = M.build(index) end
    return result
  end

  return M
end
