-- Decodes Lua 5.1 Bytecode into the Immediate Representation --

local bytecode = require "luavm.bytecode"
local version = bytecode.version.lua51

-- instruction constants copied from luavm.bytecode.lua51

local MOVE = 0
local LOADK = 1
local LOADBOOL = 2
local LOADNIL = 3
local GETUPVAL = 4
local GETGLOBAL = 5
local GETTABLE = 6
local SETGLOBAL = 7
local SETUPVAL = 8
local SETTABLE = 9
local NEWTABLE = 10
local SELF = 11
local ADD = 12
local SUB = 13
local MUL = 14
local DIV = 15
local MOD = 16
local POW = 17
local UNM = 18
local NOT = 19
local LEN = 20
local CONCAT = 21
local JMP = 22
local EQ = 23
local LT = 24
local LE = 25
local TEST = 26
local TESTSET = 27
local CALL = 28
local TAILCALL = 29
local RETURN = 30
local FORLOOP = 31
local FORPREP = 32
local TFORLOOP = 33
local SETLIST = 34
local CLOSE = 35
local CLOSURE = 36
local VARARG = 37

-- These functions define common explets

local function R(c)
	return {"register", c}
end

local function K(c)
	return {"constant", c}
end

local function RK(c)
	if c > 255 then
		return K(c-256)
	else
		return R(c)
	end
end

local function V(v)
	return {"value", v}
end

local function U(p)
	return {"upvalue", p}
end

local function G(i)
	return {"global", i}
end

local function I(t, i)
	return {"index", t, i}
end

local function BIN(a, op, b)
	return {"binaryop", a, op, b}
end

local function UN(op, a)
	return {"unaryop", op, a}
end

-- Operator data

local binaryOps = {
	[ADD] = "+",
	[SUB] = "-",
	[MUL] = "*",
	[DIV] = "/",
	[MOD] = "%",
	[POW] = "^",
}

local unaryOps = {
	[UNM] = "-",
	[NOT] = "not",
	[LEN] = "#",
}

local conditionalOps = {
	[EQ] = "==",
	[LT] = "<",
	[LE] = "<=",
	[TEST] = true, -- special handling
}

return function(decoder)
	local target = {}

	-- The decoder is organized into 3 parts:
		-- Block decoder
		-- Expression decoder
		-- Conditional expression decoder

	local function decodeExpression(chunk, i, context, collect)
		local op, a, b, c = version.decode(chunk.instructions[i])

		if op == MOVE then
			collect {op = "set", src = {R(b)}, dest = {R(a)}, pc = i}
		elseif op == LOADK then
			collect {op = "set", src = {K(b)}, dest = {R(a)}, pc = i}
		elseif op == LOADBOOL and c == 0 then
			collect {op = "set", src = {V(b ~= 0)}, dest = {R(a)}, pc = i}
		elseif op == LOADNIL then
			for i=a, b do
				collect {op = "set", src = {V(nil)}, dest = {R(i)}, pc = i}
			end
		elseif op == GETUPVAL then
			collect {op = "set", src = {U(b)}, dest = {R(a)}, pc = i}
		elseif op == GETGLOBAL then
			collect {op = "set", src = {G(b)}, dest = {R(a)}, pc = i}
		elseif op == GETTABLE then
			collect {op = "set", src = {I(R(b),RK(c))}, dest = {R(a)}, pc = i}
		elseif op == SETGLOBAL then
			collect {op = "set", src = {R(a)}, dest = {G(b)}, pc = i}
		elseif op == SETUPVAL then
			collect {op = "set", src = {R(a)}, dest = {U(b)}, pc = i}
		elseif op == SETTABLE then
			collect {op = "set", src = {RK(c)}, dest = {I(R(a), RK(b))}, pc = i}
		elseif op == NEWTABLE then
			collect {op = "set", src = {V{}}, dest = {R(a)}, pc = i}
		elseif op == SELF then
			--error "TODO: Do extra processing here to deduce to a function call"

			-- To find the ending CALL for the self expression we iterate through until we see a CALL
				-- that shares our same dest register as a source
			--if i == 54 then error '!' end
			local callidx
			for j=i, chunk.instructions.count-1 do
				local cop, ca, cb, cc = version.decode(chunk.instructions[j])
				if (cop == CALL or cop == TAILCALL) and ca == a then
					callidx = j
					break
				end
			end

			if not callidx then
				error 'TODO: Support handwritten bytecode exploiting SELF'
			end

			-- TODO: Some way to tag the call...
			collect {op = "set", src = {R(b), I(R(b), RK(c))}, dest = {R(a+1), R(a)}, pc = i}

			-- self needs to be it's own psuedo-op
			-- for simplicity's sake
			--collect {op = "self", src = {R(b), RK(c)}, dest = {R(a), R(a+1)}, pc = i}
		elseif binaryOps[op] then
			collect {op = "set", src = {BIN(RK(b), binaryOps[op], RK(c))}, dest = {R(a)}, pc = i}
		elseif unaryOps[op] then
			collect {op = "set", src = {UN(unaryOps[op], R(b))}, dest = {R(a)}, pc = i}
		elseif op == CONCAT then
			local src = {"concat"}

			for i=b, c do
				src[#src+1] = R(i)
			end

			collect {op = "set", src = {src}, dest = {R(a)}, pc = i}
		elseif op == CALL then
			local args = {}
			local dests = {}

			-- TODO: TOP support!

			for i=a, a+c-2 do
				dests[#dests+1] = R(i)
			end

			for i=a+1, a+b-1 do
				args[#args+1] = R(i)
			end

			collect {op = "set", src = {{"call", R(a), args}}, dest = dests, pc = i}
		elseif op == CLOSURE then
			print('start proto '..b)
			local block = {}
			target.decode(chunk.functionPrototypes[b], nil, nil, context, function(v)
				block[#block+1] = v
			end)
			collect {op = "set", src = {{"closure", block}}, dest = {R(a)}, pc = i}
		else
			return false
		end

		return true, i+1
	end

	-- TODO: Figure out exactly what the hell this function is doing and make examples!
	-- TODO: Fix all of this
	--[[
		Conditional jumps have 2 ways they can go.
		They can jump inside of the block or outside of the block.
		They ONLY have 2 targets.
		The inside block jump ALWAYS has a smaller PC than the outside
		block jump.
		When two conditionals are jumping OUT (1 after another) it forms
		an `and` statement.
		When the first conditional jumps IN and the second conditional
		jumps OUT it forms an `or` statement.

		Conditionals ALWAYS fall in at the bottom. The bottom of the
		conditional block IS ALWAYS THE JUMP IN POINT.

		[OUT, OUT] == and statement
		[IN, OUT] == or statement
		[OUT, IN] == ill formed
		[IN, IN] == ill formed

		Example and statement:

		if x == 5 and y == 6 then
			<OP>
		end
		<OP2>

		0| EQ r0, 5 [JUMPS OUT ON FAIL]
		1| JMP +3
		2| EQ r1, 6 [JUMPS OUT ON FAIL]
		3| JMP +1
		4| <OP>
		5| <OP2>

		Example or statement:

		if x == 5 or y == 6 then
			<OP>
		end
		<OP2>

		0| NEQ r0, 5 [JUMPS IN ON "FAIL"] [NOTICE THE CONDITION IS INVERT]
		1| JMP +2
		2| EQ r1, 6 [JUMPS OUT ON FAIL]
		3| JMP +1
		4| <OP>
		5| <OP2>

		How do expressions play in this:

		Lua will generate expressions inside of our conditional block.
		To work with that, while we aren't a conditional op, we parse
		expressions but we do manual collection and inlining.
	]]
	local function decodeConditionalJumps(chunk, i)
		local logic = {}

		-- First, get the jump bounds (AKA places where conditional jumps can go)
		local ci = i
		while true do
			local op, a, b, c = version.decode(chunk.instructions[ci])
			if op == EQ or op == LT or op == LE or op == TEST then
				local invert = op == TEST and (c ~= 0) or (a ~= 0)
				local nextop = version.decode(chunk.instructions[ci+1])
				local l = {}
				logic[ci] = l

				-- I have no idea how this code works anymore
				-- But it does
				if nextop ~= EQ and nextop ~= LT and nextop ~= LE and nextop ~= TEST then
					if invert then
						l.exitOnTrue = true
					else
						l.exitOnFalse = true
					end
					ci = ci+1
					-- Visit the very next, resolve as true
					nextop = version.decode(chunk.instructions[ci+1])
					if nextop ~= EQ and nextop ~= LT and nextop ~= LE and nextop ~= TEST then
						if not invert then
							l.exitOnTrue = true
						else
							l.exitOnFalse = true
						end
						break
					end
				end
				ci = ci+1
			else
				break
			end
		end

		en = ci

		--[[
		Example:

		NEQ R0 6 (false continues, true exits)
		JMP 2
		EQ R0 8 (false exits, true exits)
		JMP 4

		So, an Lua or statement always executes the second one if the first one fails
		So if it is "false continues" then it's an or statement
		Else if it's "true continues" then it's an and statement

		]]

		local root = {}
		local exp = root
		ci = i
		while ci <= en do -- Now, try to resolve boolean logic
			local op, a, b, c = version.decode(chunk.instructions[ci])
			if op == EQ or op == LT or op == LE or op == TEST then
				local l = logic[ci]

				local opdest, shouldBreak = nil, false
				if (not l.exitOnFalse) and l.exitOnTrue then
					opdest = {}
					exp[1] = "binaryop"
					exp[2] = opdest
					exp[3] = "or"
					exp[4] = {}
					exp = exp[4]
				elseif (not l.exitOnTrue) and l.exitOnFalse then
					opdest = {}
					exp[1] = "binaryop"
					exp[2] = opdest
					exp[3] = "and"
					exp[4] = {}
					exp = exp[4]
				else
					opdest = exp
					shouldBreak = true
				end

				print(l.exitOnTrue, l.exitOnFalse)

				local invert = op == TEST and (c ~= 0) or (a ~= 0)

				if invert then
					opdest[1] = "unaryop"
					opdest[2] = "not"
					opdest[3] = {}
					opdest = opdest[3]
				end

				if op == TEST then
					opdest[1] = "register"
					opdest[2] = a
				else
					opdest[1] = "binaryop"
					opdest[2] = RK(b)
					opdest[3] = conditionalOps[op]
					opdest[4] = RK(c)
				end

				if shouldBreak then
					break
				end
			end
			ci = ci+1
		end

		return root, en
	end

	-- "Block" instructions
	local function decodeInstruction(chunk, i, context, collect)
		local op, a, b, c = version.decode(chunk.instructions[i])

		--print(version.instructionNames[op], a, b, c)

		if op == RETURN then
			local srcs = {}

			if b == 0 then
				srcs[1] = {"top", a} -- TODO: Remember that top needs to be forced inlined!
			else
				for i=a, a+b-2 do
					srcs[#srcs+1] = R(i)
				end
			end

			collect {op = "return", src = srcs, pc = i}
		elseif op == JMP then
			local dest = i+b+1 -- Lua does pre increment
			local jop, ja, jb, jc = version.decode(chunk.instructions[dest])

			if jop == TFORLOOP then
				-- generic for loop
				local gfor = {
					op = "gfor",
					src={R(ja), R(ja+1), R(ja+2)},
					dest = {},
					loop = {entry = i, exit = dest},
					block = {},
					pc = i,
				}

				for i=ja+3,ja+2+jc do
					gfor.dest[#gfor.dest+1] = R(i)
				end

				target.decode(chunk, i+1, dest-1, gfor, function(v)
					gfor.block[#gfor.block+1] = v
				end)

				collect(gfor)
				i = dest+1 -- skip jump
			elseif jb == -1 then -- tight loop with no statements (hang)
				collect {
					op = "while",
					src = {V(true)},
					block = {},
					pc = i
				}
			elseif context and context.loop and dest == context.loop.exit then
				collect {op = "break", pc = i}
			else
				--return false, "invalid jump"
				error("Unhandled jump!")
			end
		elseif op == FORPREP then
			-- for loop
			local base, dest = a, i+b+1

			local forloop = {
				op = "for",
				src = {R(base), R(base+1), R(base+2)},
				dest = {R(base+3)},
				loop = {entry = i, exit = dest},
				block = {},
				pc = i
			}

			target.decode(chunk, i+1, dest-1, forloop, function(v)
				forloop.block[#forloop.block+1] = v
			end)

			collect(forloop)
			i = dest
		elseif conditionalOps[op] then
			local condI = i
			local cond, ni = decodeConditionalJumps(chunk, i)
			i = ni

			op, a, b, c = version.decode(chunk.instructions[i])

			print("hit conditional at "..condI)
			print("target "..i)

			if op == JMP then
				-- If the very next statement after a conditional expression is a jump, it is an if statement or a while loop

				-- For IF Statements:
				-- This jump goes to the else part of the if statement
				-- If the op before the else part of the if statement is a jump that goes past the else statement, an else
					-- statement is present
				--[[
					Example:
					if a < 0 then
						a = -a
					end

					Possible output (assuming `a` is a local variable):
					LT r0, 256 (0 [constant 0])
					JMP 1 [skip next] <-- this is jumping out of the if statement (or to the else part, if any)
					UNM r0, r0

					~~~~~~~

					Example:

					if a < 0 then
						a = a*a
					else
						a = a/a
					end

					Possible output (assuming `a` is a local variable):
					LT r0, k0 [0]
					JMP 2 [skip next 2] <-- Jump to the start of the else statement
					MUL r0, r0, r0
					JMP 1 [skip next] <-- Jump to the end of the else statement
					DIV r0, r0, r0
				]]

				-- For WHILE Statements:
				-- The jump goes to the instruction after the backwards jump that targets the instruction after the current jump
				--[[
					Example:

					local a = 100
					while a < 0 do
						a = a-1
					end

					Possible output:
					LOADK r0, k0 [100]
					LT r0, k1 [0]
					JMP 2 <-- Jump after the backwards jump
					SUB r0, r0, k2 [1]
					JMP -4 <-- Jump to the condition check (LT)
				]]

				-- An IF and WHILE statement are different because of the backwards jump

				local dest = i+b

				-- If the jump continues the current loop from the top, this is an if statement at the end of a loop block
				if context and context.loop and context.loop.entry == dest+1 then
					local ifstat = {
						op = "if",
						src = {cond},
						loop = context.loop,
						block = {},
						pc = i,
						assertLast = true -- This NEEDS to be the last one in a block
					}

					target.decode(chunk, i+1, i+1, ifstat, function(v)
						ifstat.block[#ifstat.block+1] = v
					end)

					i = i+1

					collect(ifstat)
				else
					local destOp, _, destB = version.decode(chunk.instructions[dest])

					if destOp == JMP and destB < -1 then -- -1 jumps back onto the instruction itself
						local whileloop = {
							op = "while",
							src = {cond},
							loop = {entry = condI, exit = dest+1},
							block = {},
							pc = i
						}

						print("generating while ["..condI.." -> "..(dest+1).."]")

						target.decode(chunk, i+1, dest-1, whileloop, function(v) -- don't hit that end jump
							whileloop.block[#whileloop.block+1] = v
						end)

						i = dest
						collect(whileloop)
					else
						local ifstat = {
							op = "if",
							src = {cond},
							loop = context and context.loop or nil,
							block = {},
							pc = i
						}

						local decodeElse = false
						local decodeDest = dest
						if destOp == JMP and destB > 0 then
							-- TODO: Decide if this is a break or a jump
							decodeDest = dest-1
							decodeElse = true
						end

						target.decode(chunk, i+1, decodeDest, ifstat, function(v)
							ifstat.block[#ifstat.block+1] = v
						end)

						if decodeElse then
							local elsestat = {
								op = "else",
								loop = context and context.loop or nil,
								block = {},
								pc = dest
							}

							local elseDest = dest+destB
							target.decode(chunk, dest+1, elseDest, elsestat, function(v)
								elsestat.block[#elsestat.block+1] = v
							end)

							ifstat.block[#ifstat.block+1] = elsestat
							i = elseDest
						else
							i = dest
						end

						collect(ifstat)
					end
				end
			else
				error("Invalid conditional operation magic!")
			end
		else
			return decodeExpression(chunk, i, context, collect)
		end

		return true, i+1
	end

	function target.decode(chunk, i, j, context, collect)
		i = i or 0
		j = j or chunk.instructions.count-2 -- Skip default return
		while i <= j do
			local s, ni = decodeInstruction(chunk, i, context, collect)
			if not s then return false, ni end
			i = ni
		end
		return true, i
	end

	return target
end
