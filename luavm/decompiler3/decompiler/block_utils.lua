return function(decompiler)
	function decompiler.block(b)
		setmetatable(b, {__index = decompiler})

		if not b.decoded then
			b.decoded = {}
		end

		if not b.metadata then
			b.metadata = {}
		end

		return b
	end

	function decompiler.blocks(context, startBlock)
		return function(_, block)
			if not block then
				return startBlock or context.firstBlock
			end
			return block.next
		end
	end

	function decompiler.blocksUntil(context, stopBlock, startBlock)
		local iter = decompiler.blocks(context, startBlock)
		return function(_, block)
			local nextBlock = iter(_, block)
			if nextBlock == stopBlock then return nil end
			return nextBlock
		end
	end

	function decompiler.reverseBlocks(context, startBlock)
		return function(_, block)
			if not block then
				return startBlock or context.lastBlock
			end
			return block.prev
		end
	end

	function decompiler.reverseBlocksUntil(context, stopBlock, startBlock)
		local iter = decompiler.reverseBlocks(context, startBlock)
		return function(_, block)
			local nextBlock = iter(_, block)
			if nextBlock == stopBlock then return nil end
			return nextBlock
		end
	end

	function decompiler.blocksRecursive(context, startBlock)
		return function(_, block)
			if not block then
				return startBlock or context.firstBlock
			end

			local n = block.firstBlock
			if not n then
				n = block.next
				if not n then
					n = block.parent.next
					if n == context then
						n = nil
					end
				end
			end

			return n
		end
	end

	function decompiler.insertBlock(context, block)
		decompiler.insertBlockAfter(context, context.lastBlock, block)
	end

	function decompiler.insertBlockAfter(context, block, nextBlock)
		print("Insert", nextBlock, "after", block, "in", context)

		local oldNext

		if block then
			oldNext = block.next
			block.next = nextBlock
		else
			oldNext = context.firstBlock
			context.firstBlock = nextBlock
		end

		nextBlock.prev = block

		nextBlock.next = oldNext

		if oldNext then
			oldNext.prev = nextBlock
		else
			context.lastBlock = nextBlock
		end

		nextBlock.parent = context
	end

	function decompiler.insertBlockBefore(context, block, prevBlock)
		local oldPrev = block.prev

		if not oldPrev then
			context.firstBlock = prevBlock
		else
			oldPrev.next = prevBlock
		end

		prevBlock.prev = oldPrev

		prevBlock.next = block

		if not block then
			context.lastBlock = prevBlock
		else
			block.prev = prevBlock
		end

		prevBlock.parent = context
	end

	function decompiler.removeBlock(context, block)
		local prev = block.prev
		local next = block.next

		if prev then
			prev.next = next
		else
			context.firstBlock = next
		end

		if next then
			next.prev = prev
		else
			context.lastBlock = prev
		end

		block.next = nil
		block.prev = nil
		block.parent = nil
	end

	function decompiler.removeFromParent(context)
		context.parent:removeBlock(context)
	end

	local lbi = {}
	lbi.__index = lbi

	function lbi:addPending(block, root)
		assert(root)
		self.pending[#self.pending+1] = {block, root}
	end

	function lbi:addRoot(root)
		local typ = root.type

		self:addPending(root, root)

		if typ == "exit" then
			-- Nothing to do.
		elseif typ == "alias" or typ == "complex" then
			local target = root[typ].target
			for block in self.context:blocks(root) do
				if block.start == target then
					self:addPending(block, root)
					break
				end
			end
		elseif typ == "loop" then
			for block in self.context:reverseBlocks(root.prev) do
				if block.start == root.loop.target then
					self:addPending(block, root)
					break
				end
			end

			if root.metadata.nfor or root.metadata.gfor then
				self:addPending(root.next, root)
			end
		elseif typ == "conditional" then
			self:addPending(root.next, root)
			self:addPending(root.next.next, root)
		elseif typ == "simple" or typ == "normal" then
			self:addPending(root.next, root)
		end

		self:addPending(nil, root)
	end

	function lbi:iter()
		return function()
			local p = table.remove(self.pending, 1)
			if p then
				return p[1] ~= nil, p[1], p[2]
			end
		end
	end

	function decompiler.logicalBlockIter(context, block)
		local o = setmetatable({
			context = context,
			pending = {}
		}, lbi)
		o:addRoot(block)
		return o
	end

	local noComments = {comment = false}

	function decompiler.dumpBlock(context, block)
		local parts = {}

		parts[#parts+1] = block.type

		if block.type == "meta" then
			parts[#parts+1] = "("..block.metatype..")"
		end

		parts[#parts+1] = " @ "..block.start.." # "..block.length

		if block.type == "alias" then
			parts[#parts+1] = " -> "..block.alias.target
		elseif block.type == "complex" then
			parts[#parts+1] = " -> "..block.complex.target
		elseif block.type == "loop" then
			parts[#parts+1] = " -> "..block.loop.target
		elseif block.type == "normal" then
			parts[#parts+1] = " -> "..serpent.line(block.decoded[block.length-1], noComments)
		end

		if next(block.metadata) then
			parts[#parts+1] = " ["
			local first = true
			for type, metadata in pairs(block.metadata) do
				if first then
					first = false
				else
					parts[#parts+1] = "; "
				end
				parts[#parts+1] = type..": "..serpent.line(metadata, noComments)
			end
			parts[#parts+1] = "]"
		end

		return table.concat(parts)
	end
end
