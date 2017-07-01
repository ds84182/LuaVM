local colors = require "ansicolors"

local decompiler = {}

local validExpressions = {
	"move", "loadk", "loadbool", "loadnil",
	"getupval", "getglobal", "gettable", "newtable",
	"self", "binop", "unop", "condop", "concat", "testset",
	"call", "closure", "vararg", "return", "settable",
	"forprep", "tforloop"
}
for i=1, #validExpressions do
	validExpressions[validExpressions[i]] = true
end

local invertedConditionals = {
	["<"] = ">=",
	["<="] = ">",
	["=="] = "~=",
}

local flipConditional = {
	["<"] = "<=",
	["<="] = "<",
	["=="] = "=="
}

local blockSplits = {
	["jump"] = true,
	["condop"] = true,
	["testset"] = true,
	["loadbool"] = true,
	["return"] = true,
	["forprep"] = true,
	["forloop"] = true,
	["close"] = true,
}

decompiler.terminator = blockSplits

function decompiler.id(x)
	x.id = tostring(x):sub(10)
	return x
end

require "luavm.decompiler3.decompiler.block_utils" (decompiler)
require "luavm.decompiler3.decompiler.block_splitter" (decompiler)
require "luavm.decompiler3.decompiler.block_identifier" (decompiler)
require "luavm.decompiler3.decompiler.block_metadata" (decompiler)
require "luavm.decompiler3.decompiler.jump_deopt" (decompiler)
require "luavm.decompiler3.decompiler.instr_utils" (decompiler)

--[[

A couple of nits about this code:

Some statements are treated as expressions.
	This is a limitation of the expression engine.
	The expression engine was designed to accomodate function calls.
	I actually don't know what to rename "expressions" to...
	Anyways, these things are expressions in non-archaic languages.

]]

local contextMT = {
	__index = decompiler
}

local _OPTS = {}

function decompiler.decompile(decoded, chunk, opts)
	opts = opts or _OPTS
	local level = opts.level or 1

	if true then
		local context = {
			decoded = decoded,
			chunk = chunk,
			opts = opts,
			level = level
		}
		setmetatable(context, contextMT)

		decompiler.splitBlocks(context)
		decompiler.identifyBlocks(context)
		decompiler.computeBlockMetadata(context)

		local function dumpBlock(block, level)
			level = level or 0
			local indent = string.rep(" ", level)
			print(indent..context:dumpBlock(block))
			if block.firstBlock then
				for block in block:blocks() do
					dumpBlock(block, level+1)
				end
			end
		end

		for block in context:blocks() do
			dumpBlock(block)
		end

	end

	if true then
		-- Test block spliting:
		local jumpTargets = {}
		local splits = {}
		local pc = 0
		while pc <= decoded.last do
			local instr = decoded[pc]
			if instr and blockSplits[instr[1]] then
				splits[pc+1] = true

				if instr[1] == "jump" then
					jumpTargets[instr.to] = jumpTargets[instr.to] or {}
					table.insert(jumpTargets[instr.to], pc)
					splits[instr.to] = true
				elseif instr[1] == "condop" or (instr[1] == "loadbool" and instr.skipNext) then
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
		print("Splits")
		print(serpent.block(sortedSplits))
		pc = 0
		while pc <= decoded.last do
			local instr = decoded[pc]
			if jumpTargets[pc] then
				print("*", "Jump from "..table.concat(jumpTargets[pc], "; "))
			end
			if splits[pc] then
				print("*", "-------------")
			end
			--if splits[pc] and not blockSplits[instr[1]] then
			--	print()
			--end
			print(pc, serpent.line(instr))
			--if splits[pc] and blockSplits[instr[1]] then
			--	print()
			--end
			pc = pc+1
		end

		--error()
	end

	--[[
		Several things to remember:

		We are a decompiler, not an optimizer!
		Our current goal is to recover control flow and output code that
		compiles into the same instructions.

		`local x = 5; print(x, 6)` is different from `print(5, 6)`!
		Instructions that write to the slots in a call statement
		are ACTUALLY BETWEEN THE PARENTHESIS!

		We need good lookahead logic!
	]]

	local function formatLocal(reg, lvl)
		return "L_"..(lvl or level).."_"..reg
	end

	local function formatUpvalue(index)
		local upvalLevel = opts.upvalues

		while upvalLevel do
			local upval = upvalLevel.cur[index+1]
			if upval[1] == "move" then
				return formatLocal(upval.src, upvalLevel.level)
			elseif upval[1] == "getupval" then
				index = upval.upvalue
				upvalLevel = upvalLevel.prev
			end
		end

		return "UPVALUE_"..index
	end

	local function isreg(reg)
		return reg < 256
	end

	local function testdest(instr, reg)
		if instr.dest == reg then
			return true
		elseif instr[1] == "call" or instr[1] == "tailcall" then
			if reg >= instr.base then
				if instr.nret < 0 then
					return true -- vararg
				elseif reg-instr.base+1 <= instr.nret then
					return true
				end
			end
			return false
		elseif instr[1] == "self" then
			return reg == instr.base or reg == instr.base+1
		elseif instr[1] == "loadnil" then
			return reg >= instr.from and reg <= instr.to
		else
			return false
		end
	end

	local function testsrc(instr, reg)
		if instr[1] == "gettable" or instr[1] == "settable" then
			return instr.table == reg or instr.index == reg or instr.src == reg
		elseif instr[1] == "call" or instr[1] == "tailcall" then
			if reg >= instr.base then
				if instr.narg < 0 then
					return true -- vararg
				elseif reg-instr.base <= instr.narg then
					return true
				end
			end
			return false
		elseif instr[1] == "return" then
			if reg >= instr.base then
				if instr.count < 0 then
					return true -- vararg
				elseif reg-instr.base+1 <= instr.count then
					return true
				end
			end
			return false
		end

		return instr.src == reg or instr.lhs == reg or instr.rhs == reg
	end

	local function calculateDestCount(instr)
		if instr.dest then
			return 1
		elseif instr[1] == "call" or instr[1] == "tailcall" then
			return instr.nret
		elseif instr[1] == "self" then
			return 2
		elseif instr[1] == "return" or instr[1] == "settable" or instr[1] == "forprep"  or instr[1] == "tforloop" then
			return 0
		else
			error("Unhandled dest count for "..instr[1])
		end
	end

	local function instructionBase(instr)
		if instr.dest then
			return instr.dest
		elseif instr[1] == "call" or instr[1] == "tailcall" or instr[1] == "self" then
			return instr.base
		elseif instr[1] == "tforloop" then
			return instr.base + 3
		else
			error("Unhandled base for "..instr[1])
		end
	end

	local function doesSetSomething(instr)
		local s, e = pcall(calculateDestCount, instr)
		if not s then e = 0 end
		return e > 0
	end

	local tags = {}

	local function tag(pc, t)
		local tagholder = tags[pc]
		if not tagholder then
			tagholder = {}
			tags[pc] = tagholder
		end
		tagholder[#tagholder+1] = t
	end

	local function tagrange(s, e, t)
		for i=s, e do
			tag(i, t)
		end
	end

	local function istagged(pc, type)
		local tagholder = tags[pc]
		if not tagholder then
			return false
		end
		for i=1, #tagholder do
			if tagholder[i].type == type then
				return true
			end
		end
		return false
	end

	local function findtag(pc, type)
		local tagholder = tags[pc]
		if not tagholder then
			return nil
		end
		for i=1, #tagholder do
			local tag = tagholder[i]
			if tag.type == type then
				return tag
			end
		end
		return nil
	end

	local expressionRoots = {}

	local function exproot(pc)
		expressionRoots[pc] = true
	end

	local blocks = {}

	local function declblock(s, e, extra)
		blocks[#blocks+1] = {
			s = s, e = e,
			extra = extra
		}
	end

	local function alwaysTrue() return true end
	local function loopFilter(b)
		local typ = b.extra[1]
		return typ == "while" or typ == "for"
	end

	local function findblock(pc, filter)
		filter = filter or alwaysTrue
		local range, block = math.huge
		for i=1, #blocks do
			local b = blocks[i]
			if b.s <= pc and b.e >= pc then
				local r = b.e-b.s
				if r < range and filter(b) then
					range = r
					block = b
				end
			end
		end
		return block
	end

	declblock(0, decoded.last, {"chunk"})

	local regusage = {}
	local maxreg = -1

	local function getregusage(reg)
		regusage[reg] = regusage[reg] or {
			read = {},
			nread = 0,
			write = {},
			nwrite = 0
		}
		maxreg = math.max(maxreg, reg)
		return regusage[reg]
	end

	local function regread(reg, pc)
		if reg >= 256 then return end -- Ignore constants
		local usage = getregusage(reg)
		usage.read[pc] = true
		usage.nread = usage.nread+1
	end

	local function regwrite(reg, pc)
		if reg >= 256 then return end -- Ignore constants
		local usage = getregusage(reg)
		usage.write[pc] = true
		usage.nwrite = usage.nwrite+1
	end

	local function regrangeread(s, e, pc)
		for i=s, e do regread(i, pc) end
	end

	local function regrangewrite(s, e, pc)
		for i=s, e do regwrite(i, pc) end
	end

	-- Barriers are used to prevent bad cross-inlines
	-- An example of where a barrier would be used:
	-- local i = 0
	-- while i < 10 do end
	-- Without a barrier, the conditional expression root inside the
	-- while statement can read the expression 0 < 10, which is invalid
	-- Placing a barrier at the while loop's top loop point
	-- (in the conditional expression scope)
	-- allows us to write a great looking expression collector
	-- without having to litter the code with checks
	local barriers = {}
	local barrierCache

	-- Adds a barrier between spc and epc.
	local function barrier(spc, epc, tag)
		barriers[#barriers+1] = {s = spc, e = epc, tag = tag}
		barrierCache = nil
	end

	local function computeBarrier(pc)
		if not barrierCache then
			barrierCache = {}
		end
		local cached = barrierCache[pc]
		if cached then
			return cached
		end
		local s, e = -math.huge, math.huge
		for i=1, #barriers do
			local b = barriers[i]
			if b.s <= pc and b.e >= pc then
				s = math.max(b.s, s)
				e = math.min(b.e, e)
			end
		end
		cached = {s = s, e = e}
		barrierCache[pc] = cached
		return cached
	end

	barrier(0, decoded.last, "chunk")

	local function canInlineInner(reg, pc, targetpc)
		-- pc needs to be the instruction that writes to the reg
		-- We cannot inline across blocks
			-- Inlining in conditional expression is OK (if barrier is weak)
		-- We cannot inline things that are used multiple times
			-- Loops are taken into account with this.
			-- If we hit the end of a loop (that contains our pc), we jump to the top of the loop and continue analysis

		-- TODO: Test to see if we go across impure instructions (anything that <can> invoke another function)
			-- Moving an impure instruction across other impure instructions can be disasterous
			-- This would also be solved by keeping a strict ordering on the instructions

		local instrBlock = findblock(pc)
		local targetBlock = findblock(targetpc)

		if instrBlock ~= targetBlock then
			return false, "cannot inline across blocks"
		end

		-- If the target instruction overwrites reg, don't scan the entire
			-- block.
		local targetOverwrites = testdest(decoded[targetpc], reg)

		-- Ok, in the same block...
		-- Walk from pc to targetpc then to end of block
		local curpc = pc+1
		local lastpc

		if targetOverwrites then
			lastpc = targetpc
		else
			lastpc = instrBlock.e
		end

		while curpc < lastpc do
			local instr = decoded[curpc]

			if instr and curpc ~= targetpc then
				-- TODO: Handle instructions that return multiple values
				-- better. We need to test the entire list of dests from
				-- our target instruction, not one specific dest.

				-- We also need to be able to test register ranges in
				-- testdest and testsrc, along with varargs.

				if testdest(instr, reg) then
					if curpc < pc then
						error("not inlining right dest!")
					elseif curpc < targetpc then
						return false, "set in a later expression"
					else
						break -- hit a set! the variable life is over!
					end
				end

				-- TODO: Handle loop blocks properly (by checking from start of block also (if the variable is used without being set again, we are using this across loops))

				if testsrc(instr, reg) then
					return false, "used as source in another expression (at "..curpc..")"
				end

				if instr[1] == "jump" then
					if instr.to > curpc then
						-- Forward jump...
						--curpc = instr.to-1
						print(curpc)
					end
				end
			end

			curpc = curpc+1
		end

		return true
	end

	local function canInline(reg, pc, targetpc)
		local s, e = canInlineInner(reg, pc, targetpc)
		if not s then
			print(colors("%{bright red}Failed to inline "..reg.." (set at pc "..pc..", to target pc "..targetpc.."): "..e))
		end
		return s
	end

	local function identifyStructures()
		print(colors "%{bright red}Identifying structures...")

		local pc = 0

		print(colors "%{bright green}Pass 1:")

		--[[
		Instruction identification pass 1:

		Find and label call, tailcall, and returns.
		Cluster conditional groups.
		Label while, nfor, and gfor loops.
		Examine register usage.
		]]

		-- TODO: Find nfor and gfor loops

		while pc <= decoded.last do
			local instr = decoded[pc]
			if instr then
				local typ = instr[1]

				-- Update register usage information
				-- TODO: Do we need to track this information?
					-- Inliner doesn't use it at all.
				if typ == "loadnil" then
					regrangeread(instr.from, instr.to, pc)
				elseif typ == "concat" then
					regwrite(instr.dest, pc)
					regrangeread(instr.from, instr.to, pc)
				elseif typ == "test" then
					regread(instr.target, pc)
				elseif typ == "testset" then
					regwrite(instr.dest, pc)
					regread(instr.target, pc)
				elseif typ == "call" or typ == "tailcall" then
					regread(instr.base, pc)
					-- TODO: Vararg support
					regrangeread(instr.base+1, instr.base+instr.narg, pc)
					if typ == "call" then
						-- TODO: Vararg support
						regrangewrite(instr.base, instr.base+instr.nret, pc)
					end
				elseif typ == "return" then
					-- TODO: Vararg support
					regrangeread(instr.base, instr.base+instr.count, pc)

					-- TODO: "forloop", "forprep", "tforloop", "setlist"
					-- "close", "vararg"
				else
					if instr.dest then
						regwrite(instr.dest, pc)
					end

					if instr.src then
						regread(instr.src, pc)
					end

					if instr.lhs then
						regread(instr.lhs, pc)
					end

					if instr.rhs then
						regread(instr.rhs, pc)
					end
				end

				-- Identify and tag structures
				if typ == "call" or typ == "tailcall" then
					-- Find where the function is loaded for the call before the call
					local funcloadpc = pc-1

					while funcloadpc >= 0 do
						local fl = decoded[funcloadpc]
						if testdest(fl, instr.base) then
							-- This is where the function for this call is loaded at
							break
						else
							funcloadpc = funcloadpc-1
						end
					end

					if funcloadpc < 0 then
						error("Could not find function load")
					end

					local selfCall = decoded[funcloadpc][1] == "self"

					tag(funcloadpc, {
						type = "call_function",
						expression = true,
						target = pc
					})

					barrier(funcloadpc+1, pc-1, "funcargs")

					-- Then find all arguments by looking for dests between funcloadpc and pc
					assert(instr.narg >= 0, "Varargs not supported inside function calls")
					local latestarg = funcloadpc
					local argreg = instr.base+1
					for i=1, instr.narg do
						local argpc = pc-1
						while argpc > latestarg do
							local arg = decoded[argpc]
							if testdest(arg, argreg) then
								print("TD "..argpc)
								break
							else
								argpc = argpc-1
							end
						end

						if argpc <= latestarg then
							if not (selfCall and argreg == instr.base+1) then
								error("Could not find arg "..(instr.base+1).." "..pc.." "..funcloadpc.." "..tostring(selfCall).." "..argreg.." "..latestarg)
							end
						else
							tag(argpc, {
								type = "function_argument",
								expression = true,
								target = pc
							})

							latestarg = argpc
						end
						argreg = argreg+1
					end
				elseif typ == "return" then
					-- Find all arguments by looking for dests between 0 and pc
					assert(instr.count >= 0, "Varargs not supported for returns")
				elseif typ == "condop" then
					if not istagged(pc, "conditional_block") then
						print(colors "%{bright blue}Parsing conditionals")

						local conditionals = {}
						local firstCond, lastCond = math.huge, -math.huge
						local blockStart, blockEnd = math.huge, -math.huge
						local curpc = pc

						-- we can then identify the conditional for a while loop by merging conditional_constructs starting at the beginning of the while loop
						-- merging (13 -> 17; 16 -> 20; 19 -> 33) into (conditionals: 13 -> 19; start: 20; end: 33)
						-- or (13 -> 30; 16 -> 30) into (conditionals: 13 -> 16; start: 17; end: 30)
						-- or (18 -> 21; 20 -> 24) into (conditionals: 18 -> 20; start: 21; end: 24)
						-- or (13 -> 17; 16 -> 23; 19 -> 23; 22 -> 36) into (conditionals: 13 -> 22; start: 24; end: 36)

						-- Conditionals range from min(a)-1 to max(a) (where a is from `a -> b`)
						-- Start is max(a)+1
						-- End is max(b)
						-- Merging is done on intersecting ranges
						-- b needs to be greater than "current max range"

						local function deoptJump(jumppc, target)
							-- Lua optimized our jump target...
							-- Muhwhah??
							-- Deopt our jump target!
							for i=jumppc+1, decoded.last do
								local ins = decoded[i]
								if ins then
									if ins[1] == "jump" and ins.to == target then
										print("Deopt jump target", i)
										return i
									end
								end
							end
							print("Jump deopt failed", target, curpc, jumppc)
							return target
						end

						local conds = {}
						local jumpTargets = {}
						local baseReg = math.huge

						local function handleCondOp()
							local next = decoded[curpc+1]
							assert(next[1] == "jump")
							local target = next.to

							local a = curpc
							local b = target

							if b < pc then
								b = deoptJump(curpc+1, b)
							end

							if b < blockEnd then
								return false
							end

							print(a.."; "..b)

							firstCond = math.min(firstCond, a)
							lastCond = math.max(lastCond, a+1)
							blockEnd = math.max(blockEnd, b)
							return true
						end

						while (blockEnd >= 0 and curpc < blockEnd) or (blockEnd < 0 and curpc <= decoded.last) do
							local cur = decoded[curpc]
							if cur and cur[1] == "condop" then
								handleCondOp()
								curpc = curpc+2
							else
								curpc = curpc+1
							end
						end

						-- Second pass: add all condops from firstCond to lastCond, also calculate base register
						curpc = firstCond
						while curpc <= lastCond do
							local cur = decoded[curpc]
							if cur and cur[1] == "condop" then
								local next = decoded[curpc+1]
								assert(next[1] == "jump")
								local target = next.to

								local a = curpc

								if target < pc then
									-- Lua optimized our jump target...
									-- Muhwhah??
									-- Deopt our jump target!
									target = deoptJump(curpc+1, target)
									print("Deopt jump target", target)
								end

								conds[#conds+1] = curpc
								jumpTargets[curpc] = target
								baseReg = math.min(baseReg, cur.lhs or math.huge, cur.rhs or math.huge, cur.target or math.huge)

								curpc = curpc+2
							else
								curpc = curpc+1
							end
						end

						blockStart = lastCond+1

						for i=1, #conds do
							if jumpTargets[conds[i]] < curpc then
								--error "THIS IF STATEMENT IS AT THE END OF DAYS"
								-- If the jump target jumps before the first cond, this is an if statement at the end of a loop
								-- This is an optimization done by Lua when a jump jumps to another jump
								-- So we can safely ignore it :)
							end
						end

						local conditionalExpr = false

						-- Determine if our base register from this is used
						-- First we check for EXACTLY ONE DEST in the block
						-- Then we check for usages after the block
						local scanpc = lastCond+1
						local inBlockSets = 0
						while scanpc <= blockEnd do
							local instr = decoded[scanpc]
							if instr then
								if testdest(instr, baseReg) then
									inBlockSets = inBlockSets+1
									if inBlockSets > 1 then
										break
									end
								elseif doesSetSomething(instr) then
									inBlockSets = 0
									break
								end
							end
							scanpc = scanpc+1
						end

						if inBlockSets == 1 then
							scanpc = blockEnd
							while scanpc <= decoded.last do
								local instr = decoded[scanpc]
								if instr then
									if testdest(instr, baseReg) then
										-- We've been set!
										print("We've been set!", scanpc)
										break
									end

									if testsrc(instr, baseReg) then
										-- We've been got!
										print("CONDITIONAL BASE REGISTER USED!")
										conditionalExpr = true
										break
									end
								end
								scanpc = scanpc+1
							end
						else
							print("Set too many times in block... Cannot work")
						end

						local invertLast = false

						if blockEnd-blockStart == 1 then
							-- Only two instructions? Check for loadbool!
							-- Loadbool is used at the end of a conditional expression when converting into a boolean
							-- In this case, we tag the loadbools to target the last conditional expression
							local a = decoded[blockStart]
							local b = decoded[blockEnd]
							if a and b and a[1] == "loadbool" and b[1] == "loadbool" then
								tag(blockEnd, {
									type = "conditional_target",
									pc = lastCond-1
								})

								tag(lastCond-1, {
									type = "conditional_invert"
								})

								assert(a.value ~= b.value)
								assert(not a.value)
								assert(b.value)

								invertLast = true

								conditionalExpr = true
							end
						end

						if conditionalExpr then
							conds[#conds+1] = blockStart
							blockStart = blockStart+1
						end

						-- After calculating block bounds
							-- tag induvidual conditionals with "and" or "or"

						if #conds > 1 then
							-- Conditional classification
							-- We process conditionals in groups of two
							-- Essentially doing a "fold" operation
							-- See image in Google Photos for illustration
							for i=1, #conds-1 do
								local pc = conds[i]
								local nextPc = conds[i+1]
								local target = jumpTargets[pc]
								local jumpClass
								-- TODO: We need to handle inner-cond jumps properly

								-- If we continue on true, is and
								-- If we continue on false, is or
								if target == blockStart then
									-- Invert is true: continue on false
									-- When it is false, we jump over the
									-- next jump
									-- This is "or", since we jump
									-- somewhere on true
									-- We check if it jumps to the end if it isn't a conditional expression, since there really is no block in the first place.
									jumpClass = "or"
								else
									-- Invert is false: continue on true
									-- When it is true, we jump over the
									-- next jump
									-- This is "and", since we jump
									-- somewhere on false
									jumpClass = "and"
								end

								print(pc, nextPc, target, jumpClass)
								-- tag nextPc with "cc"
								tag(nextPc, {
									type = "conditional_class",
									class = jumpClass,
									-- If we are an "or", we want to invert the lhs of this cc
									invert = jumpClass == "or",
									lhs = pc
								})
							end
						end

						print("cond range: ("..firstCond.." -> "..lastCond.."); block range: ("..blockStart.." -> "..blockEnd.."); base reg "..baseReg)

						local emitBlock = true

						if conditionalExpr then
							emitBlock = false
						end

						-- TODO: Handle a == b and c or d
						-- TODO: Handle x or y or z

						if emitBlock then
							tagrange(firstCond, lastCond, {
								type = "conditional_block",
								s = firstCond,
								e = lastCond,
								blockStart = blockStart,
								blockEnd = blockEnd,
								declaredBlock = false
							})

							tagrange(blockStart, blockEnd, {
								type = "block",
								s = blockStart,
								e = blockEnd
							})
						end
					end

					exproot(pc)
				elseif typ == "jump" then
					-- If we are jumping backwards, we form a while loop!
					if instr.to <= pc then
						print(colors "%{bright blue}Found backwards jump!")

						if istagged(pc, "conditional_block") or istagged(pc, "gfor") then
							print(colors "%{bright red}Or maybe not. Baited.", pc)
						else
							local whiletag = {
								type = "while",
								s = instr.to,
								e = pc
							}
							tagrange(instr.to, pc, whiletag)
							declblock(instr.to, pc, {"while"})
							barrier(instr.to, pc, "whileBlock")

							-- find the first conditional_block tag inside
							-- that has the correct block start and end

							local cur = instr.to
							local found = false
							while cur < pc do
								local curtags = tags[cur]
								if curtags then
									for i=1, #curtags do
										local tag = curtags[i]
										if tag.type == "conditional_block" then
											if tag.blockEnd-1 == pc and tag.s >= instr.to then
												print(colors "%{bright blue}Found conditional block for while loop")
												tag.declaredBlock = true
												whiletag.condBlock = tag

												barrier(instr.to, tag.e, "whileConditional")
												cur = pc
												found = true
												break
											end
										end
									end
								end
								cur = cur+1
							end

							if not found then
								-- If no conditional was found, this is a while true loop
							end
						end
					elseif decoded[instr.to][1] == "tforloop" then
						-- We are forming a generic for loop
						tagrange(pc, instr.to+1, {
							type = "gfor",
							s = pc,
							e = instr.to+1
						})
						declblock(pc+1, instr.to-1, {"gfor"})
						barrier(pc+1, instr.to-1, "gforBlock")
						exproot(instr.to)
					end
				elseif typ == "forprep" then
					tagrange(pc, instr.target, {
						type = "for",
						s = pc,
						e = instr.target
					})
					declblock(pc+1, instr.target, {"for"})
					barrier(pc+1, instr.target, "forBlock")
				end
			end
			pc = pc+1
		end

		print(colors "%{bright green}Pass 2:")
		-- Go through and turn conditional_blocks that aren't loops into if statements
		-- Also turn forwards jumps into breaks
		pc = 0
		while pc <= decoded.last do
			local curtags = tags[pc]
			if curtags then
				for i=1, #curtags do
					local tag = curtags[i]
					if tag.type == "conditional_block" and not tag.declaredBlock then
						print(colors "%{bright blue}Found if statement at", pc)
						-- TODO: Handle else statements
						print(serpent.line(tag))
						declblock(tag.blockStart, tag.blockEnd-1, {"if"})
						-- TODO: Weak barriers
						--barrier(tag.s, tag.e, "ifConditional")
						barrier(tag.blockStart, tag.blockEnd-1, "ifBlock")
						tag.declaredBlock = true
						tag.ifstat = true
					end
				end
			end

			local instr = decoded[pc]
			if instr and instr[1] == "jump" then
				if instr.to > pc then
					local block = findblock(pc, loopFilter)
					if block and instr.to == block.e+1 then
						tag(pc, {type = "break", block = block})
					end
				end
			end

			pc = pc+1
		end

		print(colors "%{bright green}Expression roots:")
		for pc in pairs(expressionRoots) do
			print(pc)
		end

		print(colors "%{bright green}Blocks:")
		for i=1, #blocks do
			local block = blocks[i]
			print(block.s.." -> "..block.e, serpent.line(block.extra))
		end

		print(colors "%{bright green}Register usage counts:")
		for i=0, maxreg do
			local r = regusage[i]
			if r then
				print("r"..i.." "..r.nread.." "..r.nwrite)
			end
		end

		print(colors "%{bright green}Barriers: ")
		for i=1, #barriers do
			local b = barriers[i]
			print(b.s.." "..b.e..": "..b.tag)
		end
	end

	-- TODO: A pass to annotate per block register ranges

	local decodedExpressions = {}

	local function expressionReconstruction()
		print()
		print(colors "%{bright red}Expression reconstruction:")

		-- Where do we reconstruct expressions?
			-- Expression roots
			-- Conditional expressions
			-- Any hanging expression operations are turned into variables (and passed to statementReconstruction)

		-- Why do we reconstruct expressions?
			-- Statement reconstruction just refers to expression roots, not expressions themselves.

		local visitExpression

		local function findExpressionWithDest(pc, dest, minpc)
			if not isreg(dest) then
				return {"constant", kst = dest-256}
			end

			minpc = math.max(minpc, 0)
			for i=pc, minpc, -1 do
				if decoded[i] and testdest(decoded[i], dest) and canInline(dest, i, pc+1) then
					return visitExpression(i)
				end
			end
			return {"local", reg = dest}
		end

		local visitedExpressions = {}
		local function visitExpressionImpl(pc, destreg)
			-- Visits an expression at a pc, which may visit more if needed
			-- This is scoped to the smallest barrier around this pc
			local scope = computeBarrier(pc)

			local instr = decoded[pc]
			if not instr then return end

			visitedExpressions[pc] = true

			local typ = instr[1]
			print("Visited expression at", pc, typ)
			if typ == "binop" then
				local lhsexpr = findExpressionWithDest(pc-1, instr.lhs, scope.s)
				local rhsexpr = findExpressionWithDest(pc-1, instr.rhs, scope.s)

				return {"binop", instr[2], lhs = lhsexpr, rhs = rhsexpr}
			elseif typ == "unop" then
				local rhsexpr = findExpressionWithDest(pc-1, instr.rhs, scope.s)

				return {"unop", instr[2], rhs = rhsexpr}
			elseif typ == "getglobal" then
				return {"getglobal", index = {"constant", kst = instr.index}}
			elseif typ == "loadk" then
				return {"constant", kst = instr.kst}
			elseif typ == "move" then
				return {"local", reg = instr.src}
			elseif typ == "gettable" then
				local table = findExpressionWithDest(pc-1, instr.table, scope.s)
				local indexexpr = findExpressionWithDest(pc-1, instr.index, scope.s)

				return {"gettable", table = table, index = indexexpr}
			elseif typ == "call" then
				local args = {}
				local self = false

				for i=instr.base, instr.base+instr.narg do
					local expr = findExpressionWithDest(pc-1, i, scope.s)
					if expr[1] == "self" then
						self = true
					end
					args[#args+1] = expr
				end

				local func = table.remove(args, 1)

				if self then
					-- Remove the first argument from the function
					-- Otherwise the rendered code is invalid
					table.remove(args, 1)
				end

				return {"call", func = func, args = args}
			elseif typ == "condop" then
				local op
				local subtyp = instr[2]

				if subtyp == "test" then
					op = {"condop", "test", target = findExpressionWithDest(pc-1, instr.target, scope.s), invert = instr.invert}
				else
					local lhsexpr = findExpressionWithDest(pc-1, instr.lhs, scope.s)
					local rhsexpr = findExpressionWithDest(pc-1, instr.rhs, scope.s)
					local invert = instr.invert

					local function doInvert()
						invert = not invert
						subtyp = flipConditional[subtyp]
						lhsexpr, rhsexpr = rhsexpr, lhsexpr
					end

					if rhsexpr.pc and lhsexpr.pc and rhsexpr.pc < lhsexpr.pc then
						-- rhs is evaluated before lhs...
						doInvert()
					elseif lhsexpr[1] == "constant" then
						-- style changes
						doInvert()
					end

					op = {"condop", subtyp, lhs = lhsexpr, rhs = rhsexpr, invert = invert}
				end

				if istagged(pc, "conditional_invert") then
					op.invert = not op.invert
				end

				-- TODO: Add ability to place a conditional_class on any pc (allows us to handle expression conditionals correctly)
				local cc = nil --findtag(pc, "conditional_class")
				if cc then
					local oplhs = visitExpression(cc.lhs)
					if cc.invert then
						local function invertCondOp(co)
							co.invert = not co.invert
							if co[2] ~= "test" then
								co[2] = flipConditional[co[2]]
								co.lhs, co.rhs = co.rhs, co.lhs
							end
						end

						if oplhs[1] == "condop" then
							invertCondOp(oplhs)
						elseif oplhs[1] == "condcl" then
							invertCondOp(oplhs.rhs)
						end
					end
					return {"condcl", cc.class, lhs = oplhs, rhs = op}
				end

				return op
			elseif typ == "self" then
				local object = findExpressionWithDest(pc-1, instr.object, scope.s)
				local method = findExpressionWithDest(pc-1, instr.method, scope.s)

				return {"self", object = object, method = method}
			elseif typ == "closure" then
				return {"closure", proto = instr.proto, upvalues = instr.upvalues}
			elseif typ == "return" then
				local rets = {}
				for i=instr.base, instr.base+instr.count-1 do
					rets[#rets+1] = findExpressionWithDest(pc-1, i, scope.s)
				end
				return {"return", rets = rets}
			elseif typ == "newtable" then
				return {"newtable"}
			elseif typ == "settable" then
				local src = findExpressionWithDest(pc-1, instr.src, scope.s)
				local table = findExpressionWithDest(pc-1, instr.table, scope.s)
				local index = findExpressionWithDest(pc-1, instr.index, scope.s)
				return {"settable", src = src, table = table, index = index}
			elseif typ == "getupval" then
				return {"getupvalue", upvalue = instr.upvalue}
			elseif typ == "loadbool" then
				local ct = findtag(pc, "conditional_target")

				if not ct then
					return {"bool", value = instr.value}
				end

				-- Flag the previous loadbool as visited too
				visitedExpressions[pc-1] = true
				return visitExpression(ct.pc)
			elseif typ == "forprep" then
				local s = findExpressionWithDest(pc-1, instr.base, scope.s)
				local e = findExpressionWithDest(pc-1, instr.base+1, scope.s)
				local step = findExpressionWithDest(pc-1, instr.base+2, scope.s)
				return {"forprep", s = s, e = e, step = step, index = instr.base+3}
			elseif typ == "tforloop" then
				local iterfun = findExpressionWithDest(pc-1, instr.base, scope.s)
				local itera = findExpressionWithDest(pc-1, instr.base+1, scope.s)
				local iterb = findExpressionWithDest(pc-1, instr.base+2, scope.s)

				local ret = {"tforloop", deststart = instr.base+3, destend = instr.base+3+instr.count-1}

				if iterfun.pc == itera.pc and iterfun.pc == iterb.pc then
					ret.iter = iterfun
				else
					ret.iter = {"multi", iterfun, itera, iterb}
				end

				return ret
			elseif typ == "loadnil" then
				return {"nil"}
			elseif typ == "testset" then
				assert(instr.invert == true) -- ??HOW DO WE GET THE OTHER TYPE??
				local a = findExpressionWithDest(pc-1, instr.target, scope.s)
				local b = visitExpression(decoded[pc+1].to-1)

				return {"testset", a = a, b = b}
			else
				error("Unhandled type: "..typ)
			end
		end

		function visitExpression(pc, t)
			local res = visitExpressionImpl(pc)

			local cc = findtag(pc, "conditional_class")
			if cc then
				local oplhs = visitExpression(cc.lhs)
				if cc.invert then
					local function invertCondOp(co)
						co.invert = not co.invert
						if co[2] ~= "test" then
							co[2] = flipConditional[co[2]]
							co.lhs, co.rhs = co.rhs, co.lhs
						end
					end

					if oplhs[1] == "condop" then
						invertCondOp(oplhs)
					elseif oplhs[1] == "condcl" then
						invertCondOp(oplhs.rhs)
					end
				end
				res = {"condcl", cc.class, lhs = oplhs, rhs = res}
			end

			res.pc = pc
			if t then tag(pc, t) end

			return res
		end

		local function debugFormatExpression(exp)
			local typ = exp[1]
			if typ == "getglobal" then
				return "GLOB:"..debugFormatExpression(exp.index)
			elseif typ == "constant" then
				return "K:"..tostring(chunk.constants[exp.kst])
			elseif typ == "binop" then
				return "BINOP:["..debugFormatExpression(exp.lhs).." "..exp[2].." "..debugFormatExpression(exp.rhs).."]"
			elseif typ == "local" then
				return "L:"..exp.reg
			elseif typ == "gettable" then
				return "I:"..debugFormatExpression(exp.table).."["..debugFormatExpression(exp.index).."]"
			elseif typ == "call" then
				local args = {}
				for i=1, #exp.args do
					args[i] = debugFormatExpression(exp.args[i])
				end
				return "C:"..debugFormatExpression(exp.func).."("..table.concat(args, ", ")..")"
			elseif typ == "condop" then
				local subtyp = exp[2]
				local invert = exp.invert
				if subtyp == "test" then
					return (invert and "T!:" or "T:")..debugFormatExpression(exp.target)
				else
					return (invert and "T!:" or "T:").."["..debugFormatExpression(exp.lhs).." "..subtyp.." "..debugFormatExpression(exp.rhs).."]"
				end
			elseif typ == "condcl" then
				local subtyp = exp[2]
				return "CC:"..subtyp..":".."["..debugFormatExpression(exp.lhs).." "..subtyp.." "..debugFormatExpression(exp.rhs).."]"
			elseif typ == "self" then
				return "S:"..debugFormatExpression(exp.object)..":"..debugFormatExpression(exp.method)
			else
				return "ERR:["..typ.." not impl]"
			end
		end

		print(colors "%{bright green}Visiting roots:")
		for pc in pairs(expressionRoots) do
			local expr = visitExpression(pc)
			decodedExpressions[pc] = expr
			print(pc, debugFormatExpression(expr))
		end

		-- Now, since all expressions have been visited, walk through source backwards to find roots that haven't been picked up
		print(colors "%{bright green}Picking up hanging roots:")
		for pc=decoded.last, 0, -1 do
			local instr = decoded[pc]
			if (not visitedExpressions[pc]) and instr and validExpressions[instr[1]] then
				print(colors "%{bright blue}FOUND ROOT AT", pc)
				local expr = visitExpression(pc, {
					type = "hanging",
					root = pc
				})
				decodedExpressions[pc] = expr
				print(pc, debugFormatExpression(expr))
			end
		end
	end

	local statementLayout = {}

	local function statementReconstruction()
		-- From tags and blocks, reconstruct the statement layout of the chunk
		-- We do not refer to expressions by an entire object, but by the root pc
		-- We iterate through instructions backwards

		print()
		print(colors "%{bright red}Reconstructing statement layout:")

		local pc = decoded.last

		local function addStat(t)
			table.insert(statementLayout, 1, t)
			t.pc = pc
		end

		while pc >= 0 do
			local tags = tags[pc]

			if tags then
				for i=1, #tags do
					local tag = tags[i]

					if tag.type == "hanging" and tag.root == pc then
						addStat {
							"local",
							count = calculateDestCount(decoded[pc]),
							expr = pc
						}
					elseif tag.type == "while" and tag.s == pc then
						addStat {
							"while",
							data = tag
						}
					elseif tag.type == "conditional_block" and tag.ifstat and tag.s == pc then
						addStat {
							"if",
							data = tag
						}
					elseif tag.type == "for" and tag.s == pc then
						addStat {
							"for",
							data = tag
						}
					elseif tag.type == "gfor" and tag.s == pc then
						addStat {
							"gfor",
							data = tag
						}
					elseif tag.type == "break" then
						addStat {
							"break"
						}
					end
				end
			end

			pc = pc-1
		end

		print(serpent.block(statementLayout))
	end

	local function renderSource()
		print()
		print(colors "%{bright red}Rendering source:")

		local source = {}
		local indentLevel = 0

		local function emit(s)
			source[#source+1] = string.rep(" ", indentLevel*2)..s
			print(source[#source])
		end

		local function emitPlaceholder()
			source[#source+1] = indentLevel
			return #source
		end

		local function replace(i, s)
			local oldIndentLevel = source[i]
			source[i] = string.rep(" ", oldIndentLevel*2)..s
		end

		local function remove(i)
			table.remove(source, i)
		end

		local usedLocals = {}

		local function renderExpression(expr, raw)
			local typ = expr[1]

			if typ == "constant" then
				if raw then
					return chunk.constants[expr.kst]
				else
					local const = chunk.constants[expr.kst]
					local constType = type(const)
					if constType == "string" then
						return string.format("%q", const)
					else
						return tostring(const)
					end
				end
			elseif typ == "getglobal" then
				return renderExpression(expr.index, true)
			elseif typ == "gettable" then
				return renderExpression(expr.table).."."..renderExpression(expr.index, true)
			elseif typ == "binop" then
				return renderExpression(expr.lhs)..expr[2]..renderExpression(expr.rhs)
			elseif typ == "unop" then
				return expr[2]..renderExpression(expr.rhs)
			elseif typ == "call" then
				local renderedFunc = renderExpression(expr.func)
				local renderedArgs = {}
				for i=1, #expr.args do
					renderedArgs[i] = renderExpression(expr.args[i])
				end
				return renderedFunc.."("..table.concat(renderedArgs, ", ")..")"
			elseif typ == "local" then
				return formatLocal(expr.reg)
			elseif typ == "condop" then
				if expr[2] == "test" then
					return (expr.invert and "not " or "")..renderExpression(expr.target)
				end
				return renderExpression(expr.lhs)..(expr.invert and invertedConditionals[expr[2]] or expr[2])..renderExpression(expr.rhs)
			elseif typ == "condcl" then
				return renderExpression(expr.lhs).." "..expr[2].." "..renderExpression(expr.rhs)
			elseif typ == "self" then
				return renderExpression(expr.object)..":"..renderExpression(expr.method, true)
			elseif typ == "closure" then
				local copyopts = {}
				for i, v in pairs(opts) do
					copyopts[i] = v
				end
				copyopts.indentLevel = indentLevel+1
				copyopts.asFunction = true
				copyopts.level = level+1
				copyopts.upvalues = {
					prev = opts.upvalues,
					cur = expr.upvalues,
					level = level
				}
				print(expr.proto, decoded.protos[expr.proto])
				local s, source = pcall(decompiler.decompile, decoded.protos[expr.proto], chunk.functionPrototypes[expr.proto], copyopts)
				if not s then
					return "--[[[ "..source.." ]]]"
				end

				return table.concat(source, "\n")
			elseif typ == "return" then
				local rets = {}
				for i=1, #expr.rets do
					rets[i] = renderExpression(expr.rets[i])
				end
				return "return "..table.concat(rets, ", ")
			elseif typ == "newtable" then
				return "{}"
			elseif typ == "settable" then
				return renderExpression(expr.table).."."..renderExpression(expr.index, true).." = "..renderExpression(expr.src)
			elseif typ == "getupvalue" then
				return formatUpvalue(expr.upvalue)
			elseif typ == "forprep" then
				return "for "..formatLocal(expr.index).." = "..renderExpression(expr.s)..", "..renderExpression(expr.e)..", "..renderExpression(expr.step).." do"
			elseif typ == "tforloop" then
				local vl = {}
				for i=expr.deststart, expr.destend do
					vl[#vl+1] = formatLocal(i)
				end
				return "for "..table.concat(vl, ", ").." in "..renderExpression(expr.iter).." do"
			elseif typ == "bool" then
				return tostring(expr.value)
			elseif typ == "testset" then
				return renderExpression(expr.a).." or "..renderExpression(expr.b)
			elseif typ == "nil" then
				return "nil"
			else
				error("unimplemented expression "..typ)
			end
		end

		local function renderStandaloneExpression(expr, setCount)
			if setCount == 0 then
				emit(renderExpression(expr))
			else
				local base = instructionBase(decoded[expr.pc])
				local sets = {}
				for i=base, base+setCount-1 do
					sets[#sets+1] = formatLocal(i)
					usedLocals[i] = true
				end
				emit(table.concat(sets, ", ").." = "..renderExpression(expr))
			end
		end

		local blocks = {}

		local function renderStatement(stat)
			while #blocks > 0 and stat.pc > blocks[#blocks] do
				indentLevel = indentLevel-1
				emit "end"
				table.remove(blocks, #blocks)
			end

			local typ = stat[1]

			if typ == "local" then
				local expr = decodedExpressions[stat.expr]
				renderStandaloneExpression(expr, stat.count)
			elseif typ == "if" then
				local expr = decodedExpressions[stat.data.e-1]
				emit("if "..renderExpression(expr).." then")
				indentLevel = indentLevel+1
				blocks[#blocks+1] = stat.data.blockEnd-1
			elseif typ == "while" then
				local condBlock = stat.data.condBlock

				if condBlock then
					local expr = decodedExpressions[condBlock.e-1]
					emit("while "..renderExpression(expr).." do")
				else
					emit "while true do"
				end
				indentLevel = indentLevel+1
				blocks[#blocks+1] = stat.data.e-1
			elseif typ == "for" then
				-- Prelude should be rendered from an expression
				-- TODO: I really need to rename "expression" to something else
				indentLevel = indentLevel+1
				blocks[#blocks+1] = stat.data.e-1
			elseif typ == "gfor" then
				-- Prelude should be rendered from an expression
				-- TODO: I really need to rename "expression" to something else
				local expr = decodedExpressions[stat.data.e-1]
				emit(renderExpression(expr))
				indentLevel = indentLevel+1
				blocks[#blocks+1] = stat.data.e-1
			elseif typ == "break" then
				emit "break"
			end
		end

		local function flushEnds()
			for i=1, #blocks do
				indentLevel = indentLevel-1
				emit "end"
			end
		end

		if opts.asFunction then
			local args = {}

			if chunk.nparam >= 1 then
				for i=1, chunk.nparam do
					args[#args+1] = formatLocal(i-1)
				end
			end

			if chunk.isvararg ~= 0 then
				args[#args+1] = "..."
			end

			emit("function("..table.concat(args, ", ")..")")
			blocks[#blocks+1] = math.huge
			indentLevel = indentLevel+1
		end

		if opts.indentLevel then
			indentLevel = opts.indentLevel+indentLevel-1
		end

		local locals = emitPlaceholder()

		for i=1, #statementLayout do
			renderStatement(statementLayout[i])
		end
		flushEnds()

		local usedLocalList = {}
		for i=chunk.nparam, chunk.maxStack do
			if usedLocals[i] then
				usedLocalList[#usedLocalList+1] = formatLocal(i)
			end
		end

		if #usedLocalList == 0 then
			remove(locals)
		else
			replace(locals, "local "..table.concat(usedLocalList, ", "))
		end

		return source
	end

	if false then
	local exprStack = {}
	local pc = 0

	local function decodeExpression()
		local instr = decoded[pc]
		if instr and validExpressions[instr[1]] then
			local typ = instr[1]
			if typ == "newtable" then
				-- Special handling for newtable!
				-- We take all SETLIST and SETTABLE instructions
				-- that fit in the preallocated storage of the table.
				pc = pc+1
				local hashEntriesLeft, arrayEntriesLeft = instr.hashcnt, instr.arraycnt
				while pc <= decoded.last do
					local jnstr = decoded[pc]
					if jnstr then
						if validExpressions[jnstr[1]] then
							decodeExpression()
						elseif jnstr[1] == "settable" and jnstr.table == instr.dest and hashEntriesLeft > 0 then
							hashEntriesLeft = hashEntriesLeft-1
							-- TODO: peek last expression, if dest == src, cool
							-- then peek expression before that (if index is a register), if dest == index, cool
						elseif jnstr[1] == "setlist" and jnstr.base == instr.dest then
							-- TODO: setlist stuff
						else
							break
						end
					end
				end
			end
		end
	end

	local function decodeStatement(i)
		-- TODO: Look ahead for JMP, etc
	end
	end

	identifyStructures()
	expressionReconstruction()
	statementReconstruction()
	local source = renderSource()

	return source, {
		tags = tags,
		expressionRoots = expressionRoots,
		blocks = blocks,
		regusage = regusage,
		barriers = barriers,
		decodedExpressions = decodedExpressions,
		statementLayout = statementLayout,
		source = source
	}
end

return decompiler
