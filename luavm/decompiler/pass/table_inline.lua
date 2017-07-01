-- Table Inline Pass: Inlines table sets into the table declaration --
-- This works by indexing blocks backwards
-- If we find a set instruction on a table destination and the src does not use the declared table
-- or the parent tables then we can inline

--[[
Example:

local tab = {}
tab[1] = {}
tab[1][2] = "hi"
tab.a = 5
tab.b = tab
tab.c = tab.a
tab.d = tab[1][2]

to

local tab = {{[2] = "hi"}, a = 5}
tab.b = tab
tab.c = tab.a
tab.d = tab[1][2]

]]

return function(decompiler)
local analyzer = decompiler.analyzer
return function(irBlock)
	local liveRanges = irBlock.liveRanges
	print("Starting table inline")

	-- Pass 1: Find table declarations and their live ranges
	print("Finding table decls")
	local decls = {
		--[[
		[0] = {
			{ir pos, ir block, live range, table}
		}
		]]
	}
	do
		local function scanBlock(irBlock)
			for i=1, #irBlock do
				local ir = irBlock[i]
				if ir.src and #ir.src == 1 and ir.src[1][1] == "value" and type(ir.src[1][2]) == "table" then
					-- If the ir part has a single source as a value that holds a table
					print("Found a table")
					if ir.dest and #ir.dest == 1 and ir.dest[1][1] == "register" then
						-- If it has a single dest and it is a register
						local reg = ir.dest[1][2]
						local regdecls = decls[reg]
						if not regdecls then
							regdecls = {}
							decls[reg] = regdecls
						end
						regdecls[#regdecls+1] = {i, irBlock, analyzer.findRange(liveRanges[reg], i), ir.src[1][2]}
					end
				end

				if ir.block then
					scanBlock(ir.block)
				end
			end
		end

		scanBlock(irBlock)
	end

	print("Collecting table sets")
	do
		local function scanBlock(irBlock)
			for i=1, #irBlock do
				local ir = irBlock[i]
				if ir.dest and #ir.dest == 1 and ir.dest[1][1] == "index" and ir.dest[1][2][1] == "register" then
					local sets = decls[ir.dest[1][2][2]]
					for j=1, #sets do
						local tabdecl = sets[j]
						if tabdecl[2] == irBlock and i >= tabdecl[3][1] and i <= tabdecl[3][2] then
							print("Can inline into table at "..tabdecl[1])
							tabdecl[4][ir.dest[1][3]] = ir.src[1]
							ir.disabled = "table_inline"
						end
					end
				end

				if ir.block then
					scanBlock(ir.block)
				end
			end
		end

		scanBlock(irBlock)
	end

	--[=[for pass=1, 3 do
		print("Starting inline pass "..pass)
		local ir
		local actuallyDidSomething = false -- If a pass does nothing then the loop is exit early

		local function handleSource(reg, t, i)
			local possible, inlineIR = analyzer.isInlinePossible(liveRanges, reg, ir.pc)
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

		inlineBlock(irBlock)

		if not actuallyDidSomething then
			print("Nothing done in inline pass "..pass)
			break
		else
			irBlock.liveRanges = analyzer.computeLiveRanges(irBlock)
		end
	end]=]
end
end
