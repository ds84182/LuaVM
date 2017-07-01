-- Inline Pass: Takes immediate representation and inlines --

local function dumpValue(value, indent, skipTables)
	indent = indent or ""
	local typ = type(value)

	if typ == "table" and (not skipTables or not skipTables[value]) then
		if not skipTables then skipTables = {} end
		skipTables[value] = true
		local buffer = {"{"}
		local currentNumber = 1

		for i, v in pairs(value) do
			if i == currentNumber then
				currentNumber = currentNumber+1
				buffer[#buffer+1] = indent.."\t"..dumpValue(v, indent.."\t", skipTables)
			else
				buffer[#buffer+1] = indent.."\t"..dumpValue(i, indent.."\t", skipTables)..": "..dumpValue(v, indent.."\t", skipTables)
			end
		end

		return table.concat(buffer, "\n").."\n"..indent.."}"
	end

	return tostring(value)
end

return function(decompiler)
local analyzer = decompiler.analyzer
return function(irBlock)
	local liveRanges = irBlock.liveRanges
	for pass=1, 3 do
		print("Starting inline pass "..pass)
		local ir
		local actuallyDidSomething = false -- If a pass does nothing then the loop is exit early

		local function handleSource(reg, t, i)
			local possible, inlineIR = analyzer.isInlinePossible(liveRanges, reg, ir.pc, t.pc)
			if possible then
				-- To inline, we take the first source explet of the IR and put it into where the register used to be
				-- The entire IR expr is then disabled so it doesn't show up in final output
					-- This is so the block doesn't really have to be modified
				inlineIR.disabled = "inline_source"
				t[i] = inlineIR.src[1]

				actuallyDidSomething = true
			end
		end

		-- Recursively inline explets in blocks
		local function inlineBlock(irBlock)
			for i=1, #irBlock do
				ir = irBlock[i]
				if ir.src then analyzer.forEachRegisterInEachExplet(ir.src, handleSource) end
				if ir.dest and #ir.dest == 1 and ir.dest[1][1] ~= "register" and
						#ir.src == 1 and ir.src[1][1] == "register" then
					-- Attempt destination inline
					--[[
					r0, r1 = func()
					b = r1
					a = r0

					TO

					a, b = func()
					]]
					-- Index the current block backwards until we hit an instruction that has our single source reg as a dest reg
					-- Or we could just reuse analyzer usage data :P
					-- TODO: Disable destination inline when global state is modified by dest and used by source!
					-- This means we need more analyzer stuff!
					local dest = ir.dest[1]
					local src = ir.src[1]
					local range = analyzer.findRange(liveRanges[src[2]], ir.pc)
					if range then
						local setir = range.set
						for i=1, #setir.dest do
							local sdest = setir.dest[i]
							if sdest[1] == "register" and sdest[2] == src[2] then
								setir.dest[i] = dest
								ir.disabled = "inline_dest"
								break
							end
						end
					end
				end
				if ir.block then
					inlineBlock(ir.block)
				end
			end
		end

		--TODO: Because of a bug, things need to be rewriten
		-- Register range compatibility needs to be checked in the registers an explet uses before it inlines

		inlineBlock(irBlock)

		if not actuallyDidSomething then
			print("Nothing done in inline pass "..pass)
			break
		else
			irBlock.liveRanges = analyzer.computeLiveRanges(irBlock)
		end
	end
end
end
