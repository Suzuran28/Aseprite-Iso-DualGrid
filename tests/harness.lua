local M = { passed = 0, failed = 0 }

function M.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    M.passed = M.passed + 1
    print("PASS " .. name)
  else
    M.failed = M.failed + 1
    print("FAIL " .. name .. "\n" .. tostring(err))
  end
end

function M.equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") ..
      ": expected=" .. tostring(expected) ..
      " actual=" .. tostring(actual), 2)
  end
end

function M.truthy(value, message)
  if not value then error(message or "expected truthy value", 2) end
end

function M.match(value, pattern, message)
  if type(value) ~= "string" or not value:match(pattern) then
    error(message or ("value does not match " .. pattern), 2)
  end
end

function M.finish()
  print(string.format("RESULT passed=%d failed=%d", M.passed, M.failed))
  if M.failed > 0 then error("test suite failed") end
end

return M
