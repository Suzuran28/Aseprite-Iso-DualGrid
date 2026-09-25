-- Exact 64px, center-aligned SliceBorder and SliceHeightHint pixels from
-- the replacement 4x4 atlases in assets/. Other sizes scale these samples.
local source = debug.getinfo(1,"S").source
local file = source:sub(1,1) == "@" and source:sub(2) or source
local ROOT = app.fs.filePath(app.fs.filePath(file))
local border = assert(Image{fromFile=app.fs.joinPath(ROOT,"assets","border.png")},
  "replacement border atlas is missing")
local hint = assert(Image{fromFile=app.fs.joinPath(ROOT,"assets","heighthint.png")},
  "replacement HeightHint atlas is missing")
assert(border.width == 256 and border.height == 256,
  "replacement border atlas must be 256x256")
assert(hint.width == 256 and hint.height == 256,
  "replacement HeightHint atlas must be 256x256")

local M = {border={},hintColumns={}}

local function opaque(image,x,y)
  return app.pixelColor.rgbaA(image:getPixel(x,y)) > 0
end

for slot=0,15 do
  local originX,originY = (slot % 4)*64,math.floor(slot/4)*64
  local top,columns = {},{}
  for y=0,63 do
    for x=0,63 do
      if opaque(border,originX+x,originY+y) then
        top[#top+1] = {x,y}
      end
    end
  end
  for x=0,63 do
    local runStart
    for y=0,64 do
      local painted = y < 64 and opaque(hint,originX+x,originY+y)
      if painted and not runStart then runStart=y end
      if not painted and runStart then
        columns[#columns+1] = {x,runStart,y-1}
        runStart=nil
      end
    end
  end
  M.border[slot]=top
  M.hintColumns[slot]=columns
end

return M
