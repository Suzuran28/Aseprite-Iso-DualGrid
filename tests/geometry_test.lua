return function(T, root, load)
  local Geometry = load("src/geometry.lua")
  local Model = load("src/model.lua")

  local function config(alignment, offsetX, offsetY)
    return {
      size=64, elevation=16, sizingMode="fixed", layout="row",
      alignment=alignment, offsetX=offsetX, offsetY=offsetY
    }
  end

  T.test("center and top anchors use the approved 64px vertical extents", function()
    local center = Geometry.layout(config("center", 0, 0))
    local top = Geometry.layout(config("top", 0, 0))

    T.equal(center.content.minY, 16)
    T.equal(center.content.maxY, 64)
    T.equal(center.cell.width, 64)
    T.equal(center.cell.height, 64)
    T.equal(top.content.minY, 0)
    T.equal(top.content.maxY, 48)
    T.equal(top.cell.width, 64)
    T.equal(top.cell.height, 64)
  end)

  T.test("fixed offsets translate content within a clipped 64px cell", function()
    local layout = Geometry.layout(config("center", -7, 30))
    local translated = Geometry.toCell({x=0, y=0}, layout)
    T.equal(layout.cell.width,64)
    T.equal(layout.cell.height,64)
    T.equal(layout.origin.x,0)
    T.equal(layout.origin.y,0)
    T.equal(translated.x,-7)
    T.equal(translated.y,46)
  end)

  T.test("stretch offsets enlarge cells for both negative and positive reach", function()
    local negative = config("center",-7,-25)
    negative.sizingMode = "stretch"
    local left = Geometry.layout(negative)
    T.equal(left.cell.width,71)
    T.equal(left.cell.height,89)
    T.equal(left.translation.x,0)
    T.equal(left.translation.y,0)
    local positive = config("center",7,30)
    positive.sizingMode = "stretch"
    local right = Geometry.layout(positive)
    T.equal(right.cell.width,71)
    T.equal(right.cell.height,94)
    T.equal(right.translation.x,7)
    T.equal(right.translation.y,46)
  end)

  T.test("validation rejects fractional offsets and unknown alignment", function()
    local cfg = Model.defaults()
    cfg.offsetX = 1.5
    T.equal(Model.validate(cfg).code, "OFFSET_NOT_INTEGER")
    cfg.offsetX, cfg.alignment = 0, "other"
    T.equal(Model.validate(cfg).code, "ALIGNMENT_INVALID")
  end)
end
