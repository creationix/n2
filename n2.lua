local ffi = require("ffi")
local istype = ffi.istype
local bit = require("bit")
local bor = bit.bor
local band = bit.band
local lshift = bit.lshift
local arshift = bit.arshift
local bxor = bit.bxor

local U8 = ffi.typeof("uint8_t[?]")
local U8 = ffi.typeof("uint8_t")
local U16 = ffi.typeof("uint16_t")
local U32 = ffi.typeof("uint32_t")
local U64 = ffi.typeof("uint64_t")
local I8 = ffi.typeof("int8_t")
local I16 = ffi.typeof("int16_t")
local I32 = ffi.typeof("int32_t")
local I64 = ffi.typeof("int64_t")
local F32 = ffi.typeof("float")
local F64 = ffi.typeof("double")

local u64Box = ffi.new("uint64_t[1]")
local u32Box = ffi.new("uint32_t[1]")
local u16Box = ffi.new("uint16_t[1]")
local i64Box = ffi.new("int64_t[1]")
local i32Box = ffi.new("int32_t[1]")
local i16Box = ffi.new("int16_t[1]")
local i8Box = ffi.new("int8_t[1]")

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
	if str:find("e") then
		-- Split the string into base and exponent
		local base, exponent = str:match("(-?[%d%.]+)e([+-]?%d+)")
		exponent = tonumber(exponent)
		-- Check for decimal in base
		local decimal_pos = base:find(".", 1, true)
		if decimal_pos then
			-- Remove the decimal point
			base = base:gsub("%.", "")
			-- Count the number of digits after the decimal point
			local decimal_count = #base - (decimal_pos - 1)
			-- Adjust the exponent accordingly
			exponent = exponent - decimal_count
		end
		return tonumber(base), exponent
	end
	local decimal_pos = str:find("%.")
	if decimal_pos then
		-- Remove the decimal point
		local base = str:gsub("%.", "")
		-- Adjust the exponent accordingly
		return tonumber(base), decimal_pos - #str
	end
	-- Count trailing zeroes
	local zeroes_pos = str:find("0+$")
	if zeroes_pos then
		local base = str:sub(1, zeroes_pos - 1)
		local exponent = #str - zeroes_pos + 1
		return tonumber(base), exponent
	end
	return val, 0
end

-- Inline unit test for split_number
for i = -200, 200 do
	local base, exponent = split_number(0)
	assert(base == 0, base)
	assert(exponent == 0, exponent)
	base, exponent = split_number(math.pow(10, i))
	assert(base == 1)
	assert(i == exponent, i)
	base, exponent = split_number(314 * math.pow(10, i))
	assert(base == 314)
	assert(i == exponent, i)
	base, exponent = split_number(12345678912345 * math.pow(10, i))
	assert(base == 12345678912345)
	assert(i == exponent, i)
end

---@param val table
local function is_array_like(val)
	local mt = getmetatable(val)
	if mt and mt.__is_array_like ~= nil then
		return mt.__is_array_like
	end
	local i = 0
	for k in pairs(val) do
		i = i + 1
		if k ~= i then
			return false
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
		p({ size = size, buf = buf, byte = byte })
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
		if val >= -14 and val < 14 then
			-- Small signed numbers use zigzag encoding
			return bxor(lshift(val, 1), arshift(val, 31))
		elseif val >= -0x80 and val < 0x80 then
			i8Box[0] = val
			write_binary(i8Box, 1)
			return 28
		elseif val >= -0x8000 and val < 0x8000 then
			i16Box[0] = val
			write_binary(i16Box, 2)
			return 29
		elseif val >= -0x80000000 and val < 0x80000000 then
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
		p("encode_integer", val)
		write_signed_pair(NUM, val)
	end

	local function encode_number(val)
		if val == math.floor(val) and val >= -0x8000 and val < 0x8000 then
			-- Fast path for small integers that are always better as non-extended
			encode_integer(val)
		else
			-- Use extended encoding for all other numbers
			write_signed_pair_ext(EXT, NUM, split_number(val))
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
		local height
		for i, v in ipairs(lst) do
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
		for k, v in pairs(map) do
			height = height + 1
			stack[height] = v
			height = height + 1
			stack[height] = k
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
			if typ == "string" then
				encode_string(val)
			elseif typ == "number" then
				encode_number(val)
			elseif typ == "table" then
				encode_table(val)
			elseif typ == "cdata" then
				if is_integer(val) then
					encode_integer(val)
				else
					encode_binary(val)
				end
			else
				error("Unsupported type: " .. typ)
			end
		end
	end

	encode_any(root_val)
	return ffi.string(buf, size)
end

local oct_lookup = {
	[0x0] = "0000",
	[0x1] = "0001",
	[0x2] = "0010",
	[0x3] = "0011",
	[0x4] = "0100",
	[0x5] = "0101",
	[0x6] = "0110",
	[0x7] = "0111",
	[0x8] = "1000",
	[0x9] = "1001",
	[0xA] = "1010",
	[0xB] = "1011",
	[0xC] = "1100",
	[0xD] = "1101",
	[0xE] = "1110",
	[0xF] = "1111",
}

local hex_lookup = {}
for i = 0, 255 do
	hex_lookup[i] = oct_lookup[arshift(i, 4)] .. oct_lookup[band(i, 0x0f)]
end

local function test(value)
	print()
	p(value)
	local data = encode(value)
	local bytes = {}
	for i = 1, #data do
		local b = data:byte(i)
		bytes[i] = hex_lookup[b]
	end
	print(table.concat(bytes, " "))
end

test(0)
test(-1)
test(1)
test(13)
test(-14)
test(14)
test(-15)
test(100)
test(-100)
test(-127)
test(127)
test(-128)
test(128)
test(-129)

test(1e10)
test(1e20)
test(1e30)
test(123.456)
test(12345.6789)
test(math.pi)
test(math.pi * 1e300)
test(math.pi * 1e-300)

test("")
test("Hello World")
test("Hello World" .. string.rep("!", 100))

test({ 1, 2, 3 })
test({ name = "N2", new = true })

local bin = U8(8)
bin[0] = 1
bin[1] = 3
bin[2] = 7
bin[3] = 15
bin[4] = 31
bin[5] = 63
bin[6] = 127
bin[7] = 255
test(bin)

test(123ULL)
-- print(encode(""))
-- print(encode("Hello World"))
-- print(encode(("Hello World"):rep(10)))
