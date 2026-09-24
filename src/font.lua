local glyphs = {
  ["0"]={"111","101","101","101","111"},
  ["1"]={"010","110","010","010","111"}
}

local M = {}

function M.draw(text, x, y, emit)
  for i = 1, #text do
    local glyph = assert(glyphs[text:sub(i,i)],"unsupported mask-label digit")
    for row, pixels in ipairs(glyph) do
      for column = 1, #pixels do
        if pixels:sub(column,column) == "1" then
          emit(x+(i-1)*4+column-1,y+row-1)
        end
      end
    end
  end
end

return M
