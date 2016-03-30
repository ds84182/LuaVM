-- Inline Pass: Takes immediate representation and inlines --
return function(decompiler)
local analyzer = decompiler.analyzer
return function(irBlock)
	local liveRanges = irBlock.liveRanges
	for pass=1, 3 do
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
	end
end
end
