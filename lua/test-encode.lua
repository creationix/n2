local N2 = require 'n2'
local Tibs = require 'tibs'
local dump = require 'dump'

-- ANSI color codes
local BLACK = '\27[90m'
local RED = '\27[91m'
local GREEN = '\27[92m'
local YELLOW = '\27[93m'
local BLUE = '\27[94m'
local MAGENTA = '\27[95m'
local CYAN = '\27[96m'
local WHITE = '\27[97m'
local BOLD = '\27[1m'
local DIM = '\27[2m'
local ITALIC = '\27[3m'
local UNDERLINE = '\27[4m'
local BLINK = '\27[5m'
local INVERSE = '\27[6m'
local REVERSE = '\27[7m'
local RESET = '\27[0m'

-- Some better colors using 256 ANSI codes
local ORANGE = '\27[38;5;208m'
local PINK = '\27[38;5;205m'
local PURPLE = '\27[38;5;93m'
local CORAL = '\27[38;5;203m'
local COBALT = '\27[38;5;33m'
local SKY = '\27[38;5;39m'
local AQUA = '\27[38;5;51m'
local STRAWBERRY = '\27[38;5;203m'
local LIME = '\27[38;5;118m'
local MINT = '\27[38;5;121m'
local EMERALD = '\27[38;5;34m'
local MUSTARD = '\27[38;5;136m'
local GOLD = '\27[38;5;220m'
local YELLOW_ORANGE = '\27[38;5;214m'

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
local errors = 0
for section, tests in pairs(fixtures) do
  print('\n' .. YELLOW .. BOLD .. REVERSE .. ' section: ' .. section .. ' ' .. RESET)
  for i = 1, #tests, 2 do
    local input = tests[i]
    local expected = tests[i + 1]
    print()
    print(YELLOW_ORANGE .. 'input:    ' .. RESET .. dump(input))
    print(COBALT .. 'expected: ' .. RESET .. dump(expected))
    local expectedDump = dump(expected)
    local actual = N2.encode_to_bytes(input)
    local actualDump = dump(actual)
    local actualColor = (actualDump == expectedDump) and GREEN or RED
    print(actualColor .. 'actual:   ' .. RESET .. actualDump)
    if actualDump ~= expectedDump then
      errors = errors + 1
    end
  end
end
print()
if errors > 0 then
  print(RED .. BOLD .. errors .. ' test(s) failed!' .. RESET)
  os.exit(1)
end

print(GREEN .. BOLD .. 'All tests passed!' .. RESET)
