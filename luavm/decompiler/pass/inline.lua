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
				inlineIR.disabled = "inline"
				t[i] = inlineIR.src[1]
				
				actuallyDidSomething = true
			end
		end
		
		-- Recursively inline explets in blocks
		local function inlineBlock(irBlock)
			for i=1, #irBlock do
				ir = irBlock[i]
				if ir.src then analyzer.forEachRegisterInEachExplet(ir.src, handleSource) end
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
