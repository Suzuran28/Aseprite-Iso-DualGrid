return function(T, root, load)
  local Placement = load("src/placement.lua")

  T.test("one painted ground cell selects four corner masks", function()
    local state = Placement.new()
    Placement.set(state,0,0,1)
    T.equal(Placement.maskAt(state,0,0),8)
    T.equal(Placement.maskAt(state,-1,0),4)
    T.equal(Placement.maskAt(state,-1,-1),2)
    T.equal(Placement.maskAt(state,0,-1),1)
    T.equal(Placement.maskAt(state,1,1),0)
    T.equal(#Placement.tiles(state),4)
  end)

  T.test("grass zero is painted terrain while erase is unassigned", function()
    local state=Placement.new()
    Placement.set(state,0,0,0)
    T.equal(Placement.get(state,0,0),0)
    T.equal(Placement.count(state),1)
    local tiles=Placement.tiles(state)
    T.equal(#tiles,4)
    for _,tile in ipairs(tiles) do T.equal(tile.mask,0) end
    Placement.set(state,0,0,1)
    T.equal(Placement.count(state),1)
    T.equal(Placement.maskAt(state,0,0),8)
    Placement.set(state,0,0,nil)
    T.equal(Placement.get(state,0,0),nil)
    T.equal(Placement.count(state),0)
    T.equal(#Placement.tiles(state),0)
  end)

  T.test("all corner masks resolve to the documented atlas coordinates", function()
    -- Row-major atlas slots from Bitmask.md. Bit values are top=8,
    -- right=4, bottom=2, left=1.
    local slotsByMask = {
      [0]=0,[1]=3,[2]=4,[3]=15,[4]=1,[5]=8,[6]=7,[7]=6,
      [8]=12,[9]=13,[10]=2,[11]=11,[12]=5,[13]=14,[14]=9,[15]=10
    }
    for mask=0,15 do
      T.equal(Placement.atlasIndex(mask),slotsByMask[mask],
        "wrong atlas slot for mask " .. mask)
    end
    T.equal(Placement.atlasIndex(8)%4,0,"top-only tile is column 0")
    T.equal(math.floor(Placement.atlasIndex(8)/4),3,
      "top-only tile is row 3")
  end)

  T.test("row atlases keep their mask-index slot order", function()
    for mask=0,15 do
      T.equal(Placement.atlasIndex(mask,"row"),mask)
    end
  end)

  T.test("rectangle fills inclusive ground cells and eraser removes them", function()
    local state = Placement.new()
    Placement.rectangle(state,1,1,-1,0,1)
    T.equal(Placement.count(state),6)
    T.equal(Placement.maskAt(state,-1,0),15)
    Placement.set(state,0,0,nil)
    T.equal(Placement.count(state),5)
    T.equal(Placement.maskAt(state,0,0),7)
  end)

  T.test("screen picking and unshifted grid use the same lattice", function()
    local size, scale = 64, 2
    local x,y = Placement.screenCenter(2,-1,size,scale,240,160)
    local cx,cy = Placement.pick(x,y,size,scale,240,160)
    T.equal(cx,2)
    T.equal(cy,-1)
    cx,cy = Placement.pick(240,160,size,scale,240,160)
    T.equal(cx,0)
    T.equal(cy,0)
  end)

  T.test("brush line includes every crossed grid cell", function()
    local state = Placement.new()
    Placement.line(state,-2,-2,2,2,1)
    T.equal(Placement.count(state),5)
    for i=-2,2 do T.truthy(Placement.get(state,i,i)) end
  end)
end
