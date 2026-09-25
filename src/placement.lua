return function(load)
  local M = {}

  -- Atlas row order in docs/references/Bitmask.md, with corner bits
  -- top=8, right=4, bottom=2, left=1.
  local masksByAtlasSlot = {
    0,4,10,1,
    2,12,7,6,
    5,14,15,11,
    8,9,13,3
  }
  local atlasSlotByMask = {}
  for slot=0,15 do
    atlasSlotByMask[masksByAtlasSlot[slot+1]] = slot
  end

  function M.atlasIndex(mask,layout)
    assert(type(mask) == "number" and mask == math.floor(mask)
      and mask >= 0 and mask <= 15)
    if layout == "row" then return mask end
    return atlasSlotByMask[mask]
  end

  function M.new()
    return {rows={},count=0}
  end

  function M.get(state,x,y)
    local row=state.rows[y]
    return row and row[x] or nil
  end

  function M.set(state,x,y,terrain)
    assert(terrain == nil or terrain == 0 or terrain == 1)
    local old = M.get(state,x,y)
    if old == terrain then return false end
    local row = state.rows[y]
    if terrain ~= nil then
      if not row then row = {}; state.rows[y] = row end
      row[x] = terrain
      if old == nil then state.count = state.count + 1 end
    else
      row[x] = nil
      if next(row) == nil then state.rows[y] = nil end
      state.count = state.count - 1
    end
    return true
  end

  function M.count(state)
    return state.count
  end

  function M.rectangle(state,x1,y1,x2,y2,terrain)
    local changed = false
    for y=math.min(y1,y2),math.max(y1,y2) do
      for x=math.min(x1,x2),math.max(x1,x2) do
        if M.set(state,x,y,terrain) then changed = true end
      end
    end
    return changed
  end

  function M.line(state,x1,y1,x2,y2,terrain)
    local dx,dy = math.abs(x2-x1),math.abs(y2-y1)
    local sx,sy = x1 < x2 and 1 or -1,y1 < y2 and 1 or -1
    local err,changed = dx-dy,false
    while true do
      if M.set(state,x1,y1,terrain) then changed = true end
      if x1 == x2 and y1 == y2 then break end
      local twice = 2*err
      if twice > -dy then err,x1 = err-dy,x1+sx end
      if twice < dx then err,y1 = err+dx,y1+sy end
    end
    return changed
  end

  -- NW/NE/SE/SW are the top/right/bottom/left screen corners after
  -- projecting the two logical axes toward right-down and left-down.
  function M.maskAt(state,x,y)
    return (M.get(state,x,y) == 1 and 8 or 0)
      + (M.get(state,x+1,y) == 1 and 4 or 0)
      + (M.get(state,x+1,y+1) == 1 and 2 or 0)
      + (M.get(state,x,y+1) == 1 and 1 or 0)
  end

  function M.tiles(state)
    local candidates,result = {},{}
    local function add(x,y)
      local key = x .. ":" .. y
      if candidates[key] then return end
      candidates[key] = true
      local mask = M.maskAt(state,x,y)
      result[#result+1] = {x=x,y=y,mask=mask}
    end
    for y,row in pairs(state.rows) do
      for x in pairs(row) do
        add(x,y)
        add(x-1,y)
        add(x-1,y-1)
        add(x,y-1)
      end
    end
    table.sort(result,function(a,b)
      local ad,bd = a.x+a.y,b.x+b.y
      if ad ~= bd then return ad < bd end
      return a.x < b.x
    end)
    return result
  end

  function M.screenCenter(x,y,size,scale,originX,originY)
    return originX+(x-y)*size*scale/2,
      originY+(x+y)*size*scale/4
  end

  function M.pick(screenX,screenY,size,scale,originX,originY)
    local a = (screenX-originX)/(size*scale/2)
    local b = (screenY-originY)/(size*scale/4)
    return math.floor((a+b)/2+0.5),math.floor((b-a)/2+0.5)
  end

  return M
end
