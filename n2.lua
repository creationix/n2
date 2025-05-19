local ffi = require("ffi")
local bit = require("bit")
local bor = bit.bor
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift

-- Major Types
local INT = 0 -- (zigzag val)
local DEC = 1 -- (zigzag power, zigzag base)
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
local buf = ffi.new("uint8_t[?]", capacity)

---@param val any
---@return string
local function encode(root_val)
	local size = 0

	---@param ... string|integer
	---@return integer
	local function write(...)
		local count = select("#", ...)
		local needed = size
		for i = count, 1, -1 do
			local item = select(i, ...)
			if type(item) == "string" then
				needed = needed + #item
			elseif type(item) == "number" then
				needed = needed + 1
			end
		end
		if needed > capacity then
			repeat
				capacity = capacity * 2
			until capacity >= needed
			local new_buf = ffi.new("uint8_t[?]", capacity)
			ffi.copy(new_buf, buf, size)
			buf = new_buf
		end
		for i = count, 1, -1 do
			local item = select(i, ...)
			if type(item) == "string" then
				local len = #item
				ffi.copy(buf + size, item, len)
				size = size + len
			elseif type(item) == "number" then
				buf[size] = item
				size = size + 1
			end
		end
		return size
	end

	---@param typ integer
	---@param val integer
	---@return integer
	local function encode_pair(typ, val, ...)
		-- If val fits in 4 bits, write it directly
		if val < 16 then
			return write(bor(lshift(val, 4), typ), ...)
		end
		-- If val fits in 4 bits + 7 bits, write it directly
		if val < 2048 then
			return write(bor(lshift(band(val, 0xf), 4), 0x80, typ), rshift(val, 4), ...)
		end
		error("TODO: encode larger numbers")
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
