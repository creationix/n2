local ffi = require 'ffi'
local sizeof = ffi.sizeof
local copy = ffi.copy
local cast = ffi.cast
local ffi_string = ffi.string
local typeof = ffi.typeof
local istype = ffi.istype

local bit = require 'bit'
local lshift = bit.lshift
local rshift = bit.rshift
local bor = bit.bor
local band = bit.band

local char = string.char
local byte = string.byte

local U8Ptr = typeof 'uint8_t*'
local U8Arr = typeof 'uint8_t[?]'
local I8 = typeof 'int8_t'
local I16 = typeof 'int16_t'
local I32 = typeof 'int32_t'
local I64 = typeof 'int64_t'
local U8 = typeof 'uint8_t'
local U16 = typeof 'uint16_t'
local U32 = typeof 'uint32_t'
local U64 = typeof 'uint64_t'

---@class Tibs
---@field deref boolean set to true to deref scope/ref on decode
local Tibs = {}

---@class ByteWriter
---@field capacity integer
---@field size integer
---@field data integer[]
local ByteWriter = { __name = 'ByteWriter' }
ByteWriter.__index = ByteWriter
Tibs.ByteWriter = ByteWriter

---@param initial_capacity? integer
---@return ByteWriter
function ByteWriter.new(initial_capacity)
  initial_capacity = initial_capacity or 128
  return setmetatable({
    capacity = initial_capacity,
    size = 0,
    data = U8Arr(initial_capacity),
  }, ByteWriter)
end

---@param needed integer
function ByteWriter:ensure(needed)
  if needed <= self.capacity then
    return
  end
  repeat
    self.capacity = lshift(self.capacity, 1)
  until needed <= self.capacity
  local new_data = U8Arr(self.capacity)
  copy(new_data, self.data, self.size)
  self.data = new_data
end

---@param str string
function ByteWriter:write_string(str)
  local len = #str
  self:ensure(self.size + len)
  copy(self.data + self.size, str, len)
  self.size = self.size + len
end

---@param bytes integer[]|ffi.cdata*
---@param len? integer
function ByteWriter:write_bytes(bytes, len)
  len = len or assert(sizeof(bytes))
  self:ensure(self.size + len)
  copy(self.data + self.size, cast(U8Ptr, bytes), len)
  self.size = self.size + len
end

function ByteWriter:to_string()
  return ffi_string(self.data, self.size)
end

function ByteWriter:to_bytes()
  local buf = U8Arr(self.size)
  copy(buf, self.data, self.size)
  return buf
end

---@class List
local List = {
  __name = 'List',
  __is_array_like = true,
}
Tibs.List = List

local LEN = {}

function List:__newindex(i, value)
  local len = math.max(rawget(self, LEN) or 0, i)
  rawset(self, LEN, len)
  rawset(self, i, value)
end

function List:__len()
  return rawget(self, LEN) or 0
end

function List:__ipairs()
  local i = 0
  local len = #self
  return function()
    if i < len then
      i = i + 1
      return i, self[i]
    end
  end
end

List.__pairs = List.__ipairs

function List:__slice(i, j)
  if i < 1 or j > #self then
    error('out of bounds', 2)
  end
  local size = 0
  local new_list = setmetatable({}, List)
  for idx = i, j do
    size = size + 1
    new_list[size] = self[idx]
  end
  return new_list
end

---@class Map
local Map = {
  __name = 'Map',
  __is_array_like = false,
}
Tibs.Map = Map

local KEYS = setmetatable({}, { __name = 'KEYS' })
local VALUES = setmetatable({}, { __name = 'VALUES' })
local NIL = setmetatable({}, { __name = 'NIL' })

function Map.new(...)
  local self = setmetatable({}, Map)
  local keys = {}
  local values = {}
  for i = 1, select('#', ...), 2 do
    local key = select(i, ...)
    local value = select(i + 1, ...)
    if value == nil then
      value = NIL
    end
    rawset(keys, i, key)
    rawset(values, key, value)
  end
  rawset(self, KEYS, keys)
  rawset(self, VALUES, values)
  return self
end

function Map:__newindex(key, value)
  local values = rawget(self, VALUES)
  if not values then
    values = {}
    rawset(self, VALUES, values)
  end
  local old_value = rawget(values, key)
  if old_value == nil then
    local keys = rawget(self, KEYS)
    if not keys then
      keys = {}
      rawset(self, KEYS, keys)
    end
    rawset(keys, #keys + 1, key)
  end
  if value == nil then
    value = NIL
  end
  rawset(values, key, value)
end

function Map:__index(key)
  local values = rawget(self, VALUES)
  if not values then
    return nil
  end
  local value = rawget(values, key)
  if value == NIL then
    value = nil
  end
  return value
end

function Map:__pairs()
  local keys = rawget(self, KEYS)
  if not keys then
    return function() end
  end
  local values = rawget(self, VALUES)

  local i = 0
  local len = #keys
  return function()
    if i < len then
      i = i + 1
      local key = keys[i]
      local value = rawget(values, key)
      if value == NIL then
        value = nil
      end
      return key, value
    end
  end
end

local function mixin(a, b)
  for k, v in next, b do
    if rawget(a, k) == nil then
      rawset(a, k, v)
    end
  end
end

---@class Array : List
local Array = {
  __name = 'Array',
  __is_indexed = true,
}
mixin(Array, List)
Tibs.Array = Array

---@class Trie : Map
local Trie = setmetatable({
  __name = 'Trie',
  __is_indexed = true,
}, { __index = Map })
mixin(Trie, Map)
Tibs.Trie = Trie

---@class Ref
local Ref = {
  __name = 'Ref',
  __is_ref = true,
}
Tibs.Ref = Ref

---@class Scope
local Scope = {
  __name = 'Scope',
  __is_scope = true,
  __is_array_like = true,
}
Tibs.Scope = Scope

---@alias LexerSymbols "{"|"}"|"["|"]"|":"|","|"("|")
---@alias LexerToken "string"|"number"|"bytes"|"true"|"false"|"null"|"nan"|"inf"|"-inf"|"ref"|"error"|"eos"|LexerSymbols

-- Consume a sequence of zero or more digits [0-9]
---@param data integer[]
---@param offset integer
---@param len integer
---@return integer new_offset
local function consume_digits(data, offset, len)
  while offset < len do
    local c = data[offset]
    if c < 0x30 or c > 0x39 then
      break
    end -- outside "0-9"
    offset = offset + 1
  end
  return offset
end

-- Consume a single optional character
---@param data integer[]
---@param offset integer
---@param len integer
---@param c1 integer
---@param c2? integer
---@return integer new_offset
---@return boolean did_match
local function consume_optional(data, offset, len, c1, c2)
  if offset < len then
    local c = data[offset]
    if c == c1 or c == c2 then
      offset = offset + 1
      return offset, true
    end
  end
  return offset, false
end

---@param data integer[]
---@param offset integer
---@param len integer
---@return integer offset
---@return LexerToken token
---@return integer token_start
local function next_token(data, offset, len)
  while offset < len do
    local c = data[offset]
    if c == 0x0d or c == 0x0a or c == 0x09 or c == 0x20 then
      -- "\r" | "\n" | "\t" | " "
      -- Skip whitespace
      offset = offset + 1
    elseif c == 0x2f and offset < len and data[offset] == 0x2f then
      -- '//'
      -- Skip comments
      offset = offset + 2
      while offset < len do
        c = data[offset]
        offset = offset + 1
        if c == 0x0d or c == 0x0a then -- "\r" | "\n"
          break
        end
      end
    elseif c == 0x5b or c == 0x5d or c == 0x7b or c == 0x7d or c == 0x3a or c == 0x2c or c == 0x28 or c == 0x29 then
      -- "[" | "]" "{" | "}" | ":" | "," | "(" | ")"
      -- Pass punctuation through as-is
      local start = offset
      offset = offset + 1
      if (c == 0x5b or c == 0x7b) and offset < len and data[offset] == 0x23 then -- "[#"|"{#"
        offset = offset + 1
      end
      return offset, char(c), start
    elseif
      c == 0x74
      and offset + 3 < len -- "t"
      and data[offset + 1] == 0x72 -- "r"
      and data[offset + 2] == 0x75 -- "u"
      and data[offset + 3] == 0x65
    then -- "e"
      offset = offset + 4
      return offset, 'true', offset - 4
    elseif
      c == 0x66
      and offset + 4 < len -- "f"
      and data[offset + 1] == 0x61 -- "a"
      and data[offset + 2] == 0x6c -- "l"
      and data[offset + 3] == 0x73 -- "s"
      and data[offset + 4] == 0x65
    then -- "e"
      offset = offset + 5
      return offset, 'false', offset - 5
    elseif
      c == 0x6e
      and offset + 3 < len -- "n"
      and data[offset + 1] == 0x75 -- "u"
      and data[offset + 2] == 0x6c -- "l"
      and data[offset + 3] == 0x6c
    then -- "l"
      offset = offset + 4
      return offset, 'null', offset - 4
    elseif
      c == 0x6e
      and offset + 2 < len -- "n"
      and data[offset + 1] == 0x61 -- "a"
      and data[offset + 2] == 0x6e
    then -- "n"
      offset = offset + 3
      return offset, 'nan', offset - 3
    elseif
      c == 0x69
      and offset + 2 < len -- "i"
      and data[offset + 1] == 0x6e -- "n"
      and data[offset + 2] == 0x66
    then -- "f"
      offset = offset + 3
      return offset, 'inf', offset - 3
    elseif
      c == 0x2d
      and offset + 3 < len -- "-"
      and data[offset + 1] == 0x69 -- "i"
      and data[offset + 2] == 0x6e -- "n"
      and data[offset + 3] == 0x66
    then -- "f"
      offset = offset + 4
      return offset, '-inf', offset - 4
    elseif c == 0x22 then -- double quote
      -- Parse Strings
      local start = offset
      offset = offset + 1
      while offset < len do
        c = data[offset]
        if c == 0x22 then -- double quote
          offset = offset + 1
          return offset, 'string', start
        elseif c == 0x5c then -- backslash
          offset = offset + 2
        elseif c == 0x0d or c == 0x0a then -- "\r" | "\n"
          -- newline is not allowed
          break
        else -- other characters
          offset = offset + 1
        end
      end
      return offset, 'error', offset
    elseif
      c == 0x2d -- "-"
      or (c >= 0x30 and c <= 0x39)
    then -- "0"-"9"
      local start = offset
      offset = offset + 1
      offset = consume_digits(data, offset, len)
      local matched
      offset, matched = consume_optional(data, offset, len, 0x2e) -- "."
      if matched then
        offset = consume_digits(data, offset, len)
      end
      offset, matched = consume_optional(data, offset, len, 0x45, 0x65) -- "e"|"E"
      if matched then
        offset = consume_optional(data, offset, len, 0x2b, 0x2d) -- "+"|"-"
        offset = consume_digits(data, offset, len)
      end
      return offset, 'number', start
    elseif c == 0x3c then -- "<"
      local start = offset
      offset = offset + 1
      while offset < len do
        c = data[offset]
        if c == 0x09 or c == 0x0a or c == 0x0d or c == 0x20 then -- "\t" | "\n" | "\r" | " "
          offset = offset + 1
          -- Skip whitespace
        elseif (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x41) or (c >= 0x61 and c <= 0x66) then
          -- hex digit
          offset = offset + 1
        elseif c == 0x3e then -- ">"
          offset = offset + 1
          return offset, 'bytes', start
        else
          break
        end
      end
      return offset, 'error', offset
    elseif c == 0x26 then -- "&" then
      -- parse refs
      local start = offset
      offset = offset + 1
      if offset > len then
        return offset, 'error', offset
      else
        offset = consume_digits(data, offset, len)
        return offset, 'ref', start
      end
    else
      return offset, 'error', offset
    end
  end
  return offset, 'eos', offset
end

Tibs.next_token = next_token

local function is_cdata_integer(val)
  return istype(I64, val)
    or istype(I32, val)
    or istype(I16, val)
    or istype(I8, val)
    or istype(U64, val)
    or istype(U32, val)
    or istype(U16, val)
    or istype(U8, val)
end

local any_to_tibs

--- ipairs that uses metamethods for __len and __index instead of using rawlen and rawget
local function ipairs_smart(t)
  local i = 0
  local l = #t
  return function()
    if i < l then
      i = i + 1
      return i, t[i]
    end
  end
end

---@param writer ByteWriter
---@param val any[]
---@param opener string
---@param closer string
---@param as_json? boolean if truthy, encode as JSON only
---@return string? error
local function list_to_tibs(writer, val, opener, closer, as_json)
  writer:write_string(opener)
  local mt = getmetatable(val)
  local ipair_auto = mt and (mt.__ipairs or mt.__pairs) or ipairs_smart
  for i, v in ipair_auto(val) do
    if i > 1 then
      writer:write_string ','
    end
    local err = any_to_tibs(writer, v, as_json)
    if err then
      return err
    end
  end
  writer:write_string(closer)
end

---@param writer ByteWriter
---@param scope {[1]:Value,[2]:List}
---@return string? error
local function scope_to_tibs(writer, scope)
  local val, dups = scope[1], scope[2]
  if not val or type(dups) ~= 'table' then
    error 'Unexpected scope type'
  end

  writer:write_string '('
  -- scope_to_tibs will never happen in the as_json=true path
  local err = any_to_tibs(writer, val, false)
  if err then
    return err
  end
  for _, v in ipairs_smart(dups) do
    writer:write_string ','
    err = any_to_tibs(writer, v, false)
    if err then
      return err
    end
  end
  writer:write_string ')'
end

---@param writer ByteWriter
---@param opener "{"|"{#"
---@param val table<any,any>
---@param as_json? boolean if truthy, encode as JSON only
---@return string? error
local function map_to_tibs(writer, val, opener, as_json)
  writer:write_string(opener)
  local need_comma = false
  for k, v in pairs(val) do
    if need_comma then
      writer:write_string ','
    end
    need_comma = true
    if as_json then
      local kind = type(k)
      if kind == 'number' or kind == 'boolean' then
        k = tostring(k)
      elseif kind ~= 'string' then
        return 'Invalid ' .. kind .. ' as object key when using JSON encode mode'
      end
    end
    local err = any_to_tibs(writer, k, as_json)
    if err then
      return err
    end
    writer:write_string ':'
    err = any_to_tibs(writer, v, as_json)
    if err then
      return err
    end
  end
  writer:write_string '}'
end

local function bytes_to_tibs(writer, val)
  local size = sizeof(val)
  local bytes = cast(U8Ptr, val)
  writer:write_string '<'
  for i = 0, size - 1 do
    writer:write_string(string.format('%02x', bytes[i]))
  end
  writer:write_string '>'
end

local json_escapes = {
  [0x08] = '\\b',
  [0x09] = '\\t',
  [0x0a] = '\\n',
  [0x0c] = '\\f',
  [0x0d] = '\\r',
  [0x22] = '\\"',
  -- [0x2f] = "\\/",
  [0x5c] = '\\\\',
}
local json_unescapes = {
  [0x62] = '\b',
  [0x74] = '\t',
  [0x6e] = '\n',
  [0x66] = '\f',
  [0x72] = '\r',
  [0x22] = '"',
  [0x2f] = '/',
  [0x5c] = '\\',
}

local function escape_char(c)
  return json_escapes[c] or string.format('\\u%04x', c)
end

local function string_to_tibs(writer, str)
  local is_plain = true
  for i = 1, #str do
    local c = byte(str, i)
    if c < 0x20 or json_escapes[c] then
      is_plain = false
      break
    end
  end
  if is_plain then
    writer:write_string '"'
    writer:write_string(str)
    return writer:write_string '"'
  end
  writer:write_string '"'
  local ptr = cast(U8Ptr, str)
  local start = 0
  local len = #str
  for i = 0, len - 1 do
    local c = ptr[i]
    if c < 0x20 or json_escapes[c] then
      if i > start then
        writer:write_bytes(ptr + start, i - start)
      end
      start = i + 1
      writer:write_string(escape_char(c))
    end
  end
  if len > start then
    writer:write_bytes(ptr + start, len - start)
  end
  return writer:write_string '"'
end

---@param writer ByteWriter
---@param as_json? boolean if truthy, encode as JSON only
---@param val any
---@return string? error
function any_to_tibs(writer, val, as_json)
  local as_tibs = not as_json
  local mt = getmetatable(val)
  if mt then
    if as_tibs and mt.__is_ref then
      writer:write_string '&'
      writer:write_string(tostring(val[1]))
      return
    elseif as_tibs and mt.__is_scope then
      return scope_to_tibs(writer, val)
    elseif mt.__is_array_like == true then
      if as_tibs and mt.__is_indexed then
        return list_to_tibs(writer, val, '[#', ']')
      else
        return list_to_tibs(writer, val, '[', ']', as_json)
      end
    elseif mt.__is_array_like == false then
      if as_tibs and mt.__is_indexed then
        return map_to_tibs(writer, val, '{#')
      else
        return map_to_tibs(writer, val, '{', as_json)
      end
    end
  end
  local kind = type(val)
  if kind == 'cdata' then
    if is_cdata_integer(val) then
      writer:write_string(tostring(val):gsub('[IUL]+', ''))
    elseif as_json then
      return string_to_tibs(writer, ffi.string(val, sizeof(val)))
    else
      return bytes_to_tibs(writer, val)
    end
  elseif kind == 'table' then
    local i = 0
    local is_array = true
    local is_empty = true
    for k in pairs(val) do
      is_empty = false
      i = i + 1
      if k ~= i then
        is_array = false
        break
      end
    end
    if is_array and not is_empty then
      return list_to_tibs(writer, val, '[', ']', as_json)
    else
      return map_to_tibs(writer, val, '{', as_json)
    end
  elseif kind == 'string' then
    string_to_tibs(writer, val)
  elseif kind == 'number' then
    if as_tibs and val ~= val then
      writer:write_string 'nan'
    elseif as_tibs and val == math.huge then
      writer:write_string 'inf'
    elseif as_tibs and val == -math.huge then
      writer:write_string '-inf'
    elseif tonumber(I64(val)) == val then
      local int_str = tostring(I64(val))
      writer:write_string(int_str:sub(1, -3))
    else
      writer:write_string(tostring(val))
    end
  elseif kind == 'nil' then
    writer:write_string 'null'
  elseif kind == 'boolean' then
    writer:write_string(val and 'true' or 'false')
  else
    return 'Unsupported type: ' .. kind
  end
end

---@param val any
---@return string? tibs encoded string
---@return string? error message
function Tibs.encode(val)
  local writer = ByteWriter.new(0x10000)
  local err = any_to_tibs(writer, val)
  if err then
    return nil, err
  end
  return writer:to_string()
end

---@param val any
---@return string? json encoded string
---@return string? error message
function Tibs.encode_json(val)
  local writer = ByteWriter.new(0x10000)
  local err = any_to_tibs(writer, val, true)
  if err then
    return nil, err
  end
  return writer:to_string()
end

---@alias Bytes integer[] cdata uint8_t[?]
---@alias Value List|Map|Array|Trie|Bytes|number|integer|string|boolean|nil

---@param c integer
---@return boolean
local function is_hex_char(c)
  return (c <= 0x39 and c >= 0x30) or (c <= 0x66 and c >= 0x61) or (c >= 0x41 and c <= 0x46)
end

--- Convert ascii hex digit to integer
--- Assumes input is valid character [0-9a-fA-F]
---@param c integer ascii code for hex digit
---@return integer num value of hex digit (0-15)
local function from_hex_char(c)
  return c - (c <= 0x39 and 0x30 or c >= 0x61 and 0x57 or 0x37)
end

local highPair = nil
---@param c integer
local function utf8_encode(c)
  -- Encode surrogate pairs as a single utf8 codepoint
  if highPair then
    local lowPair = c
    c = ((highPair - 0xd800) * 0x400) + (lowPair - 0xdc00) + 0x10000
  elseif c >= 0xd800 and c <= 0xdfff then --surrogate pair
    highPair = c
    return
  end
  highPair = nil

  if c <= 0x7f then
    return char(c)
  elseif c <= 0x7ff then
    return char(bor(0xc0, rshift(c, 6)), bor(0x80, band(c, 0x3f)))
  elseif c <= 0xffff then
    return char(bor(0xe0, rshift(c, 12)), bor(0x80, band(rshift(c, 6), 0x3f)), bor(0x80, band(c, 0x3f)))
  elseif c <= 0x10ffff then
    return char(
      bor(0xf0, rshift(c, 18)),
      bor(0x80, band(rshift(c, 12), 0x3f)),
      bor(0x80, band(rshift(c, 6), 0x3f)),
      bor(0x80, band(c, 0x3f))
    )
  else
    error 'Invalid codepoint'
  end
end

local function parse_advanced_string(data, first, last)
  local writer = ByteWriter.new(last - first)
  local allowHigh
  local start = first + 1
  last = last - 1

  local function flush()
    if first > start then
      writer:write_bytes(data + start, first - start)
    end
    start = first
  end

  local function write_char_code(c)
    local utf8 = utf8_encode(c)
    if utf8 then
      writer:write_string(utf8)
    else
      allowHigh = true
    end
  end

  while first < last do
    allowHigh = false
    local c = data[first]
    if c >= 0xd8 and c <= 0xdf and first + 1 < last then -- Manually handle native surrogate pairs
      flush()
      write_char_code(bor(lshift(c, 8), data[first + 1]))
      first = first + 2
      start = first
    elseif c == 0x5c then -- "\\"
      flush()
      first = first + 1
      if first >= last then
        writer:write_string '�'
        start = first
        break
      end
      c = data[first]
      if c == 0x75 then -- "u"
        first = first + 1
        -- Count how many hex digits follow the "u"
        local hex_count = (
          (first < last and is_hex_char(data[first]))
            and ((first + 1 < last and is_hex_char(data[first + 1])) and ((first + 2 < last and is_hex_char(
              data[first + 2]
            )) and ((first + 3 < last and is_hex_char(data[first + 3])) and 4 or 3) or 2) or 1)
          or 0
        )
        -- Emit � if there are less than 4
        if hex_count < 4 then
          writer:write_string '�'
          first = first + hex_count
          start = first
        else
          write_char_code(
            bor(
              lshift(from_hex_char(data[first]), 12),
              lshift(from_hex_char(data[first + 1]), 8),
              lshift(from_hex_char(data[first + 2]), 4),
              from_hex_char(data[first + 3])
            )
          )
          first = first + 4
          start = first
        end
      else
        local escape = json_unescapes[c]
        if escape then
          writer:write_string(escape)
          first = first + 1
          start = first
        else
          -- Other escapes are included as-is
          start = first
          first = first + 1
        end
      end
    else
      first = first + 1
    end
    if highPair and not allowHigh then
      -- If the character after a surrogate pair is not the other half
      -- clear it and decode as �
      highPair = nil
      writer:write_string '�'
    end
  end
  if highPair then
    -- If the last parsed value was a surrogate pair half
    -- clear it and decode as �
    highPair = nil
    writer:write_string '�'
  end
  flush()
  return writer:to_string()
end

--- Parse a JSON string into a lua string
--- @param data integer[]
--- @param first integer
--- @param last integer
--- @return string
local function tibs_parse_string(data, first, last)
  -- Quickly scan for any escape characters or surrogate pairs
  for i = first + 1, last - 1 do
    local c = data[i]
    if c == 0x5c or (c >= 0xd8 and c <= 0xdf) then
      return parse_advanced_string(data, first, last)
    end
  end
  -- Return as-is if it's simple
  return ffi_string(data + first + 1, last - first - 2)
end
Tibs.parse_string = tibs_parse_string

--- @param data integer[]
--- @param first integer
--- @param last integer
local function is_integer(data, first, last)
  if data[first] == 0x2d then -- "-"
    first = first + 1
  end
  while first < last do
    local c = data[first]
    -- Abort if anything is seen that's not "0"-"9"
    if c < 0x30 or c > 0x39 then
      return false
    end
    first = first + 1
  end
  return true
end

--- Convert an I64 to a normal number if it's in the safe range
---@param n integer cdata I64
---@return integer|number maybeNum
local function to_number_maybe(n)
  return (n <= 0x1fffffffffffff and n >= -0x1fffffffffffff) and tonumber(n) or n
end

-- Parse a JSON number Literal
--- @param data integer[]
--- @param first integer
--- @param last integer
--- @return number num
local function tibs_parse_number(data, first, last)
  if is_integer(data, first, last) then
    -- sign is reversed since we need to use the negative range of I64 for full precision
    -- notice that the big value accumulated is always negative.
    local sign = -1LL
    local big = 0LL
    while first < last do
      local c = data[first]
      if c == 0x2d then -- "-"
        sign = 1LL
      else
        big = big * 10LL - I64(data[first] - 0x30)
      end
      first = first + 1
    end

    return to_number_maybe(big * sign)
  else
    return tonumber(ffi_string(data + first, last - first), 10)
  end
end
Tibs.parse_number = tibs_parse_number

-- Parse a Tibs Bytes Literal <xx xx ...>
---@param data integer[]
---@param first integer
---@param last integer
---@return integer offset
---@return Bytes? buf
local function tibs_parse_bytes(data, first, last)
  local nibble_count = 0
  local i = first + 1
  while i < last - 1 do
    local c = data[i]
    i = i + 1
    if is_hex_char(c) then
      nibble_count = nibble_count + 1
      c = data[i]
      i = i + 1
      if is_hex_char(c) then
        nibble_count = nibble_count + 1
      else
        return i
      end
    end
  end

  if nibble_count % 2 > 0 then
    return i
  end
  local size = rshift(nibble_count, 1)
  local bytes = U8Arr(size)
  local offset = 0
  i = first + 1
  while i < last - 1 do
    local c = data[i]
    i = i + 1
    if is_hex_char(c) then
      local high = lshift(from_hex_char(c), 4)
      c = data[i]
      i = i + 1
      bytes[offset] = bor(high, from_hex_char(c))
      offset = offset + 1
    end
  end

  return last, bytes
end

-- Parse a Tibs Ref Literal
---@param data integer[]
---@param first integer
---@param last integer
---@return Ref
local function tibs_parse_ref(data, first, last)
  return setmetatable({ tibs_parse_number(data, first + 1, last) }, Ref)
end

-- Format a Tibs Syntax Error
---@param tibs string
---@param error_offset integer?
---@param filename? string
---@return string error
local function format_syntax_error(tibs, error_offset, filename)
  local c = error_offset and char(byte(tibs, error_offset + 1))
  if c then
    local index = error_offset + 1
    local before = string.sub(tibs, 1, index)
    local row = 1
    local offset = 0
    for i = 1, #before do
      if string.byte(before, i) == 0x0a then
        row = row + 1
        offset = i
      end
    end
    local col = index - offset
    return string.format('Tibs syntax error: Unexpected %q (%s:%d:%d)', c, filename or '[input string]', row, col)
  end
  return 'Lexer error: Unexpected EOS'
end
Tibs.format_syntax_error = format_syntax_error

local tibs_parse_any

---@generic T : List|Array
---@param data integer[]
---@param offset integer
---@param len integer
---@param meta T
---@param closer "]"|")"
---@return integer offset
---@return T? list
local function tibs_parse_list(data, offset, len, meta, closer)
  local list = setmetatable({}, meta)
  local token, start, value
  offset, token, start = next_token(data, offset, len)
  local i = 0
  while token ~= closer do
    offset, value = tibs_parse_any(data, offset, len, token, start)
    if offset < 0 then
      return offset
    end

    i = i + 1
    list[i] = value

    offset, token, start = next_token(data, offset, len)
    if token == ',' then
      offset, token, start = next_token(data, offset, len)
    elseif token ~= closer then
      return -offset
    end
  end

  return offset, list
end

---@param data integer[]
---@param offset integer
---@param len integer
local function tibs_parse_scope(data, offset, len)
  local token, start
  offset, token, start = next_token(data, offset, len)
  local value
  offset, value = tibs_parse_any(data, offset, len, token, start)
  offset, token = next_token(data, offset, len)
  local dups
  if token == ',' then
    offset, dups = tibs_parse_list(data, offset, len, List, ')')
  elseif token == ')' then
    dups = setmetatable({}, List)
  else
    return -offset
  end
  return offset, setmetatable({ value, dups }, Scope)
end

-- Parse a Tibs Map {x:y, ...}
---@generic T : Map|Trie
---@param data integer[]
---@param offset integer
---@param len integer
---@param meta T
---@return integer offset
---@return T? map
local function tibs_parse_map(data, offset, len, meta)
  local map = setmetatable({}, meta)
  local token, start, key, value
  offset, token, start = next_token(data, offset, len)
  while token ~= '}' do
    offset, key = tibs_parse_any(data, offset, len, token, start)
    if offset < 0 then
      return offset
    end

    offset, token = next_token(data, offset, len)
    if token ~= ':' then
      return -offset
    end

    offset, token, start = next_token(data, offset, len)
    offset, value = tibs_parse_any(data, offset, len, token, start)
    if offset < 0 then
      return offset
    end

    map[key] = value

    offset, token, start = next_token(data, offset, len)
    if token == ',' then
      offset, token, start = next_token(data, offset, len)
    elseif token ~= '}' then
      return -offset
    end
  end

  return offset, map
end

---comment
---@param data integer[]
---@param offset integer
---@param len integer
---@param token LexerToken
---@param start integer
---@return integer offset negative when error
---@return any? value unset when error
function tibs_parse_any(data, offset, len, token, start)
  if token == 'number' then
    return offset, tibs_parse_number(data, start, offset)
  elseif token == 'nan' then
    return offset, 0 / 0
  elseif token == 'inf' then
    return offset, 1 / 0
  elseif token == '-inf' then
    return offset, -1 / 0
  elseif token == 'true' then
    return offset, true
  elseif token == 'false' then
    return offset, false
  elseif token == 'null' then
    return offset, nil
  elseif token == 'ref' then
    return offset, tibs_parse_ref(data, start, offset)
  elseif token == 'bytes' then
    return tibs_parse_bytes(data, start, offset)
  elseif token == 'string' then
    return offset, tibs_parse_string(data, start, offset)
  elseif token == '[' then
    if offset - start > 1 then
      return tibs_parse_list(data, offset, len, Array, ']')
    else
      return tibs_parse_list(data, offset, len, List, ']')
    end
  elseif token == '{' then
    if offset - start > 1 then
      return tibs_parse_map(data, offset, len, Trie)
    else
      return tibs_parse_map(data, offset, len, Map)
    end
  elseif token == '(' then
    return tibs_parse_scope(data, offset, len)
  else
    return -start
  end
end

---@param tibs string
---@param filename? string
---@return any? value
---@return string? error
function Tibs.decode(tibs, filename)
  local data = cast(U8Ptr, tibs)
  local offset = 0
  local len = #tibs
  local token, start
  offset, token, start = next_token(data, offset, len)
  local value
  offset, value = tibs_parse_any(data, offset, len, token, start)
  if offset < 0 then
    return nil, format_syntax_error(tibs, -offset, filename)
  else
    return value
  end
end

return Tibs
