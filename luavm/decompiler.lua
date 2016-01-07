--decompiles lua 5.1 bytecode--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

decompiler = {}
decompiler.debug = true

local function debug(...)
	if decompiler.debug then
		print(...)
	end
end

local instructionNames = {
	[0]="MOVE","LOADK","LOADBOOL","LOADNIL",
	"GETUPVAL","GETGLOBAL","GETTABLE",
	"SETGLOBAL","SETUPVAL","SETTABLE","NEWTABLE",
	"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
	"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
	"FORLOOP","FORPREP","TFORLOOP","SETLIST","CLOSE","CLOSURE","VARARG"
}

local ins = {}
for i, v in pairs(instructionNames) do ins[v] = i end

local iABC = 0
local iABx = 1
local iAsBx = 2

local instructionFormats = {
	[0]=iABC,iABx,iABC,iABC,
	iABC,iABx,iABC,
	iABx,iABC,iABC,iABC,
	iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
	iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
	iAsBx,iAsBx,iABC,iABC,iABC,iABx,iABC
}

local band, brshift = bit.band, bit.brshift
local tostring, unpack = tostring, unpack or table.unpack

local function decodeInstruction(inst)
	local opcode = band(inst,0x3F)
	local format = instructionFormats[opcode]
	if format == iABC then
		return opcode, band(brshift(inst,6),0xFF), band(brshift(inst,23),0x1FF), band(brshift(inst,14),0x1FF)
	elseif format == iABx then
		return opcode, band(brshift(inst,6),0xFF), band(brshift(inst,14),0x3FFFF)
	elseif format == iAsBx then
		local sBx = band(brshift(inst,14),0x3FFFF)-131071
		return opcode, band(brshift(inst,6),0xFF), sBx
	else
		error(opcode.." "..format)
	end
end

local function getsBx(inst)
	local sBx = band(brshift(inst,14),0x3FFFF)-131071
	return sBx
end

local function makeRandomString()
	local s = {}
	for i=1, 5 do
		s[i] = string.char(math.random(97,122))
	end
	s[6] = "_"
	return table.concat(s)
end

--instruction constants--
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

local function computeRegisterUsageMap(bc)
	--make a mapping of all register usages--
	--we can assume that when a register is written over it is being used again--
	--say we set r1 to 5, then we do a function call with r1 as an argument, and we use r1 as a return value--
	--we can assume that we can inline the first r1 load into the function call itself because it is only used once before being set again--
	--this is how inlining works--
	local registerUsageMap = {} --maps a register to all usage instances--
	for i=0, bc.maxStack do
		registerUsageMap[i] = {}
	end
	local pc = 0
	while bc.instructions[pc] do
		local o,a,b,c = decodeInstruction(bc.instructions[pc])
		if o == MOVE then
			registerUsageMap[a][pc] = "set"
			registerUsageMap[b][pc] = "get"
		elseif o == LOADK then
			registerUsageMap[a][pc] = "set"
		elseif o == LOADBOOL then
			registerUsageMap[a][pc] = "set"
		elseif o == LOADNIL then
			for r=a,b do
				registerUsageMap[r][pc] = "set"
			end
		elseif o == GETGLOBAL then
			registerUsageMap[a][pc] = "set"
		elseif o == GETTABLE then
			registerUsageMap[a][pc] = "set"
			registerUsageMap[b][pc] = "get"
			if c < 256 then
				registerUsageMap[c][pc] = "get"
			end
		elseif o == SETGLOBAL or o == SETUPVAL then
			registerUsageMap[a][pc] = "get"
		elseif o == SETTABLE then
			registerUsageMap[a][pc] = "get"
			if b < 256 then
				registerUsageMap[b][pc] = "get"
			end
			if c < 256 then
				registerUsageMap[c][pc] = "get"
			end
		elseif o == NEWTABLE then
			registerUsageMap[a][pc] = "get"
		elseif o == SELF then
			registerUsageMap[a+1][pc] = "set"
			registerUsageMap[b][pc] = "get"
			registerUsageMap[a][pc] = "set"
			if c < 256 then
				registerUsageMap[c][pc] = "get"
			end
		elseif o == ADD or o == SUB or o == MUL or o == DIV or o == MOD or o == POW then
			registerUsageMap[a][pc] = "set"
			if b < 256 then
				registerUsageMap[b][pc] = "get"
			end
			if c < 256 then
				registerUsageMap[c][pc] = "get"
			end
		elseif o == UNM or o == NOT or o == LEN then
			registerUsageMap[a][pc] = "set"
			registerUsageMap[b][pc] = "get"
		elseif o == CONCAT then
			registerUsageMap[a][pc] = "set"
			for i=b, c do
				registerUsageMap[i][pc] = "get"
			end
		elseif o == JMP then
		elseif o == EQ or o == LT or o == LE then
			if b < 256 then
				registerUsageMap[b][pc] = "get"
			end
			if c < 256 then
				registerUsageMap[c][pc] = "get"
			end
		elseif o == TEST then
			registerUsageMap[a][pc] = "get"
		elseif o == TESTSET then
			registerUsageMap[a][pc] = "set"
			registerUsageMap[b][pc] = "get"
		elseif o == CALL then
			registerUsageMap[a][pc] = "get"
			for i=a+1,a+b-1 do
				registerUsageMap[i][pc] = "get"
			end
			for i=a,a+c-2 do
				registerUsageMap[i][pc] = "set"
			end
		elseif o == TAILCALL then
			registerUsageMap[a][pc] = "get"
			for i=a+1,a+b-1 do
				registerUsageMap[i][pc] = "get"
			end
		elseif o == RETURN then
			for i=a+1,a+b-1 do
				registerUsageMap[i][pc] = "get"
			end
		elseif o == FORLOOP then
			registerUsageMap[a][pc] = "set"
			registerUsageMap[a+1][pc] = "get"
			registerUsageMap[a+2][pc] = "get"
			registerUsageMap[a+3][pc] = "set"
		elseif o == FORPREP then
			registerUsageMap[a][pc] = "set"
			--registerUsageMap[a+2][pc] = "get"
		elseif o == TFORLOOP then
			registerUsageMap[a][pc] = "get"
			registerUsageMap[a+1][pc] = "get"
			registerUsageMap[a+2][pc] = "set"
			for i=a+3,a+2+c do
				registerUsageMap[i][pc] = "set"
			end
		elseif o == SETLIST then
			registerUsageMap[a][pc] = "get"
			for i=1, b do
				registerUsageMap[a+i][pc] = "get"
			end
		elseif o == CLOSE then
			
		elseif o == CLOSURE then
			registerUsageMap[a][pc] = "set"
		elseif o == VARARG then
			for i=a, a+b-1 do
				registerUsageMap[i][pc] = "set"
			end
		end
		pc = pc+1
	end
	
	return registerUsageMap
end

local function removeObject(tab, obj)
	for i, v in pairs(tab) do
		print(i, v, obj)
		if v == obj then
			table.remove(tab, i)
			return
		end
	end
	--error("Object not found for removal")
end

local opcodeToOperatorLUT = {
	[LT] = "<",
	[EQ] = "==",
	[ADD] = "+",
	[SUB] = "-",
	[MUL] = "*",
	[DIV] = "/",
}

function decompiler.decompile(bc)
	local pc = 0
	local block
	
	local function isExpressionOp(op,a,b,c)
		return op == GETGLOBAL or op == LOADK or op == CALL or op == MOVE or
				op == GETTABLE or
				op == ADD or op == SUB or op == MUL or op == DIV or op == CONCAT
	end
	
	local function isConditionalJump(op)
		return op == EQ or op == LT or op == LE
	end
	
	local registerUsageMap = computeRegisterUsageMap(bc)
	
	local function registerGetsAfter(reg, pc, epc, notpc)
		local n = 0
		local i = pc+1
		epc = epc or #bc.instructions
		while i <= epc do
			if i ~= notpc then
				if registerUsageMap[reg][i] == "get" then
					print("get r"..reg.." at "..i, notpc)
					n = n+1
				elseif registerUsageMap[reg][i] == "set" then
					break
				end
			
				local jo, ja, jb, jc = decodeInstruction(bc.instructions[i])
				if jo == JMP or jo == FORLOOP then
					if jb < 0 then
						--count the usages from where the jump point to out starting pc, since the code is "connected"
						n = n+registerGetsAfter(reg, i+jb, pc)
					end
				end
			end
			
			i = i+1
		end
		
		return n
	end
	
	local exp --reference to the last decoded expression
	local expressionRegisters = {} --used for optimization
	
	--[[
	Here's an example:
	
	Lets say we have this bytecode:
	GETGLOBAL 0, print
	LOADK 1, "Hello"
	CALL 0, 2, 1
	
	Normally, it would translate into this maddness:
	local vkuux_r0, vkuux_r1
	vkuux_r0 = print
	vkuux_r1 = "Hello"
	vkuux_r0(vkuux_r1)
	
	We all know thats unreadable, and it can be 100% better.
	
	expressionRegisters records data for the last set to a register.
	This can be used to flatten the code into something that looks like the source:
	
	local vkuux_r0, vkuux_r1
	print("Hello")
	]]
	
	--TODO: Multiret version of getLastExpression
	
	local function getLastExpression(r, norem, pc)
		if r > 255 then
			local k = bc.constants[r-256]
			return {type="constant", constant=k}
		end
		
		if exp then
			local e = expressionRegisters[r]
		
			if e and not e.inlined and not e.multiret and registerGetsAfter(r, e.pc, nil, pc) <= 1 then
				if norem ~= true then
					print("Inlining", e, e.type, e[e.type])
					e.inlined = true
					removeObject(exp, e)
				else
					error("Norem depreciated")
				end
				return e
			elseif e then
				print("Inline failure: ", pc, e.type, e[e.type], e.multiret, registerGetsAfter(r, e.pc, nil, pc))
			else
				--error("r"..r.." doesn't have an expression")
			end
		end
		
		return {type="register", register=r}
	end
	
	local function parenthesis(e)
		if e.type == "constant" or e.type == "math" then
			e.parenthesis = true
		end
		return e
	end
	
	local function peek(n)
		n = n or 1
		return decodeInstruction(bc.instructions[pc+n])
	end
	
	local function decompileExpressions(s,e)
		local expressions = {}
		exp = expressions
		
		local pc = s
		while pc < e do
			local op,a,b,c = decodeInstruction(bc.instructions[pc])
			if isExpressionOp(op,a,b,c) then
				--print("EXPRESSION OP", instructionNames[op])
				if op == CALL then
					print("CALL")
					local e = {
						type = "call",
						pc = pc,
						func = getLastExpression(a, nil, pc),
						args = {},
						targets = {}
					}
					
					for i=a+1, a+b-1 do
						e.args[#e.args+1] = getLastExpression(i, nil, pc)
					end
					
					for i=a, a+c-2 do
						--return targets
						e.targets[#e.targets+1] = i
						expressionRegisters[i] = nil
					end
					e.multiret = #e.targets > 1
					
					expressions[#expressions+1] = e
					
					if #e.targets == 1 then
						expressionRegisters[a] = e
					end
				elseif op == GETGLOBAL then
					local e = {
						type = "global",
						pc = pc,
						targets = {a},
						global = bc.constants[b]
					}
					expressions[#expressions+1] = e
					expressionRegisters[a] = e
					print("global "..bc.constants[b])
				elseif op == LOADK then
					local e = {
						type = "constant",
						pc = pc,
						targets = {a},
						constant = bc.constants[b]
					}
					expressions[#expressions+1] = e
					expressionRegisters[a] = e
					print("loadk", a, b)
				elseif op == EQ or op == LT or op == ADD or op == SUB or op == MUL or op == DIV then
					local e = {
						type = "math",
						pc = pc,
						targets = {a},
						lhs = getLastExpression(b, nil, pc),
						op = opcodeToOperatorLUT[op],
						rhs = getLastExpression(c, nil, pc)
					}
					expressions[#expressions+1] = e
					expressionRegisters[a] = e
				elseif op == MOVE then
					local e = {
						type = "register",
						pc = pc,
						targets = {a},
						register = b
					}
					expressions[#expressions+1] = e
					expressionRegisters[a] = e
				elseif op == GETTABLE then
					local e = {
						type = "table",
						pc = pc,
						targets = {a},
						table = parenthesis(getLastExpression(b, nil, pc)),
						index = getLastExpression(c, nil, pc)
					}
					expressions[#expressions+1] = e
					expressionRegisters[a] = e
				elseif op == CONCAT then
					local e = {
						type = "concat",
						pc = pc,
						targets = {a},
						vals = {}
					}
					
					for i=b, c do
						e.vals[#e.vals+1] = parenthesis(getLastExpression(i, nil, pc))
					end
					
					expressions[#expressions+1] = e
					expressionRegisters[a] = e
				end
				pc = pc+1
			end
		end
	end
	
	local function decompileConditionalJumps(e) --composed of EQ, LT, and LE
		local start = pc
		local en
		local logic = {}
		--first, get our jump bounds (AKA places where conditional jumps can go)--
		while pc < e do
			local op,a,b,c = decodeInstruction(bc.instructions[pc])
			if op == EQ or op == LT or op == LE then
				--if the next instruction is a JMP, act like we resolved to the inverse value
				--if the inverse value doesn't go to a conditional jump, then we found the end
				local o = peek(1)
				local l = {}
				logic[pc] = l
				if o ~= EQ and o ~= LT and o ~= LE then
					if a ~= 0 then
						l.exitOnTrue = true
					else
						l.exitOnFalse = true
					end
					--visit the very next, resolve as true
					print("visit next")
					pc = pc+1
					o = peek(1)
					if o ~= EQ and o ~= LT and o ~= LE then
						if a == 0 then
							l.exitOnTrue = true
						else
							l.exitOnFalse = true
						end
						pc = pc-1
						break
					end
				end
			else
				break
			end
			pc = pc+1
		end
		en = pc
		
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
		pc = start
		while pc <= en do --now, try to resolve boolean logic
			local op,a,b,c = decodeInstruction(bc.instructions[pc])
			if op == EQ or op == LT or op == LE then
				local l = logic[pc]
				print(l.exitOnFalse, l.exitOnTrue)
				if (not l.exitOnFalse) and l.exitOnTrue then
					exp.type = "math"
					exp.lhs = {
						type = "math",
						lhs = getLastExpression(b, nil, pc),
						op = opcodeToOperatorLUT[op],
						rhs = getLastExpression(c, nil, pc)
					}
					exp.op = " or "
					exp.rhs = {}
					exp = exp.rhs
					print(b.." == "..c.." or ")
				elseif (not l.exitOnTrue) and l.exitOnFalse then
					exp.type = "math"
					exp.lhs = {
						type = "math",
						lhs = getLastExpression(b, nil, pc),
						op = opcodeToOperatorLUT[op],
						rhs = getLastExpression(c, nil, pc)
					}
					exp.op = " and "
					exp.rhs = {}
					exp = exp.rhs
					print(b.." == "..c.." and ")
				else
					exp.type = "math"
					exp.lhs = getLastExpression(b, nil, pc)
					exp.op = opcodeToOperatorLUT[op]
					exp.rhs = getLastExpression(c, nil, pc)
					print(b.." == "..c)
					break
				end
			end
			pc = pc+1
		end
		
		return root, en+1
	end
	
	local loopdef
	local loopstack = {}
	
	local function decompileBlock(e)
		if not bc.instructions[pc] then return end
		
		e = e or math.huge
		
		local previous = block
		local blk = {}
		block = blk
		
		local expBegin
		local expEnd
		
		print("New block")
		
		while bc.instructions[pc] and pc <= e do
			local op,a,b,c = decodeInstruction(bc.instructions[pc])
			if isExpressionOp(op,a,b,c) then
				expBegin = pc
				while isExpressionOp(op,a,b,c) and pc <= e do
					--expression opcode, advance until next block opcode
					pc = pc+1
					op,a,b,c = decodeInstruction(bc.instructions[pc])
				end
				expEnd = pc
				
				if expBegin ~= expEnd then
					decompileExpressions(expBegin, expEnd)
					blk[#blk+1] = {type="expression",exp=exp}
				end
			else
				expBegin = -1
				exp = nil
			end
			
			if pc > e then break end
			
			if op == RETURN then
				blk[#blk+1] = {type="return",begin=a,size=b-1}
			elseif op == JMP then
				local dest = pc+b
				print(dest, pc)
				
				if loopdef and dest == loopdef.dest then
					blk[#blk+1] = {type = "break"}
				else
					local jo, ja, jb, jc = peek(b+1)
					if jo == TFORLOOP then
						local gfor = {type="gfor",base=ja,vars={}}
						for i=ja+3,ja+2+jc do
							gfor.vars[#gfor.vars+1] = i
						end
						pc = pc+1
						gfor.block = decompileBlock(dest)
						blk[#blk+1] = gfor
						pc = pc+1
					else
						--error("Invalid jump. "..pc)
					end
				end
			elseif op == FORPREP then
				--for loop
				local base, dest = a, pc+b
				
				print("FOR", base, dest)
				local forloop = {type="for", start=getLastExpression(base, nil, pc),
					finish=getLastExpression(base+1, nil, pc),
					step=getLastExpression(base+2, nil, pc),
					target={type="register", register=base+3}}
				pc = pc+1
				forloop.block = decompileBlock(dest)
				blk[#blk+1] = forloop
			elseif isConditionalJump(op) then
				--figure out if this is a loadk vs a regular if statement--
				local condexp, start = decompileConditionalJumps(e)
				pc = start
				
				local _, a, b, c = peek(0)
				local dest = pc+b
				local flb, fa = peek(1)
			
				if flb == LOADBOOL and peek(2) == LOADBOOL and b == 1 then
					--setup the first target to be loadbool's target--
					condexp.targets[1] = fa
					if exp then
						exp[#exp+1] = condexp
					else
						error("TODO:")
					end
					--skip over that other stuff .-.--
					pc = pc+2
				elseif flb == JMP and peek(2) == JMP then
					--"fastpc jmp"
					--the comparison either continues the loop or breaks--
					--only appears at the very end of loops--
					local jo, ja, jb, jc = peek(2)
					assert(jb < 0, "Invalid fast jump")
					
					blk[#blk+1] = {type="if", exp=condexp, block={{type="break"}}}
					pc = pc+2
				else
					local fjt
					local jo, ja, jb, jc = peek(b)
					
					local continue = true
					
					--check to see if we are actually looping--
					if jo == JMP then
						print("HEYO", jb)
						if jb < 1 then
							pc = pc+1
							print("DEST!", dest)
							
							if loopdef then
								loopstack[#loopstack+1] = loopdef
							end
							
							loopdef = {dest=dest}
							
							local whileblock = {type="while", exp=condexp, block=decompileBlock(dest-1)}
							blk[#blk+1] = whileblock
							
							if #loopstack > 0 then
								loopdef = table.remove(loopstack, #loopstack)
							end
							
							pc = pc-1
							
							continue = false
						end
					end
					
					--output as if statement
					if continue then
						print("IF: ", dest)
					
						pc = pc+1
						local ifblock = {type="if", exp=condexp, block=decompileBlock(dest-1)}
				
						--if we land on a JMP, then it's an else statement--
						if jo == JMP then
							local old = pc
							pc = dest+1
							if jb < 1 then
								error("WAT")
							else
								ifblock.elseblock = decompileBlock(pc+jb-1)
							end
						end
				
						blk[#blk+1] = ifblock
						pc = pc-1
						print("END IF AT", pc)
					end
				end
			end
			
			pc = pc+1
		end
		
		print("End block")
		
		block = previous
		return blk
	end
	
	local output = {
		info = {locals = bc.maxStack},
		block = decompileBlock()
	}
	
	return output
end

local styles = {
	basic = {
		comma = ",",
		tab = "",
		newline = " ",
		operation = "%s%s%s",
		equals = "=",
		forloop = "for %s=%s,%s,%s do",
		gforloop = "for %s in %s do"
	},
	pretty = {
		comma = ", ",
		tab = "\t",
		newline = "\n",
		operation = "%s %s %s",
		equals = " = ",
		forloop = "for %s = %s, %s, %s do",
		gforloop = "for %s in %s do"
	}
}

function decompiler.constructSyntax(syntaxrep, way)
	local style = styles[way or "basic"]
	
	local tabs = ""
	local source = {}
	
	local function emit(line)
		source[#source+1] = tabs..line
	end
	
	local function tab()
		tabs = tabs..style.tab
	end
	
	local function detab()
		tabs = tabs:sub(1, (-#style.tab)-1)
	end
	
	registerPrefix = makeRandomString()
	
	do
		local i = 0
		emit("local "..string.rep(registerPrefix.."r,", syntaxrep.info.locals):sub(1,-2):gsub("r",function() i = i+1 return "r"..(i-1) end))
	end
	
	local function decodeExpressionTargets(expression)
		if (not expression.targets) or #expression.targets == 0 then return end
		local regs = {}
		for i=1, #expression.targets do
			regs[#regs+1] = registerPrefix.."r"..expression.targets[i]
		end
		return table.concat(regs, style.comma)
	end
	
	local function encodeLuaConstant(c, q)
		if type(c) == "string" then
			local qot = string.format('%q',c):gsub("\\\n", "\\n")
			
			if q and qot:sub(2,-2) == c then
				return c, true
			end
		
			return qot
		else
			return tostring(c)
		end
	end
	
	local function formatParenthesis(dofmt, exp, ...)
		return dofmt and "("..exp..")" or exp, ...
	end
	
	local function decodeSyntaxExpression(expression, quoteless)
		local t = expression.type
			
		print("e::"..t)
		if t == "call" then
			local args = {}
			for i=1, #expression.args do
				args[i] = decodeSyntaxExpression(expression.args[i])
			end
			
			return decodeSyntaxExpression(expression.func).."("..table.concat(args,style.comma)..")"
		elseif t == "global" then
			return expression.global
		elseif t == "constant" then
			return formatParenthesis(expression.parenthesis, encodeLuaConstant(expression.constant, quoteless))
		elseif t == "register" then
			return registerPrefix.."r"..expression.register
		elseif t == "math" then
			return formatParenthesis(expression.parenthesis,
				style.operation:format(decodeSyntaxExpression(expression.lhs), expression.op, decodeSyntaxExpression(expression.rhs)))
		elseif t == "table" then
			local index, quoteless = decodeSyntaxExpression(expression.index, true)
			return decodeSyntaxExpression(expression.table)..(quoteless and "."..index or "["..index.."]")
		elseif t == "concat" then
			local concats = {}
			for i=1, #expression.vals do
				concats[i] = decodeSyntaxExpression(expression.vals[i])
			end
			return table.concat(concats, "..")
		end
	end
	
	local function decodeSyntaxExpressions(expression)
		local out = {}
		
		for i=1, #expression do
			local e = expression[i]
			local target = decodeExpressionTargets(e)
			local exp = decodeSyntaxExpression(e)
			out[#out+1] = target and target..style.equals..exp or exp
		end
		
		return out
	end
	
	local function decodeSyntaxBlock(block)
		for i=1, #block do
			local b = block[i]
			local t = b.type
		
			print(t)
		
			if t == "if" then
				local exp = decodeSyntaxExpression(b.exp)
				emit("if "..exp.." then")
				
				tab()
				decodeSyntaxBlock(b.block)
				detab()
				
				if b.elseblock then
					emit("else")
					tab()
					decodeSyntaxBlock(b.elseblock)
					detab()
				end
				
				emit("end")
			elseif t == "for" then
				local var = decodeSyntaxExpression(b.target)
				local init = decodeSyntaxExpression(b.start)
				local fin = decodeSyntaxExpression(b.finish)
				local step = decodeSyntaxExpression(b.step)
				emit(style.forloop:format(var, init, fin, step))
				
				tab()
				decodeSyntaxBlock(b.block)
				detab()
				
				emit("end")
			elseif t == "gfor" then
				local vars = {}
				for i=1, #b.vars do
					vars[i] = registerPrefix.."r"..b.vars[i]
				end
				
				local iterator = {}
				for i=b.base, b.base+2 do
					iterator[#iterator+1] = registerPrefix.."r"..i
				end
				
				emit(style.gforloop:format(table.concat(vars, style.comma), table.concat(iterator, style.comma)))
				
				tab()
				decodeSyntaxBlock(b.block)
				detab()
				
				emit("end")
			elseif t == "while" then
				local exp = decodeSyntaxExpression(b.exp)
				emit("while "..exp.." do")
				
				tab()
				decodeSyntaxBlock(b.block)
				detab()
				
				emit("end")
			elseif t == "expression" then
				if #b.exp > 0 then
					emit(table.concat(decodeSyntaxExpressions(b.exp),style.newline..tabs))
				end
			elseif t == "return" then
				if b.size == 0 then
					emit("return")
				else
					local regs = {}
					for i=b.begin, b.begin+b.size-1 do
						regs[#regs+1] = registerPrefix.."r"..i
					end
					emit("return "..table.concat(regs,style.comma))
				end
			elseif t == "break" then
				emit("break")
			end
		end
	end
	
	decodeSyntaxBlock(syntaxrep.block)
	
	return table.concat(source, style.newline)
end
