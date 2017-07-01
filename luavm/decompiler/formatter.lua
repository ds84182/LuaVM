-- Formatter: Takes IR Expressions and converts them into a list of strings

local formatter = {}

-- TODO: Use this
local _DEFAULTCONFIG = {
	binopSpacing = true, -- whether to emit spaces between binary operators (note: this is force turned on for word based binops)
}

-- TODO: Possibly make a function named formatter.new(bc) that wraps everything so bc doesn't have to be passed around

-- Formats a value into a parsable string representation
function formatter.formatValue(bc, value)
	local typ = type(value)
	if typ == "string" then
		return ("%q"):format(value):gsub("\\\n", "\\n")
	elseif typ == "table" then
		if not next(value) then
			return "{}"
		else
			local integerValues = {}
			local normalValues = {}
			local currentInteger = 1
			for k, v in pairs(value) do
				-- keys and values are explets
				local ktyp = k[1]
				local keystr, integer = nil, false

				if ktyp == "constant" then
					local kconst = bc.constants[k[2]]
					local kconsttyp = type(kconst)
					if kconsttyp == "string" and kconst:find("^[a-zA-Z_][a-zA-Z0-9_]*$") then
						keystr = kconst
					elseif kconsttyp == "number" and kconst == currentInteger then
						keystr = nil
						integerValues[kconst] = formatter.formatExplet(bc, v)
						currentInteger = kconst+1
						integer = true
					end
				end

				if not keystr then
					keystr = "["..formatter.formatExplet(bc, k).."]"
				end

				if not integer then
					normalValues[#normalValues+1] = keystr.." = "..formatter.formatExplet(bc, v)
				end
			end
			return "{"..
				(integerValues[1] and table.concat(integerValues, ",\n")..",\n" or "")..
				(normalValues[1] and table.concat(normalValues, ",\n")..",\n" or "")
			.."}"
		end
	else
		return tostring(value)
	end
end

-- Formats an explet into a parsable string representation
function formatter.formatExplet(bc, explet)
	-- TODO: Handle config
	local typ = explet[1]

	if typ == "register" then
		return "r"..explet[2]
	elseif typ == "binaryop" then
		return formatter.formatExplet(bc, explet[2]).." "..explet[3].." "..formatter.formatExplet(bc, explet[4])
	elseif typ == "unaryop" then
		return explet[2].." "..formatter.formatExplet(bc, explet[3])
	elseif typ == "constant" then
		return formatter.formatValue(bc, bc.constants[explet[2]])
	elseif typ == "global" then
		return bc.constants[explet[2]]
	elseif typ == "value" then
		--[[if type(explet[2]) == "table" then
			return "{}" -- TODO: Render table contents for table inlining
		end]]
		return formatter.formatValue(bc, explet[2])
	elseif typ == "call" then
		return formatter.formatExplet(bc, explet[2]).."("..formatter.formatExplets(bc, explet[3])..")"
	elseif typ == "index" then
		return formatter.formatExplet(bc, explet[2]).."["..formatter.formatExplet(bc, explet[3]).."]"
	else
		error("Unhandle explet "..tostring(typ))
	end
end

function formatter.formatExplets(bc, explets)
	if #explets == 1 then
		return formatter.formatExplet(bc, explets[1])
	else
		local buffer = {}
		for i=1, #explets do
			buffer[i] = formatter.formatExplet(bc, explets[i])
		end
		return table.concat(buffer, ", ")
	end
end

function formatter.formatExpression(bc, irexp)
	if irexp.disabled then return nil end
	if irexp.op == "set" then
		if #irexp.dest == 0 then
			return formatter.formatExplets(bc, irexp.src)
		else
			return formatter.formatExplets(bc, irexp.dest).." = "..formatter.formatExplets(bc, irexp.src)
		end
	elseif irexp.op == "return" then
		return "return "..formatter.formatExplets(bc, irexp.src)
	elseif irexp.op == "if" then
		return "if "..formatter.formatExplets(bc, irexp.src).." then\n"..formatter.formatBlock(bc, irexp.block).."\nend"
	elseif irexp.op == "else" then
		return "else\n"..formatter.formatBlock(bc, irexp.block)
	elseif irexp.op == "for" then
		return "for "..formatter.formatExplets(bc, irexp.dest).." = "..formatter.formatExplets(bc, irexp.src).." do\n"..formatter.formatBlock(bc, irexp.block).."\nend"
	elseif irexp.op == "gfor" then
		return "for "..formatter.formatExplets(bc, irexp.dest).." in "..formatter.formatExplets(bc, irexp.src).." do\n"..formatter.formatBlock(bc, irexp.block).."\nend"
	elseif irexp.op == "while" then
		return "while "..formatter.formatExplets(bc, irexp.src).." do\n"..formatter.formatBlock(bc, irexp.block).."\nend"
	elseif irexp.op == "break" then
		return "break"
	else
		error("Unsupported ir exp "..tostring(irexp.op))
	end
	--return dumpValue(irexp)
end

function formatter.formatBlock(bc, irblock)
	local buffer = {}
	for i=1, #irblock do
		buffer[#buffer+1] = formatter.formatExpression(bc, irblock[i])
	end
	return table.concat(buffer, "\n")
end

function formatter.formatFunction(bc, irblock, name)
	local buffer = {"function", name and " "..name or "", "("}
	-- function prelude
	for i=0, bc.nparam-1 do
		buffer[#buffer+1] = "r"..i
		if i+1 ~= bc.nparam then buffer[#buffer+1] = ", " end
	end
	if bc.isvararg ~= 0 then
		buffer[#buffer+1] = "..."
	end
	buffer[#buffer+1] = ")\n"

	if bc.maxStack-bc.nparam > 0 then
		-- TODO: Most registers are unused after inlining happens
		-- TODO: Some registers are used to track for loop state
		-- TODO: Make block level random variable names and variable definitions
		buffer[#buffer+1] = "local "
		for i=bc.nparam, bc.maxStack-1 do
			buffer[#buffer+1] = "r"..i
			if i+1 ~= bc.maxStack then buffer[#buffer+1] = ", " end
		end
		buffer[#buffer+1] = "\n"
	end

	buffer[#buffer+1] = formatter.formatBlock(bc, irblock)

	buffer[#buffer+1] = "\nend"

	return table.concat(buffer)
end

return formatter
