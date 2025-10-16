local ffi = require 'ffi'
local U8Arr = ffi.typeof 'uint8_t[?]'

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

local function color(val, str)
  local typ = type(val)
  local c
  if typ == 'string' then
    c = LIME
  elseif typ == 'number' then
    c = MINT
  elseif typ == 'boolean' then
    c = PINK
  elseif typ == 'nil' then
    c = DIM .. ITALIC .. WHITE
  elseif typ == 'table' then
    c = MUSTARD
  elseif typ == 'function' then
    c = GOLD
  elseif typ == 'userdata' then
    c = CORAL
  elseif typ == 'thread' then
    c = ORANGE
  elseif typ == 'cdata' then
    if ffi.istype(U8Arr, val) then
      c = SKY
    else
      c = STRAWBERRY
    end
  end
  if c then
    return c .. str .. RESET
  end
  return str
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

local function escape_char(c)
  if c == '\r' then
    return '\\r'
  elseif c == '\n' then
    return '\\n'
  elseif c == '\t' then
    return '\\t'
  elseif c == '"' then
    return '\\"'
  elseif c == "'" then
    return "\\'"
  end
  return '\\' .. string.format('%02x', string.byte(c))
end

-- keywords reserved in dump that must be quoted when used as string keys
local reserved = {
  ['true'] = true,
  ['false'] = true,
  ['nil'] = true,
}

local function dump_string(str)
  if reserved[str] then
    return '"' .. str .. '"'
  end

  if str:match '^[^ "\':,.%[%]%{%}0-9][^ "\':,.%[%]%{%}]*$' then
    return str
  end
  if str:find("'", 1, true) and not str:find('"', 1, true) then
    return '"' .. string.gsub(str, '["\r\n\t]', escape_char) .. '"'
  end
  return "'" .. string.gsub(str, "['\r\n\t]", escape_char) .. "'"
end

local function dump_bytes(bin)
  local str = ffi.string(bin, ffi.sizeof(bin))
  return string.format(
    '<%s>',
    string.gsub(str, '.', function(c)
      return string.format('%02x', c:byte(1))
    end)
  )
end

-- A really simple dump that prints normal lua with lots of whitespace.
local function dump(val, indent)
  if type(val) == 'string' then
    return color(val, dump_string(val))
  end
  if type(val) == 'cdata' and ffi.istype(U8Arr, val) then
    return color(val, dump_bytes(val))
  end
  if type(val) ~= 'table' then
    return color(val, tostring(val))
  end
  indent = indent or 0
  local output_count = 0
  local size = 0
  local output = {}
  local array_like, iter = is_array_like(val)
  for k, v in iter(val) do
    local entry = dump(v, indent + 1)
    if not array_like then
      entry = dump(k, indent + 1) .. ': ' .. entry
    end
    size = size + #entry
    output_count = output_count + 1
    output[output_count] = entry
  end
  local open = array_like and '[' or '{'
  local close = array_like and ']' or '}'
  if output_count == 0 then
    return open .. close
  end
  if size + output_count * 2 + 4 < 200 then
    return open .. ' ' .. table.concat(output, ', ') .. ' ' .. close
  end
  return open
    .. '\n'
    .. string.rep('  ', indent + 1)
    .. table.concat(output, ',\n' .. string.rep('  ', indent + 1))
    .. '\n'
    .. string.rep('  ', indent)
    .. close
end

return dump
