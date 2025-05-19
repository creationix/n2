local N2 = require 'n2'
local dump = require 'dump'

local bit = require 'bit'
local ffi = require 'ffi'
local band = bit.band
local arshift = bit.arshift

local U8Arr = ffi.typeof 'uint8_t[?]'
local U8 = ffi.typeof 'uint8_t'
local U16 = ffi.typeof 'uint16_t'
local U32 = ffi.typeof 'uint32_t'
local U64 = ffi.typeof 'uint64_t'
local I8 = ffi.typeof 'int8_t'
local I16 = ffi.typeof 'int16_t'
local I32 = ffi.typeof 'int32_t'
local I64 = ffi.typeof 'int64_t'
local F32 = ffi.typeof 'float'
local F64 = ffi.typeof 'double'

local u64Box = ffi.new 'uint64_t[1]'
local u32Box = ffi.new 'uint32_t[1]'
local u16Box = ffi.new 'uint16_t[1]'
local u8Box = ffi.new 'uint8_t[1]'
local i64Box = ffi.new 'int64_t[1]'
local i32Box = ffi.new 'int32_t[1]'
local i16Box = ffi.new 'int16_t[1]'
local i8Box = ffi.new 'int8_t[1]'

-- Unit test for split_number
for i = -200, 200 do
  local base, exponent = N2.split_number(0)
  assert(base == 0, base)
  assert(exponent == 0, exponent)
  base, exponent = N2.split_number(math.pow(10, i))
  assert(base == 1)
  assert(i == exponent, i)
  base, exponent = N2.split_number(314 * math.pow(10, i))
  assert(base == 314)
  assert(i == exponent, i)
  base, exponent = N2.split_number(12345678912345 * math.pow(10, i))
  assert(base == 12345678912345)
  assert(i == exponent, i)
end

local oct_lookup = {
  [0x0] = '0000',
  [0x1] = '0001',
  [0x2] = '0010',
  [0x3] = '0011',
  [0x4] = '0100',
  [0x5] = '0101',
  [0x6] = '0110',
  [0x7] = '0111',
  [0x8] = '1000',
  [0x9] = '1001',
  [0xA] = '1010',
  [0xB] = '1011',
  [0xC] = '1100',
  [0xD] = '1101',
  [0xE] = '1110',
  [0xF] = '1111',
}

local hex_lookup = {}
for i = 0, 255 do
  hex_lookup[i] = oct_lookup[arshift(i, 4)] .. oct_lookup[band(i, 0x0f)]
end

local function to_binary(data)
  local bytes = {}
  for i = 1, #data do
    local b = data:byte(i)
    bytes[i] = hex_lookup[b]
  end
  return table.concat(bytes, ' ')
end

local function to_hex(data)
  local bytes = {}
  for i = 1, #data do
    local b = data:byte(i)
    bytes[i] = string.format('%02x', b)
  end
  return string.format('%s', table.concat(bytes, ''))
end

local function test(value, expected)
  print()
  print(dump(value))
  local data = N2.encode(value)
  print(to_binary(data))
  local actual = to_hex(data)
  if actual ~= expected then
    print('Expected: ' .. tostring(expected))
    print('  Actual: ' .. tostring(actual))
    local info = debug.getinfo(2, 'Sl')
    error(string.format('Encoding Mismatch at %s:%s', info.short_src, info.currentline))
  end
end

-- Overrite pairs to have sorted keys
function _G.pairs(tab)
  -- Use the custom __pairs metamethod if it exists
  local mt = getmetatable(tab)
  if mt and mt.__pairs then
    return mt.__pairs(tab)
  end

  local keys = {}
  local size = 0
  for k in next, tab do
    size = size + 1
    keys[size] = k
  end
  table.sort(keys)
  local i = 0
  return function()
    i = i + 1
    local k = keys[i]
    if k then
      return k, tab[k]
    end
  end
end

test(0, '00')
test(-1, '01')
test(1, '02')
test(13, '1a')
test(-14, '1b')
test(14, '0e1c')
test(-15, 'f11c')
test(100, '641c')
test(-100, '9c1c')
test(-127, '811c')
test(127, '7f1c')
test(-128, '801c')
test(128, '80001d')
test(-129, '7fff1d')

test(1e10, '0234')
test(1e20, '14023c')
test(1e30, '1e023c')
test(123.456, '40e201001e25')
test(12345.6789, '15cd5b071e27')
test(math.pi, 'da362497921c00001f39')
test(math.pi * 1e300, 'da362497921c00001f011f3d')
test(math.pi * 1e-300, 'da362497921c0000c7fe1f3d')

test('', '40')
test('Hello World', '48656c6c6f20576f726c64' .. '4b')
test('Hello World' .. string.rep('!', 100), '48656c6c6f20576f726c64' .. string.rep('21', 100) .. '6f5c')

test({ 1, 2, 3 }, '06040283')
test({ name = 'N2', new = true }, 'e16e6577434e32426e616d6544ad')

local bin = U8Arr(8)
bin[0] = 1
bin[1] = 3
bin[2] = 7
bin[3] = 15
bin[4] = 31
bin[5] = 63
bin[6] = 127
bin[7] = 255
test(bin, '0103070f1f3f7fff68')

test(123ULL, '7b1c')
test(123LL, '7b1c')
test(1234LL, 'd2041d')
test(12345LL, '39301d')
test(-12345LL, 'c7cf1d')
test(0x123.456p5, '832a8e2b020000001f2b')
test(0x7fffffffffffffffLL, 'ffffffffffffff7f1f') -- largest `i64` value
test(-0x8000000000000000LL, '00000000000000801f') -- smallest `i64` value
test(U8(200), 'c8001d')
test(I8(-100), '9c1c')
test(U16(60000), '60ea00001e')
test(I16(-30000), 'd08a1d')
test(U32(4000000000), '00286bee000000001f')
test(I32(-2000000000), '006cca881e')
test(U64(0x7fffffffffffffffLL), 'ffffffffffffff7f1f')
test(I64(-0x8000000000000000LL), '00000000000000801f')
test(F32(math.pi), 'ce8d3197921c00001f39')
test(F64(math.pi), 'da362497921c00001f39')
test(F32(1.2), 'a506c4f7e90a00001f39')
test(F64(1.2), '1821')
u8Box[0] = 0xf0
test(u8Box, 'f061')
test(u8Box[0], 'f0001d')
i8Box[0] = -0x0f
test(i8Box, 'f161')
test(i8Box[0], 'f11c')
u16Box[0] = 0xf0f0
test(u16Box, 'f0f062')
test(u16Box[0], 'f0f000001e')
i16Box[0] = -0x0f0f
test(i16Box, 'f1f062')
test(i16Box[0], 'f1f01d')
u32Box[0] = 0xf0f0f0f0
test(u32Box, 'f0f0f0f064')
test(u32Box[0], 'f0f0f0f0000000001f')
i32Box[0] = -0x0f0f0f0f
test(i32Box, 'f1f0f0f064')
test(i32Box[0], 'f1f0f0f01e')
u64Box[0] = 0xf0f0f0f0f0f0f0f0ULL
test(u64Box, 'f0f0f0f0f0f0f0f068')
test(u64Box[0], 'f0f0f0f0f0f0f0f01f')
i64Box[0] = -0x0f0f0f0f0f0f0f0fLL
test(i64Box, 'f1f0f0f0f0f0f0f068')
test(i64Box[0], 'f1f0f0f0f0f0f0f01f')

-- String tests including UTF-8
test('Hello, 世界', '48656c6c6f2c20e4b896e7958c4d')
test('𐐤𐐴𐐻𐑉𐐲𐐾𐐲𐑌', 'f09090a4f09090b4f09090bbf0909189f09090b2f09090bef09090b2f090918c205c')
test('🟥🟧🟨🟩🟦🟪', 'f09f9fa5f09f9fa7f09f9fa8f09f9fa9f09f9fa6f09f9faa58')

test(nil, 'e0')
test(true, 'e1')
test(false, 'e2')

-- Test for empty objects and arrays
test(setmetatable({}, { __is_array_like = false }), 'a0')
test(setmetatable({}, { __is_array_like = true }), '80')
test({}, '80')

-- Test for mixed documents that use all types
test(
  {
    ['string'] = 'Hello, 世界',
    ['number'] = 123.456,
    ['boolean'] = true,
    ['array'] = { 1, 2, 3 },
    ['object'] = { name = 'N2', new = true },
  },
  '48656c6c6f2c20e4b896e7958c4d' -- "Hello, 世界"
    .. '737472696e6746' -- "string"
    .. 'e16e6577434e32426e616d6544ad' -- { new: true, name: "N2" }
    .. '6f626a65637446' -- "object"
    .. '40e201001e25' -- 123.456
    .. '6e756d62657246' -- "number"
    .. 'e1' -- true
    .. '626f6f6c65616e47' -- "boolean"
    .. '06040283' -- [ 1, 2, 3 ]
    .. '617272617945' -- "array"
    .. '4abc' -- MAP(0x4a)
)

test({ { { {} } } }, '80818283')

-- Test for custom iterators
local function five_squares()
  local i = 0
  return function()
    i = i + 1
    if i < 5 then
      return i, i * i
    end
  end
end

-- [ 1, 4, 9, 16]
test(setmetatable({}, { __pairs = five_squares }), '101c12080285')
test(setmetatable({}, { __ipairs = five_squares }), '101c12080285')
-- { 1: 1, 2: 4, 3: 9, 4: 16 }
test(setmetatable({}, { __pairs = five_squares, __is_array_like = false }), '101c08120608040202a9')

test({ ['true'] = true }, 'e17472756544a6')

test({
  ['Content-Type'] = 'application/json',
  ['Content-Length'] = 123,
}, '6170706c69636174696f6e2f6a736f6e50436f6e74656e742d547970654c7b1c436f6e74656e742d4c656e6774684e2fbc')
