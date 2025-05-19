local ffi = require 'ffi'
local cast = ffi.cast
local sizeof = ffi.sizeof
local copy = ffi.copy
local istype = ffi.istype
local ffi_string = ffi.string
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

local i8Ptr = ffi.typeof 'int8_t*'
local i16Ptr = ffi.typeof 'int16_t*'
local i32Ptr = ffi.typeof 'int32_t*'
local i64Ptr = ffi.typeof 'int64_t*'
local u16Ptr = ffi.typeof 'uint16_t*'
local u32Ptr = ffi.typeof 'uint32_t*'
local u64Ptr = ffi.typeof 'uint64_t*'

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
  if val == 0 then
    return 0, 0
  end
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
  local iter = pairs
  if mt then
    if mt.__pairs then
      iter = mt.__pairs
    elseif mt.__ipairs then
      return true, mt.__ipairs
    end
    if mt.__is_array_like ~= nil then
      return mt.__is_array_like, iter
    end
  end
  local i = 0
  for k in iter(val) do
    i = i + 1
    if k ~= i then
      return false, iter
    end
  end
  return true, iter
end

ffi.cdef [[
enum {
  /* Externally visible types. */
  CT_NUM,		/* Integer or floating-point numbers. */
  CT_STRUCT,		/* Struct or union. */
  CT_PTR,		/* Pointer or reference. */
  CT_ARRAY,		/* Array or complex type. */
  CT_MAYCONVERT = CT_ARRAY,
  CT_VOID,		/* Void type. */
  CT_ENUM,		/* Enumeration. */
  CT_HASSIZE = CT_ENUM,  /* Last type where ct->size holds the actual size. */
  CT_FUNC,		/* Function. */
  CT_TYPEDEF,		/* Typedef. */
  CT_ATTRIB,		/* Miscellaneous attributes. */
  /* Internal element types. */
  CT_FIELD,		/* Struct/union field or function parameter. */
  CT_BITFIELD,		/* Struct/union bitfield. */
  CT_CONSTVAL,		/* Constant value. */
  CT_EXTERN,		/* External reference. */
  CT_KW			/* Keyword. */
};
]]

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
--- @param val ffi.cdata*
--- @return boolean
local function is_float(val)
  return istype(F64, val) or istype(F32, val)
end
-- At most we will need 18 bytes for an ext pair
local varintBuffer = ffi.new 'uint8_t[18]'

--- @param val integer number to write
--- @param offset integer
--- @return integer new_offset
--- @return integer lower 5 bits for pair
local function encode_varint(offset, val)
  local num = tonumber(val)
  if num < 28 then
    return offset, val
  elseif num < 0x100 then
    varintBuffer[offset] = val
    return offset + 1, 28
  elseif num < 0x10000 then
    cast(varintBuffer + offset, u16Ptr)[0] = val
    return offset + 2, 29
  elseif num < 0x100000000 then
    cast(varintBuffer + offset, u32Ptr)[0] = val
    return offset + 4, 30
  else
    cast(varintBuffer + offset, u64Ptr)[0] = val
    return offset + 8, 31
  end
end

--- @param val integer number to write
--- @param offset integer
--- @return integer new_offset
--- @return integer lower 5 bits for pair
local function encode_signed_varint(offset, val)
  local num = tonumber(val)
  if num >= -14 and num < 14 then
    -- Small signed numbers use zigzag encoding
    return offset, bxor(lshift(val, 1), arshift(val, 31))
  elseif num >= -0x80 and num < 0x80 then
    cast(i8Ptr, varintBuffer + offset)[0] = val
    return offset + 1, 28
  elseif num >= -0x8000 and num < 0x8000 then
    cast(i16Ptr, varintBuffer + offset)[0] = val
    return offset + 2, 29
  elseif num >= -0x80000000 and num < 0x80000000 then
    cast(i32Ptr, varintBuffer + offset)[0] = val
    return offset + 4, 30
  else
    cast(i64Ptr, varintBuffer + offset)[0] = val
    return offset + 8, 31
  end
end

---@param typ integer
---@param val integer
---@return ffi.cdata* ptr
---@return integer len
local function encode_pair(typ, val)
  local offset, lower = encode_varint(0, val)
  varintBuffer[offset] = bor(lshift(typ, 5), lower)
  return varintBuffer, offset + 1
end

---@param typ integer
---@param val integer
---@return ffi.cdata* ptr
---@return integer len
local function encode_signed_pair(typ, val)
  local offset, lower = encode_signed_varint(0, val)
  varintBuffer[offset] = bor(lshift(typ, 5), lower)
  return varintBuffer, offset + 1
end

local function encode_signed_pair_ext(typ, val1, val2)
  local offset, lower1, lower2
  offset, lower2 = encode_signed_varint(0, val2)
  offset, lower1 = encode_signed_varint(offset, val1)
  varintBuffer[offset] = bor(lshift(typ, 5), lower2)
  varintBuffer[offset + 1] = bor(lshift(EXT, 5), lower1)
  return varintBuffer, offset + 2
end

---@param root_val any
---@param write fun(data:ffi.cdata*|string, len:integer):integer
---@return integer total_bytes_written
local function encode(root_val, write)
  assert(type(write) == 'function', 'write function is required')
  local offset = 0

  local function encode_integer(val)
    offset = write(encode_signed_pair(NUM, val))
  end

  local function encode_float(val)
    local base, power = split_number(val)
    if power >= 0 and power < 10 then
      return encode_integer(val)
    end
    offset = write(encode_signed_pair_ext(NUM, base, power))
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
    local len = #str
    write(str, len)
    offset = write(encode_pair(STR, len))
  end

  ---@param val ffi.cdata*
  local function encode_binary(val)
    local len = assert(sizeof(val))
    write(val, len)
    offset = write(encode_pair(BIN, len))
  end

  local encode_any

  local function encode_list(lst, iter)
    local stack = {}
    local height = 0
    for i, v in iter(lst) do
      height = i
      stack[height] = v
    end
    local start = offset
    for i = height, 1, -1 do
      encode_any(stack[i])
    end
    offset = write(encode_pair(LST, offset - start))
  end

  local function encode_map(map, iter)
    local stack = {}
    local height = 0
    for k, v in iter(map) do
      height = height + 1
      stack[height] = k
      height = height + 1
      stack[height] = v
    end
    local start = offset
    for i = height, 1, -1 do
      encode_any(stack[i])
    end
    offset = write(encode_pair(MAP, offset - start))
  end

  local function encode_table(val)
    local is_array, iter = is_array_like(val)
    if is_array then
      encode_list(val, iter)
    else
      encode_map(val, iter)
    end
  end

  ---@param val any
  function encode_any(val)
    if val == nil then
      offset = write(encode_pair(REF, NULL))
    elseif val == true then
      offset = write(encode_pair(REF, TRUE))
    elseif val == false then
      offset = write(encode_pair(REF, FALSE))
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
          local info = ffi.typeinfo(ffi.typeof(val)).info
          local ct = arshift(info, 28)
          if ct == ffi.C.CT_ARRAY or ct == ffi.C.CT_STRUCT then
            encode_binary(val)
          else
            error('Unsupported ctype: ' .. ct)
          end
        end
      else
        error('Unsupported type: ' .. typ)
      end
    end
  end

  encode_any(root_val)
  return offset
end

local capacity = 1024
local size = 0
local buf = U8Arr(capacity)
local function ensure_capacity(needed)
  if needed <= capacity then
    return
  end
  repeat
    capacity = capacity * 2
  until capacity >= needed
  local new_buf = U8Arr(capacity)
  copy(new_buf, buf, size)
  buf = new_buf
end

---@param data ffi.cdata*|string
---@param len integer
---@return integer total_bytes_written
local function buffered_write(data, len)
  ensure_capacity(size + len)
  copy(buf + size, data, len)
  size = size + len
  return size
end

local function encode_to_string(root_val)
  assert(size == 0, 'encode_to_string is not reentrant')
  local total_bytes_written = encode(root_val, buffered_write)
  size = 0
  return ffi_string(buf, total_bytes_written)
end

return {
  split_number = split_number,
  encode = encode,
  encode_to_string = encode_to_string,
}
