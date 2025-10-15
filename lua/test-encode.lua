local N2 = require 'n2'
local Tibs = require 'tibs'
local dump = require 'dump'

-- Polyfill for Lua 5.1
function _G.pairs(self)
  local mt = getmetatable(self)
  if mt and mt.__pairs then
    return mt.__pairs(self)
  end
  return next, self
end

local function readfile(path)
  local f = assert(io.open(path, 'r'))
  local data = assert(f:read '*a')
  f:close()
  -- Strip comments since Tibs doesn't support them
  data = data:gsub('//[^\n]*\n', '\n')
  return Tibs.decode(data, path)
end

local fixtures = readfile '../fixtures/encode.tibs'

-- print(dump(fixtures))
for section, tests in pairs(fixtures) do
  print('section: ' .. dump(section))
  for i = 1, #tests, 2 do
    local input = tests[i]
    local expected = tests[i + 1]
    print('input:    ' .. dump(input))
    print('expected: ' .. dump(expected))
    local actual = N2.encode_to_bytes(input)
    print('actual:   ' .. dump(actual))
    if dump(actual) ~= dump(expected) then
      error(string.format('Encoding Mismatch in %s', section))
    end
  end
end
