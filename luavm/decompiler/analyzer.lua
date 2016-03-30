-- Analyzer: Analyzes decoded bytecode to create data structures that are integral to the decompilation process --

-- Sample Destination Output:
-- ADD R2, R0, R1
-- ADD R2, R2, K0 [3]
-- RETURN R2
--[[ Output: {
	liveRanges = { -- Per register live ranges
		-- A live range is a set, followed by several gets, before another set
		-- The first PC is always the one that set the instruction
		-- For argument registers, they start at PC -1 (because they are set before the first instruction runs)
		[0] = {
			{-1, 0} -- Start PC, End PC
		},
		{
			{-1, 0} -- Start PC, End PC
		},
		{
			{0, 1}, -- Start PC, End PC
			{1, 2}
		}
		-- With live ranges, you can easily compute things like inlining.
	}
}]]

-- The analyzer is also responsible for computing exact register usage positions when asked --

local analyzer = {}

-- Helper functions for iterating through registers used in an explet
local function forEachRegister(explet, func, parent, parentIndex)
	if explet[1] == "register" then
		func(explet[2], parent, parentIndex, false)
	elseif explet[1] == "constant" then --ignore
	elseif explet[1] == "global" then --ignore
	elseif explet[1] == "value" then --ignore
	elseif explet[1] == "binaryop" then
		forEachRegister(explet[2], func, explet, 2)
		forEachRegister(explet[4], func, explet, 4)
	elseif explet[1] == "unaryop" then
		forEachRegister(explet[3], func, explet, 3)
	elseif explet[1] == "call" then
		forEachRegister(explet[2], func, explet, 2)
		local args = explet[3]
		for i=1, #args do
			forEachRegister(args[i], func, args, i)
		end
	elseif explet[1] == "index" then
		forEachRegister(explet[2], func, explet, 2)
		forEachRegister(explet[3], func, explet, 3)
	else
		error("Unsupported explet type in analyzer: "..explet[1])
	end
end

-- Helper functions for iterating through registers used multiple explets
local function forEachRegisterInEachExplet(explets, func, toplevelOnly)
	if toplevel then
		for i=1, #explets do
			local explet = explets[i]
			if explet[1] == "register" then
				func(explet[2], explets, i, true)
			end
		end
	else
		for i=1, #explets do
			local explet = explets[i]
			if explet[1] == "register" then
				func(explet[2], explets, i, true)
			else
				forEachRegister(explet, func, explets, i)
			end
		end
	end
end

analyzer.forEachRegister = forEachRegister
analyzer.forEachRegisterInEachExplet = forEachRegisterInEachExplet

function analyzer.computeLiveRanges(irBlock)
	-- Recursively flatten sources and create a list of used registers in the block (for per register state)
	local registers = {}
	
	local currentBlock = irBlock
	local ir
	
	local function makeRange(s, e, set)
		return {s, e, set = set, gets = 0, block = currentBlock}
	end
	
	local function handleSource(reg)
		if not registers[reg] then
			registers[reg] = {makeRange(-1, 0), argument = true}
		end
		local r = registers[reg]
		local rrange = r[#r]
		rrange[2] = ir.pc
		rrange.gets = rrange.gets+1
		if rrange.block ~= currentBlock then
			rrange.crossBlock = true
		end
	end
	
	local function handleDest(reg, _, _, toplevel)
		if toplevel then
			if not registers[reg] then
				registers[reg] = {makeRange(ir.pc, ir.pc, ir)}
			else
				local r = registers[reg]
				r[#r+1] = makeRange(ir.pc, ir.pc, ir)
			end
		else
			-- A non top level destination is actually just a source, since the destination gets set indirectly
			handleSource(reg)
		end
	end
	
	local function doBlock(irBlock)
		currentBlock = irBlock
		for i=1, #irBlock do
			ir = irBlock[i]
			if not ir.disabled then
				if ir.src then forEachRegisterInEachExplet(ir.src, handleSource) end
				if ir.dest then forEachRegisterInEachExplet(ir.dest, handleDest) end
				if ir.block then
					local wasSubBlock = inSubBlock
					inSubBlock = true
					doBlock(ir.block)
					currentBlock = irBlock
					inSubBlock = wasSubBlock
					-- Sub register ranges are marked inside the current register range
					-- When a register range has sub ranges it cannot be used for inlines
					-- Sub ranges are added when the register is used inside the sub range
					-- Sub ranges include regular blocks and closures
				end
			end
		end
	end
	
	doBlock(irBlock)
	
	return registers
end

-- Helper method to find the range that pc falls in in a list of register ranges
local function findRange(ranges, pc)
	for i=1, #ranges do
		local range = ranges[i]
		if pc >= range[1] and pc <= range[2] then
			return range
		end
	end
end

analyzer.findRange = findRange

-- Computes whether an inline is possible for a register
function analyzer.isInlinePossible(liveRanges, reg, pc)
	-- Arguments cannot be inlined because they are arguments
	if liveRanges[reg].argument then
		print("Cannot inline register "..reg..": Is argument")
		return false
	end
	
	local range = findRange(liveRanges[reg], pc)
	-- Registers without live ranges cannot be inlined (not enough data)
	if not range then
		print("Cannot inline register "..reg..": Range not found")
		return false
	end
	
	-- Register cannot have multiple gets
	if range.gets > 1 then
		print("Cannot inline register "..reg..": More than one register get")
		return false
	end
	
	-- Registers with multiple uses cannot be inlined
	if range[2] > pc then
		print("Cannot inline register "..reg..": Usage range is greater than current pc")
		return false
	end
	
	-- Registers that are used in multiple blocks cannot be inlined
	if range.crossBlock then
		print("Cannot inline register "..reg..": Cross block usage")
		return false
	end
	
	-- The following checks go off of the instruction that started the register range
	-- If the instruction is disabled, disallow inline
	if range.set.disabled then
		print("Cannot inline register "..reg..": Instruction disabled because "..range.set.disabled)
	end
	
	-- If the instruction with the register dest has multiple dests, inline is canceled
	if #range.set.dest ~= 1 then
		print("Cannot inline register "..reg..": Multiple dests in instruction")
		return false
	end
	
	-- If the instruction has multiple sources, inline is canceled (this shouldn't happen though)
	if #range.set.src ~= 1 then
		print("Cannot inline register "..reg..": Multiple sources in instruction")
		return false
	end
	
	-- If the set instruction has a block, disallow inline (else it would try to inling if statements)
	if range.set.block then
		print("Cannot inline register "..reg..": Instruction has block")
		return false
	end
	
	-- meh, I guess it can be inlined
	return true, range.set
end

return analyzer
