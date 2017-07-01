--[[
Block identifier: Identifies what blocks are based on their structure.

Block types:

Alias: A block that only jumps to another block after itself.
Loop: A block that exits to a previous block or itself.
Simple: A block that falls through to the next block.
Conditional: A block that executes one block or the other based on the
	results from an expression.
Normal: A block that jumps forward to another block, but has other
	instructions. (DEPRECATED)
Exit: A block that exits the function through a return.
Complex: A block that always jumps forward to another block.

Identifying blocks:

Alias:
	Only one instruction, a jump.
	The jump's target is after the current block.
Loop:
	The final instruction is a jump.
	The jump's target is before or the current block.
Simple:
	The final instruction is NOT a block terminator.
Conditional:
	The final instruction is a conditional instruction.
Normal:
	Everything that doesn't fit in with the rest.
]]

return function(decompiler)

local function getJumpTarget(instr, pc)
	if instr then
		if instr[1] == "jump" then
			return instr.to
		elseif instr[1] == "forprep" or instr[1] == "forloop" then
			return instr.target
		elseif instr[1] == "loadbool" and instr.skipNext then
			return pc+2
		end
	end
end

local function handleBlockAlias(block)
	if block.length ~= 1 then return false end
	local instr = block.decoded[0]
	if not instr or instr[1] ~= "jump" then return false end
	if instr.to <= block.start then return false end

	block.type = "alias"
	block.alias = {
		target = instr.to
	}

	return true
end

local function handleBlockLoop(block)
	local instr = block.decoded[block.length-1]
	local jt = getJumpTarget(instr, block.start+block.length-1)
	if not jt then return false end
	if jt > block.start then return false end

	block.type = "loop"
	block.loop = {
		target = jt
	}

	return true
end

local function isBlockSimple(block)
	local instr = block.decoded[block.length-1]
	if decompiler.isTerminator(instr) then
		-- last instruction is a block terminator
		return false
	end
	return true
end

local function isBlockConditional(block)
	local instr = block.decoded[block.length-1]
	if not instr or instr[1] ~= "condop" then return false end
	return true
end

local function handleBlockExit(block)
	local instr = block.decoded[block.length-1]
	if not instr or instr[1] ~= "return" then return false end

	block.type = "exit"
	block.exit = {}

	return true
end

local function handleBlockComplex(block)
	local instr = block.decoded[block.length-1]
	local jt = getJumpTarget(instr, block.start+block.length-1)
	if not jt then return false end
	if jt <= block.start then return false end

	block.type = "complex"
	block.complex = {
		target = jt
	}

	return true
end

function decompiler.clearBlockIdentification(context, block)
	if block.type then
		block[block.type] = nil
		block.type = nil
	end
end

function decompiler.identifyBlock(context, block)
	if not block.type then
		if handleBlockAlias(block) then
		elseif handleBlockLoop(block) then
		elseif handleBlockExit(block) then
		elseif handleBlockComplex(block) then
		elseif isBlockSimple(block) then
			block.type = "simple"
			block.simple = {}
		elseif isBlockConditional(block) then
			block.type = "conditional"
			block.conditional = {}
		else
			block.type = "normal"
			block.normal = {}
		end
	end
end

-- TODO: Should this be merged with identifyBlock?
function decompiler.identifyBlockPost(context, block)
	-- determine if this normal block is a break block
	-- a break block is a block that jumps to the block AFTER a loop block
	if block.type == "complex" then
		local instr = block.decoded[block.length-1]
		if instr and instr[1] == "jump" then
			-- Find block it exits to
			local exitBlock
			for testBlock in context:blocks(block) do
				if testBlock.start == instr.to then
					exitBlock = testBlock
				end
			end
			if exitBlock.prev.type == "loop" then
				-- If the block before the exit block is a loop...
				block.metadata["break"] = true
			end
		end
	end
end

function decompiler.identifyBlocks(context)
	for block in context:blocks() do
		context:identifyBlock(block)
	end

	context:identifyBlocksPost()
end

function decompiler.identifyBlocksPost(context)
	for block in context:blocks() do
		context:identifyBlockPost(block)
	end
end

end
