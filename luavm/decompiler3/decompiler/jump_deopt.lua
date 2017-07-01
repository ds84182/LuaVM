--[[
Jump Deoptimizer: Attempts to find the true value of tricky jumps.

Notable example:

while true do
	if j > 3 then
		print("Q!")
	end
end

Compiles into (not real Lua bytecode):

loop:
branch j > 3, [onFalse, onTrue]
onFalse: goto exit
onTrue:  print("Q!")
	     <fallthrough to exit>
exit:
goto loop

Which gets optimized into:

loop:
branch j > 3, [onFalse, onTrue]
onFalse: goto loop
onTrue:  print("Q!")
	     <fallthrough to exit>
exit:
goto loop

This is because Lua notices a jump to another jump.
When the bytecode compiler notices this, it removes the intermediate jump.

The jump deoptimizer handles this by infering what the original jump was,
based on knowledge known about the construct used.

The "onFalse" block of conditional expression _usually_ jumps to where the
"onTrue" block falls through, for example.
]]

return function(decompiler)

decompiler.jumpDeopt = {}
function decompiler.jumpDeopt.tryDeoptConditional(context, conditional)
	-- blockIndex points to conditional block
	-- usually the next block is an alias block
	-- but in the event its a loop block, we need to do jump deopt to fix it
	local blockA = conditional.next
	local blockB = blockA.next
	if blockA.type == "loop" and blockB then
		-- deoptimize, find the last loop block with this jump target
		local lastLoopBlock
		for testBlock in context:reverseBlocksUntil(blockB) do
			if testBlock.type == "loop" and testBlock.loop.target == blockA.loop.target then
				lastLoopBlock = testBlock
				break
			end
		end

		if lastLoopBlock then
			assert(blockA.length == 1)

			if lastLoopBlock.length > 1 then
				-- Split the last loop block
				local jump = lastLoopBlock.decoded[lastLoopBlock.length-1]

				local singleJumpBlock = decompiler.block {
					start = lastLoopBlock.start+lastLoopBlock.length-1,
					length = 1,
					decoded = {jump}
				}

				context:insertBlockAfter(lastLoopBlock, singleJumpBlock)

				lastLoopBlock.decoded[lastLoopBlock.length-1] = nil
				lastLoopBlock.length = lastLoopBlock.length-1
				context:clearBlockIdentification(lastLoopBlock)

				context:identifyBlock(lastLoopBlock)
				context:identifyBlock(singleJumpBlock)

				lastLoopBlock = singleJumpBlock
			end

			-- mutate the jump
			blockA.decoded[0] = {"jump", to = lastLoopBlock.start}
			context:clearBlockIdentification(blockA)
			context:identifyBlock(blockA)
		end
	end
end

end
