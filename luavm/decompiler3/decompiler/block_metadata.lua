--[[
Block metadata: Fills out metadata about blocks, like relations.

For example, the two blocks following a conditional block are children of
the conditional block.
]]

return function(decompiler)

function decompiler.computeBlockMetadata(context)
	-- Pass 1: Compute block relationships
	for block in context:blocks() do
		if block.type == "conditional" then
			local nextBlock = block.next

			decompiler.jumpDeopt.tryDeoptConditional(context, block)

			if nextBlock.type == "alias" then

				local meta = decompiler.id {
					mainBlockRange = {
						nextBlock.next.start,
						nextBlock.alias.target
					}
				}

				local lastInnerBlock
				for testBlock in context:blocks(nextBlock.next) do
					if testBlock.start == nextBlock.alias.target then
						lastInnerBlock = testBlock.prev
						break
					end
				end
				assert(lastInnerBlock)

				local libTarget = lastInnerBlock[lastInnerBlock.type].target

				if libTarget and nextBlock.alias.target ~= libTarget and not (lastInnerBlock.metadata["break"]) then
					meta.subBlockRange = {
						nextBlock.alias.target,
						libTarget
					}
				end

				block.metadata["if"] = meta

				-- if else chain
				--[[local metaBlock = decompiler.block {
					type = "meta",
					metatype = "ifelse",
					start = block.start,
					length = 0,
					decoded = {},
				}

				block.parent:insertBlockBefore(block, metaBlock)

				local nextNextBlock = nextBlock.next

				block:removeFromParent()
				metaBlock:insertBlock(block)

				nextBlock:removeFromParent()
				metaBlock:insertBlock(nextBlock)

				local lastInnerBlock
				for testBlock in context:blocks(nextNextBlock) do
					if testBlock.start == nextBlock.alias.target then
						lastInnerBlock = testBlock.prev
						break
					else
						testBlock:removeFromParent()
						metaBlock:insertBlock(testBlock)
					end
				end]]
			end
		elseif block.type == "loop" then
			-- Insert a "metablock" above the loop start
			local loopTarget = block.loop.target
			local loopBlock
			for testBlock in context:blocksUntil(block) do
				if testBlock.start == loopTarget then
					loopBlock = testBlock
					break
				end
			end

			local prevBlock = block.prev

			local meta = decompiler.id {}

			if prevBlock and prevBlock.type == "conditional" then
				block.metadata["until"] = meta
			elseif block.decoded[0][1] == "tforloop" then
				block.metadata["gfor"] = meta
			elseif block.decoded[block.length-1][1] == "forloop" then
				block.metadata["nfor"] = meta
			else
				block.metadata["while"] = meta
			end

			--[[assert(loopBlock)
			local metaBlock = decompiler.block {
				type = "meta",
				metatype = "loopstart",
				start = loopBlock.start,
				length = 0,
				decoded = {},
			}
			-- If the loop's parent is a conditional block, we are a
			-- repeat until loop!
			context:insertBlockBefore(loopBlock, metaBlock)
			-- link parents and children
			local lastLinkBlock = nil
			for linkBlock in context:blocksUntil(block.next, loopBlock) do
				if not relationships[linkBlock] then
					relationships[linkBlock] = metaBlock
					afterRelationships[linkBlock] = lastLinkBlock
					relationships[#relationships+1] = linkBlock

					lastLinkBlock = linkBlock
				end
			end]]
		elseif block.type == "normal" then
			--[[local instr = block.decoded[block.length-1]
			if instr and instr[1] == "loadbool" and instr.skipNext then
				relationships[block.next] = block
				relationships[#relationships+1] = block.next
			end]]
		end

		decompiler.computeRegisterDependenciesForBlock(block)
	end

	for block in context:blocks() do
		context:deduceBlockScope(block)
	end
end

function decompiler.computeRegisterDependenciesForBlock(block)
	local written = {}
	local writtenList = {}
	local read = {}
	local readList = {}

	local function onRead(reg)
		if not written[reg] and not read[reg] then
			read[reg] = true
			readList[#readList+1] = reg
		end
	end

	local function onWrite(reg)
		if not written[reg] then
			written[reg] = true
			writtenList[#writtenList+1] = reg
		end
	end

	for i=0, block.length-1 do
		local instr = block.decoded[i]
		if instr then
			local regDetails = decompiler.instr.getRegisterDetails(instr)

			for reg in pairs(regDetails.read) do
				onRead(reg)
			end

			for reg in pairs(regDetails.write) do
				onWrite(reg)
			end
		end
	end

	if block.type == "exit" then
		-- We can't actually export anything from an exit block...
		-- writtenList = {}
	end

	block.metadata.regs = {
		importSet = read,
		imports = readList,
		exportSet = written,
		exports = writtenList
	}
end

function decompiler.deduceBlockScope(context, block)
	-- Find out which exported registers can be block local variables
	local blockLocalRejections = {}
	local blockRegData = block.metadata.regs

	-- Simple case: The register is both imported and exported
	for reg in pairs(blockRegData.exportSet) do
		if blockRegData.importSet[reg] then
			blockLocalRejections[reg] = "register is imported from another block"
		end
	end

	-- Complex case: The register is imported in pending control flow
	local visited = {[block] = true} -- TODO: visited might have to be per root?
	local followed = {[block] = true}
	local ignoreStack = {}
	local ignore = {}
	local pendingIgnores = {}

	local function addIgnore(reg)
		ignore[reg] = true
	end

	local function pushIgnore()
		ignoreStack[#ignoreStack+1] = ignore
		ignore = {}
	end

	local function popIgnore()
		ignore = ignoreStack[#ignoreStack]
		ignoreStack[#ignoreStack] = nil
	end

	local function isIgnored(reg, i)
		local ig
		if not i then
			ig = ignore
			i = #ignoreStack+1
		else
			ig = ignoreStack[i]
		end

		if i <= 0 then return false end
		if ig[reg] then
			return true
		end

		return isIgnored(reg, i-1)
	end

	local lbi = context:logicalBlockIter(block)
	for hasBlock, block, root in lbi:iter() do
		if hasBlock then
			if block == root then
				print("start root "..root.start)
			end
			print("do "..block.start.." root "..root.start)
		else
			print("exit root "..root.start)
		end

		if hasBlock and block == root then
			pushIgnore()
			ignore = pendingIgnores[block.start] or ignore
		end

		if hasBlock and not visited[block] then
			-- visited[block] = true

			local follow = false
			local pendingIgnore = {}
			for reg in pairs(blockRegData.exportSet) do
				if not blockLocalRejections[reg] and not isIgnored(reg) then
					if block.metadata.regs.importSet[reg] then
						blockLocalRejections[reg] = "register imported in block @ "..block.start
					else
						if not block.metadata.regs.exportSet[reg] then
							-- follow block if possible
							follow = true
						else
							-- ignore register from root
							print("Ignoring "..reg.." in root @ "..block.start)
							pendingIgnore[reg] = true
						end
					end
				end
			end

			if follow and not followed[block] then
				print("follow "..block.start)

				pendingIgnores[block.start] = pendingIgnore

				lbi:addRoot(block)
				followed[block] = true
			end
		elseif block == nil then
			popIgnore()
		end
	end

	print("BLR for "..block.start..":")
	print(serpent.block(blockLocalRejections))

	local blrList = {set={}}
	for reg in pairs(blockRegData.exportSet) do
		if not blockLocalRejections[reg] then
			blrList[#blrList+1] = reg
			blrList.set[reg] = true
		end
	end
	print("BLROK: ", serpent.line(blrList))

	block.metadata.locals = blrList
end

end
