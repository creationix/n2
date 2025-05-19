local ffi = require("ffi")
local bit = require("bit")
local bor = bit.bor
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift

local U8 = ffi.typeof("uint8_t[?]")
local u64Box = ffi.new("uint64_t[1]")
local u32Box = ffi.new("uint32_t[1]")
local u16Box = ffi.new("uint16_t[1]")
local u8Box = ffi.new("uint8_t[1]")
local i64Box = ffi.new("int64_t[1]")
local i32Box = ffi.new("int32_t[1]")
local i16Box = ffi.new("int16_t[1]")
local i8Box = ffi.new("int8_t[1]")

-- Major Types
local NUM = 0 -- (zigzag val)
local EXT = 1 -- (zigzag power, zigzag base)
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

local capacity = 1024
local buf = U8(capacity)

---@param root_val any
---@return string
local function encode(root_val)
	local size = 0

	local function ensure_capacity(needed)
		if needed <= capacity then
			return
		end
		repeat
			capacity = capacity * 2
		until capacity >= needed
		local new_buf = U8(capacity)
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

	---@param typ integer
	---@param val integer
	local function encode_pair(typ, val)
		typ = lshift(typ, 5)
		if val < 28 then
			write_byte(bor(typ, val))
		elseif val < 0x100 then
			write_byte(val)
			write_byte(bor(typ, 12))
		elseif val < 0x10000 then
			u16Box[0] = val
			write_binary(u16Box, 2)
			write_byte(bor(typ))
		elseif val < 0x100000000 then
			u32Box[0] = val
			write_binary(u32Box, 4)
			write_byte(bor(typ))
		else
			u64Box[0] = val
			write_binary(u64Box, 8)
			write_byte(bor(typ))
		end
	end

	local function encode_pairs(typ, val1, val2, ...)
		-- First write val2 using
	end

	---@param str string
	---@return integer
	local function encode_string(str)
		return encode_pair(STR, #str, str)
	end

	if type(root_val) == "string" then
		size = encode_string(root_val)
	else
		error("Unsupported type: " .. type(root_val))
	end

	return ffi.string(buf, size)
end

print(encode(""))
-- print(encode("Hello World"))
-- print(encode(("Hello World"):rep(10)))
