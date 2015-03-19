--executes lua 5.2 bytecode--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

local band, brshift = bit.band, bit.brshift
local tostring, unpack = tostring, unpack or table.unpack
local pack = table.pack or function(...) return {n=select("#",...),...} end

require "luavm.vmcore"
vm.lua52 = {}

local function debug(...)
	if vm.debug then
		print(...)
	end
end

local function attemptCall(v)
	if vm.typechecking then
		local t = type(v)
		if not (t == "function" or (t == "table" and getmetatable(v) and type(getmetatable(v).__call) == "function")) then
			error("attempt to call a "..t.." value")
		end
	end
	return v
end

local function attemptMetatable(v,n,typ,meta)
	if vm.typechecking then
		local t = type(v)
		if not (t == typ or (t == "table" and getmetatable(v) and type(getmetatable(v)[meta]) == "function")) then
			error("attempt to "..n.." a "..t.." value")
		end
	end
	return v
end

local function attempt(v,to,...)
	if vm.typechecking then
		local t = type(v)
		for i=1, select("#",...) do
			if t == select(i,...) then return v end
		end
		error("attempt to "..to.." a "..t.." value")
	end
	return v
end

do
	local instructionNames = {
		[0]="MOVE","LOADK","LOADKX","LOADBOOL","LOADNIL",
		"GETUPVAL","GETTABUP","GETTABLE",
		"SETTABUP","SETUPVAL","SETTABLE","NEWTABLE",
		"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
		"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
		"FORLOOP","FORPREP","TFORCALL","TFORLOOP","SETLIST","CLOSURE","VARARG","EXTRAARG"
	}

	local iABC = 0
	local iABx = 1
	local iAsBx = 2
	local iA = 3
	local iAx = 4

	local instructionFormats = {
		[0]=iABC,iABx,iA,iABC,iABC,
		iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iAsBx,iABC,iABx,iABC,iAx
	}
	
	function vm.lua52.run(chunk, args, upvals, globals, hook)
		if chunk.version ~= 0x52 then error(string.format("attempt to run %x bytecode in 52",chunk.version)) end
		local R = {}
		local top = 0
		local pc = 0
		local code = chunk.instructions
		local constants = chunk.constants
		args = args or {}
		globals = globals or _G
		upvals = upvals or {[0]=globals}
		
		for i=1,chunk.nparam do R[i-1] = args[i] top = i-1 end
	
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
			elseif format == iA then
				return opcode, band(brshift(inst,6),0xFF)
			elseif format == iAx then
				return opcode, brshift(inst,6)
			else
				error(opcode.." "..tostring(instructionNames[opcode]))
			end
		end
	
		local function getsBx(inst)
			local sBx = band(brshift(inst,14),0x3FFFF)-131071
			return sBx
		end
		
		local function getAx(inst)
			return brshift(inst,6)
		end
	
		local function RK(n)
			return n >= 256 and constants[n-256] or R[n]
		end
	
		--instruction constants--
		local MOVE = 0
		local LOADK = 1
		local LOADKX = 2
		local LOADBOOL = 3
		local LOADNIL = 4
		local GETUPVAL = 5
		local GETTABUP = 6
		local GETTABLE = 7
		local SETTABUP = 8
		local SETUPVAL = 9
		local SETTABLE = 10
		local NEWTABLE = 11
		local SELF = 12
		local ADD = 13
		local SUB = 14
		local MUL = 15
		local DIV = 16
		local MOD = 17
		local POW = 18
		local UNM = 19
		local NOT = 20
		local LEN = 21
		local CONCAT = 22
		local JMP = 23
		local EQ = 24
		local LT = 25
		local LE = 26
		local TEST = 27
		local TESTSET = 28
		local CALL = 29
		local TAILCALL = 30
		local RETURN = 31
		local FORLOOP = 32
		local FORPREP = 33
		local TFORCALL = 34
		local TFORLOOP = 35
		local SETLIST = 36
		local CLOSURE = 37
		local VARARG = 38
		local EXTRAARG = 39
	
		local ret = pack(pcall(function()
			while true do
				local o,a,b,c = decodeInstruction(code[pc])
				if vm.debug then debug(chunk.name,tostring(chunk.sourceLines[pc]),pc,instructionNames[o],a,b,c) end
				pc = pc+1
				if hook then hook(o,a,b,c,pc-1,instructionNames[o]) end
		
				if o == MOVE then
					R[a] = R[b]
					debug("Ra =",R[b])
				elseif o == LOADNIL then
					for i=a, a+b do
						R[i] = nil
						debug("R"..i,"= nil")
					end
				elseif o == LOADK then
					R[a] = constants[b]
					debug("Ra =",R[a])
					if R[a] == "START_DEBUGGING" then
						vm.debug = true
					end
				elseif o == LOADKX then
					R[a] = constants[getAx(code[pc])]
					pc = pc+1
					debug("Ra =",R[a])
				elseif o == LOADBOOL then
					R[a] = b ~= 0
					debug("Ra =",R[a])
					if c ~= 0 then
						pc = pc+1
					end
				elseif o == GETTABUP then
					R[a] = attempt(upvals[b], "index", "table", "string")[RK(c)]
					debug("Ra =",upvals[b],"[",RK(c),"]")
				elseif o == SETTABUP then
					attempt(upvals[a], "index", "table", "string")[RK(b)] = RK(c)
					debug(upvals[a],"[",RK(b),"] =",RK(c))
				elseif o == GETUPVAL then
					R[a] = upvals[b]
					debug("Ra =",upvals[b])
				elseif o == SETUPVAL then
					upvals[b] = R[a]
					debug("UVb =",R[a])
				elseif o == GETTABLE then
					R[a] = attempt(R[b], "index", "table", "string")[RK(c)]
					debug("Ra =",R[b],"[",RK(c),"]")
				elseif o == SETTABLE then
					attempt(R[a], "index", "table", "string")[RK(b)] = RK(c)
					debug(R[a],"[",RK(b),"] =",RK(c))
				elseif o == ADD then
					R[a] = attemptMetatable(RK(b), "perform arithmetic on", "number", "__add")+attemptMetatable(RK(c), "perform arithmetic on", "number", "__add")
				elseif o == SUB then
					R[a] = attemptMetatable(RK(b), "perform arithmetic on", "number", "__sub")-attemptMetatable(RK(c), "perform arithmetic on", "number", "__sub")
				elseif o == MUL then
					R[a] = attemptMetatable(RK(b), "perform arithmetic on", "number", "__mul")*attemptMetatable(RK(c), "perform arithmetic on", "number", "__mul")
				elseif o == DIV then
					R[a] = attemptMetatable(RK(b), "perform arithmetic on", "number", "__div")/attemptMetatable(RK(c), "perform arithmetic on", "number", "__div")
				elseif o == MOD then
					R[a] = attemptMetatable(RK(b), "perform arithmetic on", "number", "__mod")%attemptMetatable(RK(c), "perform arithmetic on", "number", "__mod")
				elseif o == POW then
					R[a] = attemptMetatable(RK(b), "perform arithmetic on", "number", "__pow")^attemptMetatable(RK(c), "perform arithmetic on", "number", "__pow")
				elseif o == UNM then
					R[a] = -attemptMetatable(R[b], "perform arithmetic on", "number", "__unm")
				elseif o == NOT then
					R[a] = not R[b]
				elseif o == LEN then
					R[a] = #attempt(R[b], "get length of", "string", "table")
				elseif o == CONCAT then
					local sct = {}
					for i=b, c do sct[#sct+1] = tostring(R[i]) end
					R[a] = table.concat(sct)
				elseif o == JMP then
					pc = (pc+b)
				elseif o == CALL then
					attemptCall(R[a])
					local ret
					if b == 1 then
						if c == 1 then
							R[a]()
						elseif c == 2 then
							R[a] = R[a]()
						else
							ret = {R[a]()}
							debug(ret[1], ret[2], ret[3])
					
							if c == 0 then
								for i=a, a+#ret-1 do R[i] = ret[i-a+1] end
								top = a+#ret-1
							else
								local g = 1
								for i=a, a+c-1 do R[i] = ret[g] g=g+1 end
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
							debug("RETURN VALUE",R[a])
						else
							ret = pack(R[a](unpack(R,s,e)))
							debug(ret[1], ret[2], ret[3], ret.n)
				
							if c == 0 then
								for i=1, #ret do R[a+i-1] = ret[i] end
								debug("NRET",unpack(ret))
								top = a+#ret-1
							else
								local g = 1
								for i=a, a+c-2 do R[i] = ret[g] g=g+1 end
							end
						end
					end
				elseif o == RETURN then
					local ret = {}
					local rti = 1
					if b == 0 then
						for i=a, top do ret[rti] = R[i] rti = rti+1 end
					else
						for i=a, a+b-2 do ret[rti] = R[i] rti = rti+1 end
					end
					return unpack(ret,1,rti-1)
				elseif o == TAILCALL then
					local cargs = {}
					local ai = 1
					if b == 0 then
						for i=a+1, top do cargs[ai] = R[i] ai = ai+1 end
					else
						for i=a+1, a+b-1 do cargs[ai] = R[i] ai = ai+1 end
					end
					return attemptCall(R[a])(unpack(cargs,1,ai-1))
				elseif o == VARARG then
					if b > 0 then
						local i = 1
						for n=a, a+b-2 do
							R[n] = args[i]
							i = i+1
						end
					else
						local idx = a
						for i=chunk.nparam+1, #args do
							R[idx] = args[i]
							idx = idx+1
						end
						top = idx-1
					end
				elseif o == SELF then
					debug("SELF",R[b])
					R[a+1] = R[b]
					R[a] = attempt(R[b], "index", "table", "string")[RK(c)]
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
					if (not R[a]) == (c ~= 0) then
						pc = pc+1
					else
						pc = pc+getsBx(code[pc])+1
					end
				elseif o == TESTSET then
					if (not R[b]) == (c ~= 0) then
						pc = pc+1
					else
						R[a] = R[b]
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
			
					if (step > 0 and idx <= limit) or (step < 0 and limit <= idx) then
						pc = pc+b
						R[a+3] = R[a]
					end
				elseif o == TFORCALL then
					local ret = {R[a](R[a+1],R[a+2])}
					local i = 1
					for n=a+3, a+2+c do R[n] = ret[i] i=i+1 end
					
					o, a, b = decodeInstruction(code[pc])
					pc = pc+1
					if R[a+1] ~= nil then
						R[a] = R[a+1]
						pc = pc+b
					end
				elseif o == TFORLOOP then
					if R[a+1] ~= nil then
						R[a] = R[a+1]
						pc = pc+b
					end
				elseif o == NEWTABLE then
					R[a] = {}
				elseif o == SETLIST then
					if b > 0 then
						for i=1, b do
							R[a][((c-1)*50)+i] = R[a+i]
						end
					else
						for i=1, top-a do
							R[a][((c-1)*50)+i] = R[a+i]
						end
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
						return vm.lua52.run(proto, pack(...), upvalues, globals, hook)
					end
					for i, uv in pairs(proto.upvalues) do
						debug("UPVALUE",proto.upvaluesDebug[i],i,uv.idx,uv.instack)
						if uv.instack > 0 then
							upvaldef[i] = {type=0,reg=uv.idx}
							openUpvalues[uv.idx] = upvaldef[i]
						else
							upvaldef[i] = {type=1,reg=uv.idx}
						end
					end
				elseif o == EXTRAARG then
					error("Not supposed to hit EXTRAARG")
				else
					error("Unknown opcode!")
				end
			end
		end))
		if not ret[1] then
			error(tostring(ret[2]).."\n"..tostring(chunk.name).." at pc "..(pc-1).." line "..tostring(chunk.sourceLines[pc-1]),0)
		else
			return unpack(ret,2,ret.n)
		end
	end
end
