local ffi = require 'ffi'
local istype = ffi.istype
local bit = require 'bit'
local bor = bit.bor
local lshift = bit.lshift
local arshift = bit.arshift
local bxor = bit.bxor

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
local i64Box = ffi.new 'int64_t[1]'
local i32Box = ffi.new 'int32_t[1]'
local i16Box = ffi.new 'int16_t[1]'
local i8Box = ffi.new 'int8_t[1]'

-- Major Types
local NUM = 0 -- (val)
local EXT = 1 -- (data)
local STR = 2 -- (length)
local BIN = 3 -- (length)
local LST = 4 -- (length)
local MAP = 5 -- (length)
local PTR = 6 -- (offset)
local REF = 7 -- (index)
-- Built-in Refs
local NULL = 0
local TRUE = 1
local FALSE = 2

-- Given a double value, split it into a base and power of 10.
-- For example, 1234.5678 would be split into 12345678 and -4.
local function split_number(val)
  if val == 0 then return 0, 0 end
  local str = tostring(val)
  -- Check if the number is in scientific notation
  if str:find 'e' then
    -- Split the string into base and exponent
    local base, exponent = str:match '(-?[%d%.]+)e([+-]?%d+)'
    exponent = tonumber(exponent)
    -- Check for decimal in base
    local decimal_pos = base:find('.', 1, true)
    if decimal_pos then
      -- Remove the decimal point
      base = base:gsub('%.', '')
      -- Count the number of digits after the decimal point
      local decimal_count = #base - (decimal_pos - 1)
      -- Adjust the exponent accordingly
      exponent = exponent - decimal_count
    end
    return tonumber(base), exponent
  end
  local decimal_pos = str:find '%.'
  if decimal_pos then
    -- Remove the decimal point
    local base = str:gsub('%.', '')
    -- Adjust the exponent accordingly
    return tonumber(base), decimal_pos - #str
  end
  -- Count trailing zeroes
  local zeroes_pos = str:find '0+$'
  if zeroes_pos then
    local base = str:sub(1, zeroes_pos - 1)
    local exponent = #str - zeroes_pos + 1
    return tonumber(base), exponent
  end
  return val, 0
end

---@param val table
local function is_array_like(val)
  local mt = getmetatable(val)
  if mt then
    if mt.__is_array_like ~= nil then
      return mt.__is_array_like
    elseif mt.__ipairs then
      return true
    elseif mt.__pairs then
      return false
    end
  end
  local i = 0
  for k in pairs(val) do
    i = i + 1
    if k ~= i then return false end
  end
  return true
end

--- Detect if a cdata is an integer
---@param val ffi.cdata*
---@return boolean
local function is_integer(val)
  return istype(I64, val)
    or istype(I32, val)
    or istype(I16, val)
    or istype(I8, val)
    or istype(U64, val)
    or istype(U32, val)
    or istype(U16, val)
    or istype(U8, val)
end

--- Detect if a cdata is a float
---@param val ffi.cdata*
---@return boolean
local function is_float(val)
  return istype(F32, val) or istype(F64, val)
end

local capacity = 1024
local buf = U8Arr(capacity)

---@param root_val any
---@return string
local function encode(root_val)
  local size = 0

  local function ensure_capacity(needed)
    if needed <= capacity then return end
    repeat
      capacity = capacity * 2
    until capacity >= needed
    local new_buf = U8Arr(capacity)
    ffi.copy(new_buf, buf, size)
    buf = new_buf
  end

  ---@param str integer
  local function write_string(str)
    local len = #str
    ensure_capacity(size + len)
    ffi.copy(buf + size, str, len)
    size = size + len
  end

  ---@param byte integer
  local function write_byte(byte)
    ensure_capacity(size + 1)
    buf[size] = byte
    size = size + 1
  end

  ---@param data ffi.cdata*
  ---@param len integer
  local function write_binary(data, len)
    ensure_capacity(size + len)
    ffi.copy(buf + size, data, len)
    size = size + len
  end

  --- @param val integer number to write
  --- @return integer lower 5 bits for pair
  local function write_varint(val)
    if val < 28 then
      return val
    elseif val < 0x100 then
      write_byte(val)
      return 28
    elseif val < 0x10000 then
      u16Box[0] = val
      write_binary(u16Box, 2)
      return 29
    elseif val < 0x100000000 then
      u32Box[0] = val
      write_binary(u32Box, 4)
      return 30
    else
      u64Box[0] = val
      write_binary(u64Box, 8)
      return 31
    end
  end

  --- @param val integer number to write
  --- @return integer lower 5 bits for pair
  local function write_signed_varint(val)
    local num = tonumber(val)
    if num >= -14 and val < 14 then
      -- Small signed numbers use zigzag encoding
      return bxor(lshift(val, 1), arshift(val, 31))
    elseif num >= -0x80 and num < 0x80 then
      i8Box[0] = val
      write_binary(i8Box, 1)
      return 28
    elseif num >= -0x8000 and num < 0x8000 then
      i16Box[0] = val
      write_binary(i16Box, 2)
      return 29
    elseif num >= -0x80000000 and num < 0x80000000 then
      i32Box[0] = val
      write_binary(i32Box, 4)
      return 30
    else
      i64Box[0] = val
      write_binary(i64Box, 8)
      return 31
    end
  end

  ---@param typ integer
  ---@param val integer
  local function write_pair(typ, val)
    local lower = write_varint(val)
    write_byte(bor(lshift(typ, 5), lower))
  end

  ---@param typ integer
  ---@param val integer
  local function write_signed_pair(typ, val)
    local lower = write_signed_varint(val)
    write_byte(bor(lshift(typ, 5), lower))
  end

  local function write_signed_pair_ext(ext, typ, val1, val2)
    local lower2 = write_signed_varint(val1)
    local lower1 = write_signed_varint(val2)
    write_byte(bor(lshift(typ, 5), lower2))
    write_byte(bor(lshift(ext, 5), lower1))
  end

  local function encode_integer(val)
    write_signed_pair(NUM, val)
  end

  local function encode_float(val)
    local base, power = split_number(val)
    if power >= 0 and power < 10 then return encode_integer(val) end
    write_signed_pair_ext(EXT, NUM, base, power)
  end

  local function encode_number(val)
    if val == math.floor(val) and val >= -0x8000 and val < 0x8000 then
      -- Fast path for small integers that are always better as non-extended
      encode_integer(val)
    else
      -- Use extended encoding for all other numbers
      encode_float(val)
    end
  end

  ---@param str string
  local function encode_string(str)
    write_string(str)
    write_pair(STR, #str)
  end

  ---@param val ffi.cdata*
  local function encode_binary(val)
    local len = assert(ffi.sizeof(val))
    write_binary(val, len)
    write_pair(BIN, len)
  end

  local encode_any

  local function encode_list(lst)
    local stack = {}
    local height = 0
    local mt = getmetatable(lst)
    local iter = mt and mt.__ipairs or mt.__pairs or ipairs
    for i, v in iter(lst) do
      height = i
      stack[height] = v
    end
    local start = size
    for i = height, 1, -1 do
      encode_any(stack[i])
    end
    write_pair(LST, size - start)
  end

  local function encode_map(map)
    local stack = {}
    local height = 0
    local mt = getmetatable(map)
    local iter = mt and mt.__pairs or pairs
    for k, v in iter(map) do
      height = height + 1
      stack[height] = k
      height = height + 1
      stack[height] = v
    end
    local start = size
    for i = height, 1, -1 do
      encode_any(stack[i])
    end
    write_pair(MAP, size - start)
  end

  local function encode_table(val)
    if is_array_like(val) then
      encode_list(val)
    else
      encode_map(val)
    end
  end

  ---@param val any
  function encode_any(val)
    if val == nil then
      write_pair(REF, NULL)
    elseif val == true then
      write_pair(REF, TRUE)
    elseif val == false then
      write_pair(REF, FALSE)
    else
      local typ = type(val)
      if typ == 'string' then
        encode_string(val)
      elseif typ == 'number' then
        encode_number(val)
      elseif typ == 'table' then
        encode_table(val)
      elseif typ == 'cdata' then
        if is_integer(val) then
          encode_integer(val)
        elseif is_float(val) then
          encode_float(tonumber(val))
        else
          encode_binary(val)
        end
      else
        error('Unsupported type: ' .. typ)
      end
    end
  end

  encode_any(root_val)
  return ffi.string(buf, size)
end

return {
  split_number = split_number,
  encode = encode,
}
