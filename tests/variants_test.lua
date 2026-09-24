return function(T, root, load)
  local Variants = load("src/variants.lua")
  local Seams = load("src/seams.lua")

  T.test("encodes mask labels in NW NE SE SW bit order", function()
    T.equal(Variants.label(0), "0000")
    T.equal(Variants.label(5), "0101")
    T.equal(Variants.label(10), "1010")
    T.equal(Variants.label(15), "1111")

    local ten = Variants.corners(10)
    T.equal(ten.nw, true)
    T.equal(ten.ne, false)
    T.equal(ten.se, true)
    T.equal(ten.sw, false)
  end)

  T.test("builds all sixteen canonical marching-squares states", function()
    local expected = {
      [0]="empty", [1]="cap_sw", [2]="cap_se", [3]="bridge_s",
      [4]="cap_ne", [5]="diagonal_ne_sw", [6]="bridge_e",
      [7]="missing_nw", [8]="cap_nw", [9]="bridge_w",
      [10]="diagonal_nw_se", [11]="missing_ne",
      [12]="bridge_n", [13]="missing_se", [14]="missing_sw",
      [15]="full"
    }
    local expectedPaths = {
      [0]=0, [1]=1, [2]=1, [3]=1, [4]=1, [5]=2, [6]=1, [7]=1,
      [8]=1, [9]=1, [10]=2, [11]=1, [12]=1, [13]=1, [14]=1, [15]=0
    }
    local expectedInverted = {
      [0]=false, [1]=false, [2]=false, [3]=true, [4]=false, [5]=false,
      [6]=false, [7]=true, [8]=false, [9]=true, [10]=false, [11]=true,
      [12]=false, [13]=true, [14]=true, [15]=false
    }

    local all = Variants.all()
    T.equal(#all, 16)
    for i = 0, 15 do
      local state = Variants.build(i)
      T.equal(all[i + 1].index, i)
      T.equal(all[i + 1].label, Variants.label(i))
      T.equal(state.index, i)
      T.equal(state.label, Variants.label(i))
      T.equal(state.kind, expected[i])
      T.equal(#state.paths, expectedPaths[i])
      T.equal(state.inverted, expectedInverted[i])
    end
  end)

  T.test("resolves each state to its canonical seam polylines", function()
    local expectedPaths = {
      [1]="cap_sw", [2]="cap_se", [3]="bridge_down", [4]="cap_ne",
      [5]="cap_ne", [6]="bridge_up", [7]="cap_nw", [8]="cap_nw",
      [9]="bridge_up", [10]="cap_nw", [11]="cap_ne", [12]="bridge_down",
      [13]="cap_se", [14]="cap_sw"
    }

    for index, pathId in pairs(expectedPaths) do
      local state = Variants.build(index)
      local path = Seams.path(pathId)
      T.equal(state.paths[1].points[1].x, path.points[1].x)
      T.equal(state.paths[1].points[1].y, path.points[1].y)
      T.equal(#state.paths[1].wallEdges.normal, #state.paths[1].points - 1)
      T.equal(#state.paths[1].wallEdges.inverted, #state.paths[1].points - 1)
    end
  end)

  T.test("returns independent named seam path records", function()
    local first = Seams.path("cap_nw")
    first.points[1].x = -1
    first.wallEdges.normal[1] = not first.wallEdges.normal[1]

    local second = Seams.path("cap_nw")
    T.equal(second.points[1].x, 16)
    T.equal(second.points[1].y, 8)
    T.equal(second.wallEdges.normal[1], false)
  end)

  T.test("returns independent variant builds and all-state records", function()
    local first = Variants.build(5)
    first.paths[1].points[1].x = -1
    first.inverted = true

    local second = Variants.build(5)
    T.equal(second.paths[1].points[1].x, 48)
    T.equal(second.inverted, false)

    local all = Variants.all()
    all[1].label = "mutated"
    T.equal(Variants.all()[1].label, "0000")
  end)
end
