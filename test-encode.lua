local N2 = require 'n2'
local Tibs = require 'tibs'
local dump = require 'dump'

local function readfile(path)
  local f = assert(io.open(path, 'r'))
  local data = assert(f:read '*a')
  f:close()
  return Tibs.decode(data, path)
end

local function to_hex(data)
  local bytes = {}
  for i = 1, #data do
    local b = data:byte(i)
    bytes[i] = string.format('%02x', b)
  end
  return string.format('%s', table.concat(bytes, ''))
end

local fixtures = readfile 'fixtures/encode.tibs'

for section, tests in pairs(fixtures) do
  print("Section", section)
  for i = 1, #tests, 2 do
    local input = tests[i]
    local expected_raw = tests[i+1]
    print(dump(input))
    local expected = to_hex(expected_raw)
    print(expected)
    local actual_raw = N2.encode_to_string(input)
    local actual = to_hex(actual_raw)
    if actual ~= expected then
      print('Expected: ' .. tostring(expected))
      print('  Actual: ' .. tostring(actual))
      error(string.format('Encoding Mismatch in %s', section))
    end
  end
end
