local anchors = {
  nw={x=16,y=8}, ne={x=48,y=8},
  se={x=48,y=24}, sw={x=16,y=24}
}

local paths = {
  cap_nw = {
    points={
      anchors.nw, {x=20,y=8}, {x=24,y=6}, {x=32,y=3},
      {x=40,y=6}, {x=44,y=8}, anchors.ne
    },
    wallEdges={
      normal={false,false,false,false,false,false},
      inverted={true,true,true,true,true,true}
    }
  },
  cap_ne = {
    points={
      anchors.ne, {x=50,y=10}, {x=55,y=14}, {x=56,y=16},
      {x=55,y=18}, {x=50,y=22}, anchors.se
    },
    wallEdges={
      normal={false,false,false,true,true,true},
      inverted={true,true,true,false,false,false}
    }
  },
  cap_se = {
    points={
      anchors.se, {x=44,y=24}, {x=40,y=26}, {x=32,y=29},
      {x=24,y=26}, {x=20,y=24}, anchors.sw
    },
    wallEdges={
      normal={true,true,true,true,true,true},
      inverted={false,false,false,false,false,false}
    }
  },
  cap_sw = {
    points={
      anchors.sw, {x=14,y=22}, {x=9,y=18}, {x=8,y=16},
      {x=9,y=14}, {x=14,y=10}, anchors.nw
    },
    wallEdges={
      normal={true,true,true,false,false,false},
      inverted={false,false,false,true,true,true}
    }
  },
  bridge_down = {
    points={
      anchors.nw, {x=24,y=9}, {x=29,y=13}, {x=35,y=19},
      {x=40,y=23}, anchors.se
    },
    wallEdges={
      normal={false,false,false,true,true},
      inverted={true,true,true,false,false}
    }
  },
  bridge_up = {
    points={
      anchors.ne, {x=40,y=9}, {x=35,y=13}, {x=29,y=19},
      {x=24,y=23}, anchors.sw
    },
    wallEdges={
      normal={false,false,false,true,true},
      inverted={true,true,true,false,false}
    }
  }
}

for id, path in pairs(paths) do
  local segments = #path.points - 1
  assert(#path.wallEdges.normal == segments,
    "invalid normal wall edge count for " .. id)
  assert(#path.wallEdges.inverted == segments,
    "invalid inverted wall edge count for " .. id)
end

local function clonePath(path)
  local points, normal, inverted = {}, {}, {}
  for i, point in ipairs(path.points) do
    points[i] = {x=point.x, y=point.y}
  end
  for i, edge in ipairs(path.wallEdges.normal) do normal[i] = edge end
  for i, edge in ipairs(path.wallEdges.inverted) do inverted[i] = edge end
  return {
    points=points,
    wallEdges={normal=normal, inverted=inverted}
  }
end

local M = {}

function M.path(id)
  local path = paths[id]
  if not path then return nil end
  return clonePath(path)
end

return M
