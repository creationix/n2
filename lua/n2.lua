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

local bit = require 'bit'
local dump = require 'dump'
local ffi = require 'ffi'

local bor = bit.bor
local lshift = bit.lshift
local arshift = bit.arshift
local bxor = bit.bxor
local cast = ffi.cast
local sizeof = ffi.sizeof
local copy = ffi.copy
local istype = ffi.istype
local ffi_string = ffi.string

ffi.cdef [[
  #pragma packed
  struct n2_5 {
    uint8_t u5:5;
    uint8_t type:3;
  };
  #pragma packed
  struct n2_8 {
    union {
      uint8_t u8;
      int8_t i8;
    };
    uint8_t tag:5;
    uint8_t type:3;
  };
  #pragma packed
  struct n2_16 {
    union {
      uint16_t u16;
      int16_t i16;
    };
    uint8_t tag:5;
    uint8_t type:3;
  };
    #pragma packed
  struct n2_32 {
    union {
      uint32_t u32;
      int32_t i32;
    };
    uint8_t tag:5;
    uint8_t type:3;
  };
  #pragma packed
  struct n2_64 {
    union {
      uint64_t u64;
      int64_t i64;
    };
    uint8_t tag:5;
    uint8_t type:3;
  };
]]

---@class N2_5:ffi.cdata*
local n2_5 = ffi.new 'struct n2_5'
---@class N2_8:ffi.cdata*
local n2_8 = ffi.new 'struct n2_8'
n2_8.tag = 28
---@class N2_16:ffi.cdata*
local n2_16 = ffi.new 'struct n2_16'
n2_16.tag = 29
---@class N2_32:ffi.cdata*
local n2_32 = ffi.new 'struct n2_32'
n2_32.tag = 30
---@class N2_64:ffi.cdata*
local n2_64 = ffi.new 'struct n2_64'
n2_64.tag = 31

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

-- Reverse an iterator
---@generic O,T : fun():(any,any)
---@param iter fun(O):T
---@return T
local function reverse(iter, obj)
  ---@type any[]
  local stack = {}
  local height = 0
  for k, v in iter(obj) do
    height = height + 1
    stack[height] = v
    height = height + 1
    stack[height] = k
  end
  return function()
    local k = stack[height]
    if not k then
      return
    end
    stack[height] = nil
    height = height - 1
    local v = stack[height]
    stack[height] = nil
    height = height - 1
    return k, v
  end
end

-- Given a double value, split it into a base and power of 10.
-- For example, 1234.5678 would be split into 12345678 and -4.
local function split_number(val)
  if val == 0 then
    return 0, 0
  end
  if type(val) ~= 'number' then
    error('Expected a number, got ' .. type(val))
  end
  local str = tostring(val)
  -- Check if the number is in scientific notation
  if str:find 'e' then
    -- Split the string into base and exponent
    local base, exponent = str:match '(-?[%d%.]+)e([+-]?%d+)'
    if not base or not exponent then
      error('Invalid number format: ' .. str)
    end
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
  local zeroes_pos, _, zeroes = str:find '(0+)U?L?L?$'
  if zeroes_pos then
    local base = str:sub(1, zeroes_pos - 1)
    local exponent = #zeroes
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

local function same_shape(a, b)
  if a == b then
    return true
  end
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return false
  end
  local a_arr = is_array_like(a)
  local b_arr = is_array_like(b)
  if a_arr ~= b_arr then
    return false
  end
  if a_arr then
    local a_len = #a
    local b_len = #b
    if a_len ~= b_len then
      return false
    end
    for i = 1, a_len do
      if not same_shape(a[i], b[i]) then
        return false
      end
    end
  else
    for k, v in pairs(a) do
      if not same_shape(v, b[k]) then
        return false
      end
    end
    for k, v in pairs(b) do
      if not same_shape(v, a[k]) then
        return false
      end
    end
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
--- @param val ffi.cdata*
--- @return boolean
local function is_float(val)
  return istype(F64, val) or istype(F32, val)
end
-- At most we will need 18 bytes for an ext pair
local varintBuffer = ffi.new 'uint8_t[18]'

---@param num integer
---@return integer
local function varint_size(num)
  if num < 28 then
    return 1
  elseif num < 0x100 then
    return 2
  elseif num < 0x10000 then
    return 3
  elseif num < 0x100000000 then
    return 5
  else
    return 9
  end
end

---@param num integer
---@return integer
local function signed_varint_size(num)
  if num >= -14 and num < 14 then
    return 1
  elseif num >= -0x80 and num < 0x80 then
    return 2
  elseif num >= -0x8000 and num < 0x8000 then
    return 3
  elseif num >= -0x80000000 and num < 0x80000000 then
    return 5
  else
    return 9
  end
end

---@param typ integer
---@param val integer
---@return N2_5|N2_8|N2_16|N2_32|N2_64 ptr
---@return integer len
local function encode_pair(typ, val)
  local num = tonumber(val)
  if num < 28 then
    n2_5.type = typ
    n2_5.u5 = val
    return n2_5, 1
  elseif num < 0x100 then
    n2_8.type = typ
    n2_8.u8 = val
    return n2_8, 2
  elseif num < 0x10000 then
    n2_16.type = typ
    n2_16.u16 = val
    return n2_16, 3
  elseif num < 0x100000000 then
    n2_32.type = typ
    n2_32.u32 = val
    return n2_32, 5
  else
    n2_64.type = typ
    n2_64.u64 = val
    return n2_64, 9
  end
end

---@param typ integer
---@param val integer
---@return N2_5|N2_8|N2_16|N2_32|N2_64 ptr
---@return integer len
local function encode_signed_pair(typ, val)
  local num = tonumber(val)
  if num >= -14 and num < 14 then
    n2_5.type = typ
    -- Small signed numbers use zigzag encoding
    n2_5.u5 = bxor(lshift(val, 1), arshift(val, 31))
    return n2_5, 1
  elseif num >= -0x80 and num < 0x80 then
    n2_8.type = typ
    n2_8.i8 = val
    return n2_8, 2
  elseif num >= -0x8000 and num < 0x8000 then
    n2_16.type = typ
    n2_16.i16 = val
    return n2_16, 3
  elseif num >= -0x80000000 and num < 0x80000000 then
    n2_32.type = typ
    n2_32.i32 = val
    return n2_32, 5
  else
    n2_64.type = typ
    n2_64.i64 = val
    return n2_64, 9
  end
end

local key_cache = setmetatable({}, { __mode = 'k' })
-- Create a unique key for a value
-- Used for detecting previously seen values
---@param val any
---@param depth? integer
---@return string
local function makeKey(val, depth)
  depth = depth or 2
  if depth <= 0 or type(val) ~= 'table' then
    return type(val) == 'string' and string.format('%q', val) or tostring(val)
  end
  local key
  local cached = key_cache[val]
  if cached then
    return cached
  end
  local is_array, iter = is_array_like(val)
  local parts = {}
  local length = 0
  for k, v in iter(val) do
    length = length + 1
    if is_array then
      parts[length] = makeKey(v, depth - 1)
    else
      parts[length] = makeKey(k, depth - 1) .. ':' .. makeKey(v, depth - 1)
    end
  end
  if is_array then
    key = '[' .. table.concat(parts, ',') .. ']'
  else
    key = '{' .. table.concat(parts, ',') .. '}'
  end
  key_cache[val] = key
  return key
end

---@param root_val any
---@param write fun(data:ffi.cdata*|string, len:integer):integer
---@return integer total_bytes_written
local function encode(root_val, write)
  assert(type(write) == 'function', 'write function is required')
  local offset = 0
  ---@type table<string,integer>
  local seen_offsets = {}
  ---@type table<string,integer>
  local seen_costs = {}
  ---@type table<string,integer>
  local schema_counts = {}
  ---@type table<table,string>
  local schema_keys = setmetatable({}, { __mode = 'k' })

  ---@param value unknown
  local function count_schemas(value)
    if type(value) ~= 'table' then
      return
    end
    local is_array, iter = is_array_like(value)
    local keys = is_array and nil or {}
    local count = 0
    for k, v in iter(value) do
      count_schemas(k)
      count_schemas(v)
      if not is_array then
        count = count + 1
        keys[count] = tostring(k)
      end
    end
    if count > 1 then
      local key = makeKey(keys)
      schema_keys[value] = key
      schema_counts[key] = (schema_counts[key] or 0) + 1
    end
  end

  count_schemas(root_val)

  local function encode_integer(val)
    offset = write(encode_signed_pair(NUM, val))
  end

  local function encode_float(val, base, power)
    if not base or not power then
      base, power = split_number(val)
    end
    write(encode_signed_pair(NUM, base))
    offset = write(encode_signed_pair(EXT, power))
  end

  -- Encode a number as either an integer or a float
  -- Use whichever representation is more compact
  ---@param val number
  local function encode_number(val)
    local base, power = split_number(val)
    if power < 0 or val > 0x7FFFFFFFFFFFFFFF or val < -0x8000000000000000 then
      -- If the number has a decimal component or is too big, we have to encode it as a float
      encode_float(val, base, power)
      return
    end
    local float_cost = signed_varint_size(base) + signed_varint_size(power)
    local int_cost = signed_varint_size(val)
    if float_cost < int_cost then
      encode_float(val, base, power)
    else
      encode_integer(val)
    end
  end

  ---@param str string
  local function encode_string(str)
    local len = #str
    if len > 0 then
      write(str, len)
    end
    offset = write(encode_pair(STR, len))
  end

  local encode_any

  local function encode_list(lst, iter)
    local start = offset
    for _, v in reverse(iter, lst) do
      encode_any(v)
    end
    offset = write(encode_pair(LST, offset - start))
  end

  local function encode_schema_map(map, iter)
    local start = offset
    local keys = {}
    local count = 0
    for k in iter(map) do
      count = count + 1
      keys[count] = k
    end
    for i = count, 1, -1 do
      local k = keys[i]
      local v = map[k]
      encode_any(v)
    end
    local target = encode_any(keys, true)
    target = target or offset
    offset = write(encode_pair(MAP, offset - start))
    offset = write(encode_pair(EXT, offset - target))
  end

  local function encode_map(map, iter)
    local schema_key = schema_keys[map]
    if schema_key and schema_counts[schema_key] > 1 then
      return encode_schema_map(map, iter)
    end
    local start = offset
    for k, v in reverse(iter, map) do
      encode_any(v)
      encode_any(k)
    end
    offset = write(encode_pair(MAP, offset - start))
  end

  ---@param val any
  ---@param skipPointer? boolean
  ---@return integer|nil seen_offset
  function encode_any(val, skipPointer)
    local key = makeKey(val)
    local seen_offset = seen_offsets[key]
    if seen_offset then
      local delta = offset - seen_offset
      if seen_costs[key] > varint_size(delta) + 1 then
        if not skipPointer then
          offset = write(encode_pair(PTR, delta))
        end
        return seen_offset
      end
    end
    local before = offset
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
        local is_array, iter = is_array_like(val)
        if is_array then
          encode_list(val, iter)
        else
          encode_map(val, iter)
        end
      elseif typ == 'cdata' then
        if is_integer(val) then
          -- If the integer fits in a Lua number, encode it as such
          local num = tonumber(val)
          if I64(num) == val then
            encode_number(num)
          else
            encode_integer(val)
          end
        elseif is_float(val) then
          encode_number(tonumber(val))
        else
          local info = ffi.typeinfo(ffi.typeof(val)).info
          local ct = arshift(info, 28)
          if ct == ffi.C.CT_ARRAY or ct == ffi.C.CT_STRUCT then
            local len = assert(sizeof(val))
            if len > 0 then
              write(val, len)
            end
            offset = write(encode_pair(BIN, len))
          else
            error('Unsupported ctype: ' .. ct)
          end
        end
      else
        error('Unsupported type: ' .. typ)
      end
    end
    local cost = offset - before
    if cost > 1 then
      seen_offsets[key] = offset
      seen_costs[key] = cost
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

---@param root_val any
local function encode_to_string(root_val)
  assert(size == 0)
  local total_bytes_written = encode(root_val, buffered_write)
  size = 0
  return ffi_string(buf, total_bytes_written)
end

---@param root_val any
local function encode_to_bytes(root_val)
  assert(size == 0)
  local total_bytes_written = encode(root_val, buffered_write)
  size = 0
  local new_buf = U8Arr(total_bytes_written)
  ffi.copy(new_buf, buf, total_bytes_written)
  return new_buf
end

return {
  split_number = split_number,
  encode = encode,
  encode_to_string = encode_to_string,
  encode_to_bytes = encode_to_bytes,
  is_float = is_float,
  is_integer = is_integer,
}
