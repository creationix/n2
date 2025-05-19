local function color(val, str)
	local typ = type(val)
	local c
	if typ == "string" then
		c = "\27[0;32m"
	elseif typ == "number" then
		c = "\27[0;34m"
	elseif typ == "boolean" then
		c = "\27[0;35m"
	elseif typ == "nil" then
		c = "\27[0;36m"
	elseif typ == "table" then
		c = "\27[0;33m"
	elseif typ == "function" then
		c = "\27[0;37m"
	elseif typ == "userdata" then
		c = "\27[0;38m"
	elseif typ == "thread" then
		c = "\27[0;39m"
	elseif typ == "cdata" then
		c = "\27[0;31m"
	end
	if c then
		return c .. str .. "\27[0m"
	end
	return str
end

local reserved = {
	["true"] = true,
	["false"] = true,
	["nil"] = true,
}

-- A really simple dump that prints normal lua with lots of whitespace.
local function dump(val, indent)
	if type(val) == "string" then
		return color(val, string.format("%q", val))
	end
	if type(val) ~= "table" then
		return color(val, tostring(val))
	end
	local count = 0
	indent = indent or 0
	local output_count = 0
	local size = 0
	local output = {}
	local mt = getmetatable(val)
	local iter = pairs
	local is_array_like = nil
	if mt then
		if mt.__ipairs then
			iter = mt.__ipairs
			is_array_like = true
		elseif mt.__pairs then
			iter = mt.__pairs
			is_array_like = false
		end
		if mt.__is_array_like ~= nil then
			is_array_like = mt.__is_array_like
		end
	end
	if is_array_like == nil then
		is_array_like = true
		local i = 0
		for k in iter(val) do
			i = i + 1
			if k ~= i then
				is_array_like = false
				break
			end
		end
	end
	for k, v in iter(val) do
		count = count + 1
		local entry = dump(v, indent + 1)
		if k ~= count or is_array_like == false then
			if type(k) == "string" and not reserved[k] and k:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
				entry = color(k, k) .. ": " .. entry
			else
				entry = dump(k, indent + 1) .. ": " .. entry
			end
		end
		size = size + #entry
		output_count = output_count + 1
		output[output_count] = entry
	end
	local open = is_array_like and "[" or "{"
	local close = is_array_like and "]" or "}"
	if count == 0 then
		return open .. close
	end
	if size + output_count * 2 + 4 < 120 then
		return open .. " " .. table.concat(output, ", ") .. " " .. close
	end
	return open
		.. "\n"
		.. string.rep("  ", indent + 1)
		.. table.concat(output, ",\n" .. string.rep("  ", indent + 1))
		.. "\n"
		.. string.rep("  ", indent)
		.. close
end

return dump
