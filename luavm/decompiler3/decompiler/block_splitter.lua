--[[
Block splitter: Splits a stream of instructions into blocks.
]]

return function(decompiler)

function decompiler.isTerminator(instr)
	if not instr then return false end
	if decompiler.terminator[instr[1]] then
		if instr[1] == "loadbool" and not instr.skipNext then
			return false
		end
		return true
	end
	return false
end

function decompiler.splitBlocks(context)
	local decoded = context.decoded
	local splits = {}
	local pc = 0
	while pc <= decoded.last do
		local instr = decoded[pc]
		if instr and decompiler.isTerminator(instr) then
			splits[pc+1] = true

			if instr[1] == "jump" then
				splits[instr.to] = true
			elseif instr[1] == "forprep" or instr[1] == "forloop" then
				splits[instr.target] = true
			elseif instr[1] == "condop" or instr[1] == "loadbool" then
				-- Condops and loadbools can skip the very next instruction
				splits[pc+2] = true
			end
		end
		pc = pc+1
	end

	local sortedSplits = {}
	for i in pairs(splits) do
		sortedSplits[#sortedSplits+1] = i
	end
	table.sort(sortedSplits)

	pc = 0

	local currentBlock
	local lastBlock

	local function flushBlock()
		if currentBlock then
			-- Flush block
			if lastBlock then
				lastBlock.next = currentBlock
				currentBlock.prev = lastBlock
			else
				context.firstBlock = currentBlock
			end
			lastBlock = currentBlock
			currentBlock = nil
		end
	end

	while pc <= decoded.last do
		if splits[pc] then
			flushBlock()
		end

		local instr = decoded[pc]

		if not currentBlock then
			currentBlock = decompiler.block {
				start = pc,
				length = 0,
				decoded = {},
				parent = context,
			}
		end

		currentBlock.decoded[currentBlock.length] = instr
		currentBlock.length = currentBlock.length + 1

		pc = pc + 1
	end
	flushBlock()
	context.lastBlock = lastBlock
end

end
