--dynamically recompiles lua 5.1 bytecode, (basically a decompiler, a prettier decompiler will come later)--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

dynarec = {}
dynarec.debug = true
dynarec.attemptExpressionOptimization = false

local function debug(...)
	if dynarec.debug then
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

function dynarec.compile(chunk, hookemit)
	local output = {}
	local outputPCMap = {}
	
	local top = 0
	local pc = 0
	local code
	local constants
	--for i=1,chunk.nparam do R[i-1] = args[i] top = i-1 end
	local registerPrefix, oldRegisterPrefix
	local upvals
	local tabs = 0
	local alreadyFound = {}
	local lastExpressions = {}
	local lastExpressionEmit = {}
	local blockLimit
	local blockLimitStack = {}
	
	local function makeRandomString()
		local s = {}
		for i=1, 5 do
			s[i] = string.char(math.random(97,122))
		end
		s[6] = "_"
		return table.concat(s)
	end
	
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
	
	local function RK(n)
		return n >= 256 and constants[n-256] or R[n]
	end
	
	local function formatConstant(constant)
		if type(constant) == "string" then
			return string.format("%q",constant):gsub("\\\n","\\n")
		end
		return tostring(constant)
	end
	
	local function peek(...)
		local t = {...}
		for i=1, #t do
			local p = code[i+pc-1]
			if p and t[i] and t[i] ~= band(p,0x3F) then
				return false
			end
		end
		return true
	end
	
	local function find(...)
		local t = {...}
		local ofs = 0
		while code[pc-1+ofs] do
			local c = false
			for i=1, #t do
				local p = code[i+pc-2+ofs]
				if p and t[i] and t[i] ~= band(p,0x3F) then
					c = true
					break
				end
			end
			if not c then return pc-1+ofs end
			ofs = ofs+1
		end
		return false
	end
	
	local function emit(line)
		output[#output+1] = string.rep("\t",tabs)..line
		outputPCMap[#outputPCMap+1] = pc-1
		--print(output[#output])
	end
	
	local function emitf(fmt,...)
		output[#output+1] = string.rep("\t",tabs)..fmt:format(...)
		outputPCMap[#outputPCMap+1] = pc-1
		--print(output[#output])
	end
	
	local function unemit(pc)
		local rem = {}
		for i=1, #output do
			if outputPCMap[i] == pc then
				rem[#rem+1] = i
			end
		end
		
		for i=1, #rem do
			table.remove(outputPCMap,rem[i])
			table.remove(output,rem[i])
		end
	end
	
	local function unemitRange(s,e)
		local rem = {}
		for i=1, #output do
			if outputPCMap[i] >= s and outputPCMap[i] <= e then
				rem[#rem+1] = i
			end
		end
		
		for i=1, #rem do
			table.remove(outputPCMap,rem[i])
			table.remove(output,rem[i])
		end
	end
	
	local function findAndUnemit(str)
		for i=#output, 1, -1 do
			if output[i] == str then
				table.remove(output, i)
				table.remove(outputPCMap, i)
				break
			end
		end
	end
	
	local function clearExpressions()
		for i, v in pairs(lastExpressions) do
			lastExpressions[i] = nil
			lastExpressionEmit[i] = nil
		end
	end
	
	local function pushBlockLimit(pc)
		blockLimitStack[#blockLimitStack+1] = blockLimit
		blockLimit = pc
	end
	
	local function popBlockLimit()
		blockLimit = blockLimitStack[#blockLimitStack]
		blockLimitStack[#blockLimitStack] = nil
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
	
	local operatorExpression = {
		[EQ] = "==",
		[LT] = "<",
		[LE] = "<=",
	}
	
	local function nextInst(p)
		local cod = code[p or pc]
		if not cod then return end
		local o,a,b,c = decodeInstruction(cod)
		if dynarec.debug then debug(p or pc,instructionNames[o],a,b,c) end
		if not p then pc = pc+1 end
		return o,a,b,c
	end
	
	local function lookForJump(to,af)
		--looks into the future for a jump back to here--
		local i = 0
		while true do
			local c = code[i+pc-1]
			if not c then break end
			if band(c,0x3F) == JMP then
				local o,a,b,c = decodeInstruction(c)
				print(i+pc+b,to)
				if i+pc+b == to then
					if not alreadyFound[i+pc+b] then
						if not af then
							alreadyFound[i+pc+b] = true
						end
						return i+pc-1
					end
				end
			end
			i = i+1
		end
		return false
	end
	
	local generateChunk
	
	local expressionDefs = {
		[MOVE] = {"@RB","A"},
		[LOADK] = {"@KB","A"},
		[GETGLOBAL] = {"_G[@KB]","A"},
		[GETUPVAL] = {"@UB","A"},
		[ADD] = {"(@RKB+@RKC)","A"},
		[SUB] = {"(@RKB-@RKC)","A"},
		[MUL] = {"(@RKB*@RKC)","A"},
		[DIV] = {"(@RKB/@RKC)","A"},
		[MOD] = {"(@RKB%@RKC)","A"},
		[POW] = {"(@RKB^@RKC)","A"},
		[UNM] = {"(-%RC)","A"},
		[NOT] = {"(not %RC)","A"},
		[LEN] = {"(#%RC)","A"},
		[CALL] = function(o,a,b,c)
			--dynamically generate an exp def--
			local expdef = {}
			expdef[#expdef+1] = "|R"..a.."|("
			if c == 1 then
				if b > 1 then
					for i=a+1, a+b-1 do
						expdef[#expdef+1] = "|R"..i.."|"
						if i ~= a+b-1 then
							expdef[#expdef+1] = ","
						end
					end
				else
					error("VARARG FUNCTION?!")
				end
			else
				error("I DON'T HAVE RETURN SHIT YET")
			end
			expdef[#expdef+1] = ")"
			return table.concat(expdef),nil
		end
	}
	
	local function generateExpression(s,e)
		--from s to e, generate an expression--
		local i = s
		local expr = {}
		local regval = {}
		local setAt = {}
		local usedAt = {}
		local expParts = {}
		local toemit = {}
		--local dependsOn = {}
		--local hasDependency = {}
		for i=-1, chunk.maxStack do
			regval[i] = registerPrefix.."r"..i
			--dependsOn[i] = {}
			--hasDependency[i] = {}
			setAt[i] = {}
			usedAt[i] = {}
		end
		local function use(r)
			print("Register",r,"is used at",i)
			usedAt[r][i] = true
		end
		local function set(r)
			print("Register",r,"is set at",i)
			setAt[r][i] = true
		end
		local function isRegUsedAfter(r,pc)
			for i, v in pairs(usedAt[r]) do
				if i > pc then
					return true
				end
			end
			
			for i, v in pairs(setAt[r]) do
				if i > pc and not usedAt[r][i] then
					return false
				end
			end
			return false
		end
		local function getLastUseIn(r,s,e)
			local lastpc = s
			for i, v in pairs(usedAt[r]) do
				if i > s and i < e then
					lastpc = math.max(lastpc,i)
				end
			end
			return lastpc
		end
		local function getFirstUseBefore(r,pc)
			local lastpc = -1
			for i, v in pairs(usedAt[r]) do print("UA",r,i) end
			for i, v in pairs(setAt[r]) do print("SA",r,i) end
			for i, v in pairs(setAt[r]) do
				if i < pc then
					if not usedAt[r][i] then
						lastpc = i
					end
				else
					break
				end
			end
			if lastpc == -1 then return end
			return lastpc
		end
		local lastreg
		while i <= e do
			local o,a,b,c = nextInst(i)
			lastreg = a --an instruction can change this if required
			local expdef,ret = expressionDefs[o]
			if type(expdef) == "function" then
				expdef,ret = expdef(o,a,b,c)
			else
				ret,expdef = expdef[2],expdef[1]
			end
			if ret == "A" then ret = a elseif ret == "B" then ret = b elseif ret == "C" then ret = c end
			--RK: (b >= 256 and formatConstant(constants[b-256]) or use(b))
			--R: use(b)
			--K: formatConstant(constants[b])
			local expPart = {o=o,a=a,b=b,c=c,ret=ret,pc=i}
			expParts[i] = expPart
			if expdef then
				expPart.expdef = expdef
				expPart.preprocessedExpdef = expdef:gsub("@(R?K?)([BC])",function(typ, reg)
					if reg == "A" then reg = a elseif reg == "B" then reg = b else reg = c end
					if typ == "R" then
						return "|R"..reg.."|"
					elseif typ == "K" then
						return formatConstant(constants[reg])
					elseif typ == "RK" then
						if reg >= 256 then
							return formatConstant(constants[reg-256])
						else
							return "|R"..reg.."|"
						end
					end
				end)
				for usedreg in expPart.preprocessedExpdef:gmatch("|R(%d+)|") do
					use(tonumber(usedreg))
				end
				if ret then
					set(ret)
				end
				print(expPart.preprocessedExpdef)
			--[[elseif o == CALL then
				local func = use(a)
			
				local args = ""
				if c == 1 then
					lastreg = -1
					
					if b > 1 then
						for i=a+1, a+b-1 do
							args = args..use(i)..","
						end
						args = args:sub(1,-2)
					else
						error("VARARG FUNCTION?!")
					end
					regval[-1] = func.."("..args..")"
					break
				else
					error("I DON'T HAVE RETURN SHIT YET")
				end]]
			else
				error("Unknown expression opcode")
			end
			i = i+1
		end
		--now, go through expdefs backwards--
		i = i-1
		local function processExpPart(expPart)
			print("processExpPart",expPart.pc, expPart.inlined and "already inlined" or "not inlined")
			if not expPart.inlined then
				return expPart.preprocessedExpdef:gsub("|R(%d+)|", function(r)
					if dynarec.attemptExpressionOptimization then
						r = tonumber(r)
						local fu = getFirstUseBefore(r,expPart.pc)
						print("First usage of r"..r.." before "..expPart.pc..":",fu)
						local lu = getLastUseIn(r,fu,expPart.pc)
						print("Last usage of r"..r.." before "..expPart.pc..":",lu)
						local p = processExpPart(expParts[lu])
						expParts[lu].inlined = true
						return p
					else
						return registerPrefix.."r"..r
					end
				end)
			end
		end
		while i >= s do
			--go through all the usages at this point--
			local expPart = expParts[i]
			local e = processExpPart(expPart)
			if e then
				if expPart.ret then
					regval[expPart.ret] = e
					table.insert(toemit,1,registerPrefix.."r"..expPart.ret.." = "..e)
				else
					table.insert(toemit,1,e)
				end
			end
			i = i-1
		end
		return regval[lastreg],regval,usedAt,lastreg,i,toemit
	end
	
	local function generateInstruction(o,a,b,c)
		local fj = lookForJump(pc-1)
		if fj then
			print("FOUND FUTURE JUMP")
			local opc = pc
			local fjo,fja,fjb,fjc = nextInst(fj)
			local jo,ja,jb,jc
			local to,ta,tb,tc
			--find test jump combo--
			local tj = find(TEST, JMP)
			local cond = false
			if not tj then
				cond = true
				tj = find(LT,JMP)
				if not tj then
					tj = find(LE,JMP)
					if not tj then
						tj = find(EQ,JUMP)
					end
				end
			end
			if tj then
				--read the jump, verify that it jumps directly after fj--
				to,ta,tb,tc = nextInst(tj)
				jo,ja,jb,jc = nextInst(tj+1)
				if tj+2+jb == fj+1 then
					print("Jump valid")
				else
					tj = nil
					print("Jump invalid")
				end
			end
			if tj then
				local expr,rv = generateExpression(opc-1, tj-1)
				if cond then
					emitf("while%s %s%s%s do",a == 1 and " not" or "", b > 255 and formatConstant(constants[b-256]) or rv[b],operatorExpression[to], c > 255 and formatConstant(constants[c-256]) or rv[c])
					clearExpressions()
					tabs = tabs+1
					pc = tj+2
					pushBlockLimit(fj)
					while pc < fj do
						generateInstruction(nextInst())
					end
					popBlockLimit()
					pc = pc+1
					tabs = tabs-1
					clearExpressions()
					emit("end")
				else
					emitf("while%s %s do",c == 1 and " not" or "",rv[a])
					clearExpressions()
					tabs = tabs+1
					pc = tj+2
					pushBlockLimit(fj)
					while pc < fj do
						generateInstruction(nextInst())
					end
					popBlockLimit()
					pc = pc+1
					tabs = tabs-1
					clearExpressions()
					emit("end")
				end
			else
				--if it doesn't (or if tj is nil) generate a while true do loop (lua does loop optimization)--
				emit("while true do")
				clearExpressions()
				tabs = tabs+1
				pc = pc-1
				pushBlockLimit(fj)
				while pc < fj do
					generateInstruction(nextInst())
				end
				popBlockLimit()
				pc = pc+1
				tabs = tabs-1
				clearExpressions()
				emit("end")
			end
		--[[elseif o == MOVE then
			emitf("%sr%d=%sr%d",registerPrefix,a,registerPrefix,b)]]
		elseif o == LOADNIL then
			local i = a
			emitf("%s=nil",string.rep(registerPrefix.."r,",a-c):sub(1,-2):gsub("r",function() i = i+1 return "r"..(i-1) end))
		--[[elseif o == LOADK then
			emitf("%sr%d=%s",registerPrefix,a,formatConstant(constants[b]))
		elseif o == ins.LOADBOOL then
			R[a] = b ~= 0
			if c ~= 0 then
				pc = pc+1
			end]]
		--[[elseif  then
			lastExpression = "_G["..formatConstant(constants[b]).."]"
			emitf("%sr%d=_%s[%s]",registerPrefix,a,lastExpression)]]
		elseif o == SETGLOBAL then
			--unemitRange(lastExpressionRange[1],lastExpressionRange[2])
			emitf("_%s[%s]=%s","G",formatConstant(constants[b]),lastExpressions[a] or registerPrefix.."r"..a)
			if lastExpressions[a] then
				findAndUnemit(lastExpressionEmit[a])
			end
		elseif o == TEST and peek(JMP) then
			--either an if-elseif-else statement or an and-or chain
			--either one can go fuck themselves
			--TODO: generateExpression
			local jo,ja,jb,jc = nextInst()
			local jto,jta,jtb,jtc = nextInst(pc+jb-2)
			if jto == TEST and jta == a and jtc ~= c then
				debug("and-or statement")
				emitf("if%s %sr%d then",c == 1 and " not" or "",registerPrefix,a)
				clearExpressions()
				tabs = tabs+1
				--emit sucess opcodes--
				local to = pc+jb-2
				while pc < to do
					generateInstruction(nextInst())
				end
				tabs = tabs-1
				clearExpressions()
				emit("else")
				clearExpressions()
				tabs = tabs+1
				pc = pc+2
				local to = pc+jb
				pushBlockLimit(to)
				while pc < to do
					generateInstruction(nextInst())
				end
				popBlockLimit()
				tabs = tabs-1
				clearExpressions()
				emit("end")
			else
				debug("if statement")
				--unemitRange(lastExpressionRange[1],lastExpressionRange[2])
				emitf("if%s %s then",c == 1 and " not" or "",lastExpressions[a] or registerPrefix.."r"..a)
				if lastExpressions[a] then
					findAndUnemit(lastExpressionEmit[a])
				end
				clearExpressions()
				tabs = tabs+1
				--emit sucess opcodes--
				local to = pc+jb-1
				pushBlockLimit(to)
				while pc < to do
					generateInstruction(nextInst())
				end
				popBlockLimit()
				jo,ja,jb,jc = nextInst()
				if jo == JMP then
					tabs = tabs-1
					debug("else statement")
					emit("else")
					clearExpressions()
					tabs = tabs+1
					--emit failure opcodes--
					local to = pc+jb
					pushBlockLimit(to)
					while pc < to do
						generateInstruction(nextInst())
					end
					popBlockLimit()
				else
					pc = pc-1
					generateInstruction(nextInst())
				end
				tabs = tabs-1
				clearExpressions()
				emit("end")
			end
		elseif o == SETUPVAL then
			emitf("%s=%sr%d",upvals[b],lastExpressions[a] or registerPrefix.."r"..a)
			if lastExpressions[a] then
				findAndUnemit(lastExpressionEmit[a])
			end
		elseif o == GETTABLE then
			R[a] = R[b][RK(c)]
		elseif o == SETTABLE then
			R[a][RK(b)] = RK(c)
		elseif o == MOVE or o == ADD or o == SUB or o == MUL or o == DIV or o == MOD or o == POW or o == GETGLOBAL or o == LEN or o == LOADK or o == NOT or o == UNM or o == CALL then
			--R[a] = RK(b)+RK(c)
			--start set routine--
			--find all arithmetic opcodes that use the same destination register to enable operation chaining--
			local cpc = pc
			while true do
				if blockLimit and cpc >= blockLimit then break end
				local no,na,nb,nc = nextInst(cpc)
				if lookForJump(cpc,true) then print("breaking, has jump to") break end
				if no == MOVE or no == ADD or no == SUB or no == MUL or no == DIV or no == MOD or no == POW or no == GETGLOBAL or no == LEN or no == LOADK or no == NOT or no == UNM or no == CALL then
					cpc = cpc+1
				else
					break
				end
			end
			local last,rv,use,lastreg,lastpc,toemit = generateExpression(pc-1,cpc-1)
			for i, v in pairs(toemit) do
				lastExpressions[i] = rv[i]
				emit(v)
				lastExpressionEmit[i] = output[#output]
			end
			--emitf("%sr%d=%s",registerPrefix,a,lastExpression)
			--lastExpressionRange[1] = pc-1
			--lastExpressionRange[2] = cpc-1
			--lastExpressionRegister = a
			pc = cpc
		--[[elseif o == CONCAT then
			local sct = {}
			for i=b, c do sct[#sct+1] = tostring(R[i]) end
			R[a] = table.concat(sct)]]
		--elseif o == CALL then
			
			--[[local ret
			if b == 1 then
				if c == 1 then
					R[a]()
				elseif c == 2 then
					R[a] = R[a]()
				else
					ret = {R[a]()}
				
					if c == 0 then
						for i=a, a+#ret-1 do R[i] = ret[i-a+1] top = i end
					else
						local g = 1
						for i=a, a+c-2 do R[i] = ret[g] g=g+1 end
					end
				end
			else
				--local cargs = {}
				local s,e
				if b == 0 then
					s,e=a+1,top
					--for i=a+2, chunk.maxStack-2 do cargs[#cargs+1] = R[i] end
				else
					s,e=a+1,a+b-1
					--for i=a+1, a+b-1 do cargs[#cargs+1] = R[i] end
				end
				if c == 1 then
					R[a](unpack(R,s,e))
				elseif c == 2 then
					R[a] = R[a](unpack(R,s,e))
				else
					ret = {R[a](unpack(R,s,e))}
			
					if c == 0 then
						for i=a, a+#ret-1 do R[i] = ret[i-a+1] top = i end
					else
						local g = 1
						for i=a, a+c-2 do R[i] = ret[g] g=g+1 end
					end
				end
			end]]
		--[[elseif o == RETURN then
			local ret = {}
			for i=a, a+b-2 do ret[#ret+1] = R[i] end
			return unpack(ret)
		elseif o == TAILCALL then
			local cargs = {}
			if b == 0 then
				for i=a+2, top do cargs[#cargs+1] = R[i] end
			else
				for i=a+1, a+b-1 do cargs[#cargs+1] = R[i] end
			end
			return R[a](unpack(cargs))
		elseif o == VARARG then
			if b > 0 then
				local i = 1
				for n=a, a+b-1 do
					R[n] = args[i]
					i = i+1
				end
			else
				for i=chunk.nparam+1, #args do
					R[a+i-1] = args[i]
					top = a+i-1
				end
			end
		elseif o == SELF then
			R[a+1] = R[b]
			R[a] = R[b][RK(c)]
		elseif o == EQ then
			if (RK(b) == RK(c)) == (a ~= 0) then
				pc = pc+getsBx(code[pc])+1
			else
				pc = pc+1
			end
		elseif o == LT then
			if (RK(b) < RK(c)) == (a ~= 0) then
				pc = pc+getsBx(code[pc])+1
			else
				pc = pc+1
			end
		elseif o == LE then
			if (RK(b) <= RK(c)) == (a ~= 0) then
				pc = pc+getsBx(code[pc])+1
			else
				pc = pc+1
			end
		elseif o == TEST then
			if (not R[a]) ~= (c ~= 0) then
				pc = pc+getsBx(code[pc])+1
			else
				pc = pc+1
			end
		elseif o == TESTSET then
			if (not R[b]) ~= (c ~= 0) then
				R[a] = R[b]
				pc = pc+1
			else
				pc = pc+getsBx(code[pc])+1
			end
		elseif o == FORPREP then
			R[a] = R[a]-R[a+2]
			pc = pc+b
		elseif o == FORLOOP then
			local step = R[a+2]
			R[a] = R[a]+step
			local idx = R[a]
			local limit = R[a+1]
		
			if (step < 0 and limit <= idx or idx <= limit) then
				pc = pc+b
				R[a+3] = R[a]
			end
		elseif o == TFORLOOP then
			local ret = {R[a](R[a+1],R[a+2])}
			local i = 1
			for n=a+3, a+3+b do R[n] = ret[i] i=i+1 end
			if R[a+3] ~= nil then
				R[a+2] = R[a+3]
			else
				pc = pc+1
			end
		elseif o == NEWTABLE then
			R[a] = {}
		elseif o == SETLIST then
			for i=1, b do
				R[a][((c-1)*50)+i] = R[a+i]
			end
		elseif o == CLOSURE then
			local proto = chunk.functionPrototypes[b]
			local upvaldef = {}
			local upvalues = setmetatable({},{__index=function(_,i)
				if not upvaldef[i] then error("unknown upvalue") end
				local uvd = upvaldef[i]
				if uvd.type == 0 then --local upvalue
					return R[uvd.reg]
				elseif uvd.type == 1 then
					return upvals[uvd.reg]
				else
					return uvd.storage
				end
			end,__newindex=function(_,i,v)
				if not upvaldef[i] then error("unknown upvalue") end
				local uvd = upvaldef[i]
				if uvd.type == 0 then --local upvalue
					R[uvd.reg] = v
				elseif uvd.type == 1 then
					upvals[uvd.reg] = v
				else
					uvd.storage = v
				end
			end})
			R[a] = function(...)
				return vm.run(proto, {...}, upvalues, globals, hook)
			end
			for i=1, proto.nupval do
				local o,a,b,c = decodeInstruction(code[pc+i-1])
				debug(pc+i,"PSD",instructionNames[o],a,b,c)
				if o == MOVE then
					upvaldef[i-1] = openUpvalues[b] or {type=0,reg=b}
					openUpvalues[b] = upvaldef[i-1]
				elseif o == GETUPVAL then
					upvaldef[i-1] = {type=1,reg=b}
				else
					error("unknown upvalue psuedop")
				end
			end
			pc = pc+proto.nupval
		elseif o == CLOSE then
			for i=a, chunk.maxStack do
				if openUpvalues[i] then
					local ouv = openUpvalues[i]
					ouv.type = 2 --closed
					ouv.storage = R[ouv.reg]
					openUpvalues[i] = nil
				end
			end]]
		elseif o == nil then
			error("INSTRUCTION IS NIL")
		else
			print("Unknown opcode!")
		end
	end
	
	function generateChunk(chunk,uv)
		local oc = code
		local occ = constants
		local opc = pc
		local ouv = upvals
		
		if upvals and uv then
			upvals = setmetatable(uv,{__index = ouv})
		end
		
		oldRegisterPrefix = registerPrefix
		registerPrefix = makeRandomString()
		
		code = chunk.instructions
		constants = chunk.constants
		pc = 0
		
		do
			local i = 0
			emit("local "..string.rep(registerPrefix.."r,", chunk.maxStack):sub(1,-2):gsub("r",function() i = i+1 return "r"..(i-1) end))
		end
		while pc < #code do
			local o,a,b,c = nextInst()
			if not o then break end
			generateInstruction(o,a,b,c)
		end
		
		code = oc
		constants = occ
		pc = opc
		if uv then
			setmetatable(uv,{})
			upvals = ouv
		end
	end
	
	generateChunk(chunk)
	
	return output
end
