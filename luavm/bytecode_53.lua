--patches for bytecode.lua for lua 5.3 (bitops, lua 5.3 support, string.unpack)--

local function debug(...)
	if bytecode.debug then
		print(...)
	end
end

bytecode.lua53 = {}
bytecode[0x53] = bytecode.lua53

do
	local instructionNames = {
		[0]="MOVE","LOADK","LOADKX","LOADBOOL","LOADNIL",
		"GETUPVAL","GETTABUP","GETTABLE",
		"SETTABUP","SETUPVAL","SETTABLE","NEWTABLE","SELF",
		"ADD","SUB","MUL","MOD","POW","DIV","IDIV","BAND","BOR","BXOR","SHL","SHR","UNM","BNOT","NOT","LEN","CONCAT",
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
		iABC,iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iAsBx,iABC,iABx,iABC,iAx
	}
	
	local ins = {}
	for i, v in pairs(instructionNames) do ins[v] = i end
	
	bytecode.lua53.instructionNames = instructionNames
	bytecode.lua53.instructions = ins
	bytecode.lua53.defaultReturn = ins.RETURN | 0 | 1 << 23 | 0

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
	local MOD = 16
	local POW = 17
	local DIV = 18
	local IDIV = 19
	local BAND = 20
	local BOR = 21
	local BXOR = 22
	local SHL = 23
	local SHR = 24
	local UNM = 25
	local BNOT = 26
	local NOT = 27
	local LEN = 28
	local CONCAT = 29
	local JMP = 30
	local EQ = 31
	local LT = 32
	local LE = 33
	local TEST = 34
	local TESTSET = 35
	local CALL = 36
	local TAILCALL = 37
	local RETURN = 38
	local FORLOOP = 39
	local FORPREP = 40
	local TFORCALL = 41
	local TFORLOOP = 42
	local SETLIST = 43
	local CLOSURE = 44
	local VARARG = 45
	local EXTRAARG = 46

	function bytecode.lua53.encode(inst,a,b,c)
		inst = type(inst) == "string" and ins[inst] or inst
		local format = instructionFormats[inst]
		return
			format == iABC and
			inst | ((a & 0xFF) << 6) | ((b & 0x1FF) << 23) | ((c & 0x1FF) << 14) or
			format == iABx and
			inst | ((a & 0xFF) << 6) | ((b & 0x3FFFF) << 14) or
			inst | ((a & 0xFF) << 6) | (((b + 131071) & 0x3FFFF) << 14)
	end

	function bytecode.lua53.decode(inst)
		local opcode = inst & 0x3F
		local format = instructionFormats[opcode]
		if format == iABC then
			return opcode, (inst >> 6) & 0xFF, (inst >> 23) & 0x1FF, (inst >> 14) & 0x1FF
		elseif format == iABx then
			return opcode, (inst >> 6) & 0xFF, (inst >> 14) & 0x3FFFF
		elseif format == iAsBx then
			return opcode, (inst >> 6) & 0xFF, ((inst >> 14) & 0x3FFFF)-131071
		else
			error(opcode.." "..format)
		end
	end
	
	bytecode.lua53.patcher = {}

	local function patchJumpsAndAdd(bc, pc, op)
		for i=0, #bc.instructions do
			local o,a,b,c = bytecode.lua53.decode(bc.instructions[i])
			if o == LOADBOOL then
				if c ~= 0 then
					if i+1 == pc then
						error("TODO: Patch LOADBOOL")
					end
				end
			elseif o == JMP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == TEST then
				if i+1 == pc then
					error("TODO: Patch TEST")
				end
			elseif o == TESTSET then
				if i+1 == pc then
					error("TODO: Patch TESTSET")
				end
			elseif o == FORLOOP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == FORPREP then
				if (i < pc and i+b+1 > pc) then
					b = b+1 --since this gets shifted forward...
				elseif (i > pc and i+b+1 <= pc) then
					b = b-1 --since this gets shifted backward...
				end
			elseif o == TFORPREP then
				if i+1 == pc then
					error("TODO: Patch TFORPREP")
				end
			end
			bc.instructions[i] = bytecode.lua53.encode(o,a,b,c)
			print(i,bc.instructions[i])
		end
	
		for i=#bc.instructions, pc, -1 do
			bc.instructions[i+1] = bc.instructions[i]
			bc.sourceLines[i+1] = bc.sourceLines[i]
		end
		bc.instructions[pc] = op
	end

	function bytecode.lua53.patcher.insert(bc, pc, inst)
		--insert commands, fix jump targets--
		patchJumpsAndAdd(bc, pc, inst)
	end

	function bytecode.lua53.patcher.replace(bc, pc, inst)
		bc.instructions[pc] = inst
	end

	function bytecode.lua53.patcher.find(bc, pc, o)
		if type(o) == "string" then
			o = ins[o]
		end
		
		for i=pc+1, #bc.instructions do
			local no = bytecode.lua53.decode(bc.instructions[i])
			if no == o then
				return i
			end
		end
	end

	function bytecode.lua53.patcher.addConstant(bc, const)
		--try find constant...---
		for i, v in pairs(bc.constants) do if v == const then return i end end
		bc.constants[#bc.constants+1] = const
		return #bc.constants
	end
end

function bytecode.load(bc)
	debug("Loading binary chunk with size "..#bc.."b")
	local idx = 1
	local integer, size_t, number
	local bigEndian = false
	local version
	
	local function u1()
		idx = idx+1
		return bc:byte(idx-1)
	end
	local function u2()
		local a,b = bc:byte(idx,idx+1)
		idx = idx+2
		return bigEndian and (a<<8)+b or (b<<8)+a
	end
	local function u4()
		local a,b,c,d = bc:byte(idx,idx+3)
		idx = idx+4
		return bigEndian and (a<<24)+(b<<16)+(c<<8)+d or (d<<24)+(c<<16)+(b<<8)+a
	end
	local function u8()
		local s = string.unpack(bigEndian and ">i8" or "i8", bc:sub(idx,idx+7))
		idx = idx+8
		return s
	end
	local function float(f)
		local x = bc:sub(idx,idx+3)
		idx = idx+4
		return string.unpack(bigEndian and ">f" or "f",x)
	end
	local function double(f)
		local x = bc:sub(idx,idx+7)
		idx = idx+8
		return string.unpack(bigEndian and ">d" or "d",x)
	end
	local function ub(n)
		idx = idx+n
		return bc:sub(idx-n,idx-1)
	end
	local function us()
		if version == 0x53 then
			local hdr = u1()
			if hdr < 0xFF then
				return ub(hdr-1)
			else
				local size = size_t()
				return ub(size-1)
			end
		else
			local size = size_t()
			return ub(size):sub(1,-2)
		end
	end
	
	--verify header--
	assert(ub(4) == "\27Lua", "invalid header signature")
	version = u1()
	assert(version == 0x51 or version == 0x52 or version == 0x53, ("version not supported: Lua%X"):format(version))
	do
		local fmtver = u1()
		assert(fmtver == 0 or fmtver == 255, "unknown format version "..fmtver)
	end
	
	if version == 0x53 then
		ub(6)
	end
	
	local types = ub(version == 0x53 and 5 or 6)
	
	bigEndian = version < 0x53 and types:byte(1) ~= 1
	integer = types:byte(version == 0x53 and 1 or 2) == 8 and u8 or u4
	size_t = types:byte(version == 0x53 and 2 or 3) == 8 and u8 or u4
	number = types:byte(version == 0x53 and 4 or 5) == 8 and double or float
	
	if version == 0x52 then
		ub(6)
	elseif version == 0x53 then
		local int = u8()
		bigEndian = int ~= 0x5678
		ub(8)
	end
	
	debug("header is legit")
	
	local sizeupvalues
	if version == 0x53 then
		sizeupvalues = u1()
	end
	
	local function chunk()
		local function instructionList()
			local instructions = {}
			local count = u4()
			print(count)
			for i=1, count do
				instructions[i-1] = u4()
			end
			return instructions
		end
		
		local function constantList()
			local constants = {}
			for i=1, u4() do
				local type, sub = u1()
				if version < 0x53 then
					if type == 0 then
						constants[i-1] = nil
					elseif type == 1 then
						constants[i-1] = u1() > 0
					elseif type == 3 then
						constants[i-1] = number(true)
					elseif type == 4 then
						constants[i-1] = us()
					else
						error("Type: "..type)
					end
				else
					sub = (type & 0xF0) >> 4
					type = type & 0xF
					
					if type == 0 then
						constants[i-1] = nil
					elseif type == 1 then
						constants[i-1] = u1() > 0
					elseif type == 3 then
						if sub == 0 then
							constants[i-1] = number()
						else
							constants[i-1] = integer()
						end
					elseif type == 4 then
						constants[i-1] = us()
					else
						error("Type: "..type.." "..sub)
					end
				end
				debug("Constant "..(i-1)..": "..tostring(constants[i-1]), type, sub)
			end
			return constants
		end
		
		local function functionPrototypeList()
			local functionPrototypes = {}
			for i=1, u4() do
				functionPrototypes[i-1] = chunk()
			end
			return functionPrototypes
		end
		
		local function sourceLineList()
			local sourceLines = {}
			for i=1, u4() do
				sourceLines[i-1] = integer()
			end
			return sourceLines
		end
		
		local function localList()
			local locals = {}
			for i=1, u4() do
				locals[i-1] = {
					name = us(),
					startpc = integer(),
					endpc = integer()
				}
			end
			return locals
		end
		
		local function upvalueList()
			local upvalues = {}
			for i=1, u4() do
				upvalues[i-1] = us()
			end
			return upvalues
		end
		
		--extract an lua chunk into a table--
		local c = {version = version, sizeupvalues=sizeupvalues}
		if version == 0x51 then
			c.name = us()
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nupval = u1()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.functionPrototypes = functionPrototypeList()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvalues = upvalueList()
		elseif version == 0x52 or version == 0x53 then
			local function upvalueDefinitionList()
				local upvalues = {}
				for i=1, u4() do
					upvalues[i-1] = {instack=u1(),idx=u1()}
					debug(("upvalue %d instack=%d idx=%d"):format(i-1,upvalues[i-1].instack,upvalues[i-1].idx))
				end
				return upvalues
			end
			if version == 0x53 then
				c.name = us()
			end
			c.lineDefined = u4()
			c.lastLineDefined = u4()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			print(c.lineDefined)
			c.instructions = instructionList()
			c.constants = constantList()
			
			if version < 0x53 then
				c.functionPrototypes = functionPrototypeList()
				c.upvalues = upvalueDefinitionList()
			else
				c.upvalues = upvalueDefinitionList()
				c.functionPrototypes = functionPrototypeList()
			end
			
			if version == 0x52 then
				c.name = us()
			end
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvaluesDebug = upvalueList()
		else
			error("Unknown lua version.")
		end
		return c
	end
	return chunk()
end

local supportedTypes = string.dump(function() end):sub(12,17)
local header = string.dump(function() end):sub(1,0x21)
function bytecode.save(chunk)
	assert(chunk.version == 0x53, "Cannot save Lua versions that are not 5.3! Sorry!")
	local bc = {header}
	
	local function w1(b)
		bc[#bc+1] = string.char(b)
	end
	
	local function w2(s)
		bc[#bc+1] = string.pack("I2", s)
	end
	
	local function w4(s)
		bc[#bc+1] = string.pack("I4", s)
	end
	
	local function double(x)
		bc[#bc+1] = string.pack("d", x)
	end
	
	local function w8(s)
		bc[#bc+1] = string.pack("I8", s)
	end
	
	local integer = supportedTypes:byte(1) == 8 and w8 or w4
	local size_t = supportedTypes:byte(2) == 8 and w8 or w4
	
	local function ws(str)
		local len = #str+1
		if len < 0xFF then
			w1(len)
		else
			w1(0xFF)
			size_t(len)
		end
		bc[#bc+1] = str
	end
	
	local function len(t)
		local n = 0
		for i, v in pairs(t) do n = n+1 end
		return n
	end
	
	local function writeChunk(chunk)
		ws(chunk.name)
		integer(chunk.lineDefined)
		integer(chunk.lastLineDefined)
		w1(chunk.nparam)
		w1(chunk.isvararg)
		w1(chunk.maxStack)
		
		integer(len(chunk.instructions))
		for i=0, len(chunk.instructions)-1 do
			w4(chunk.instructions[i])
		end
		
		integer(len(chunk.constants))
		for i=0, len(chunk.constants)-1 do
			local v = chunk.constants[i]
			local t = type(v)
			
			if t == "boolean" then
				w1(1)
				w1(v and 1 or 0)
			elseif t == "number" then
				if math.type(v) == "integer" then
					w1(3 | 0x10)
					integer(v)
				else
					w1(3)
					double(v)
				end
			elseif t == "string" then
				w1(4)
				ws(v)
			else
				w1(0)
			end
		end
		
		integer(len(chunk.upvalues))
		for i=0, len(chunk.upvalues)-1 do
			w1(chunk.upvalues[i].instack)
			w1(chunk.upvalues[i].idx)
		end
		
		integer(len(chunk.functionPrototypes))
		for i=0, len(chunk.functionPrototypes)-1 do
			writeChunk(chunk.functionPrototypes[i])
		end
		
		integer(len(chunk.sourceLines))
		for i=0, len(chunk.sourceLines)-1 do
			integer(chunk.sourceLines[i])
		end
		
		integer(len(chunk.locals))
		for i=0, len(chunk.locals)-1 do
			local l = chunk.locals[i]
			ws(l.name)
			integer(l.startpc)
			integer(l.endpc)
		end
		
		integer(len(chunk.upvaluesDebug))
		for i=0, len(chunk.upvaluesDebug)-1 do
			ws(chunk.upvaluesDebug[i])
		end
	end
	
	w1(chunk.sizeupvalues)
	writeChunk(chunk)
	return table.concat(bc)
end
