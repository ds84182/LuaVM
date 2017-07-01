return function(bytecode)
	local impl = {}

	local debug = bytecode.printDebug

	--of all the Lua versions, 5.3 has to set up the most.
	bytecode.bit = {
		bor = function(a, b) return a|b end,
		band = function(a, b) return a&b end,
		bnot = function(a) return ~a end,
		blshift = function(a, b) return a << b end,
		brshift = function(a, b) return a >> b end,
	}

	bytecode.binarytypes = {
		encode = {
			u1 = function(value, bigEndian)
				return string.char(value)
			end,
			u2 = function(value, bigEndian)
				return string.pack(bigEndian and ">I2" or "<I2", value)
			end,
			u4 = function(value, bigEndian)
				return string.pack(bigEndian and ">I4" or "<I4", value)
			end,
			u8 = function(value, bigEndian)
				return string.pack(bigEndian and ">I8" or "<I8", value)
			end,
			float = function(value, bigEndian)
				return string.pack(bigEndian and ">f" or "<f", value)
			end,
			double = function(value, bigEndian)
				return string.pack(bigEndian and ">d" or "<d", value)
			end,
		},
		decode = {
			u1 = function(bin, index, bigEndian)
				return bin:byte(index)
			end,
			u2 = function(bin, index, bigEndian)
				return string.unpack(bigEndian and ">I2" or "<I2", bin, index)
			end,
			u4 = function(bin, index, bigEndian)
				return string.unpack(bigEndian and ">I4" or "<I4", bin, index)
			end,
			u8 = function(bin, index, bigEndian)
				return string.unpack(bigEndian and ">I8" or "<I8", bin, index)
			end,
			float = function(bin, index, bigEndian)
				return string.unpack(bigEndian and ">f" or "<f", bin, index)
			end,
			double = function(bin, index, bigEndian)
				return string.unpack(bigEndian and ">d" or "<d", bin, index)
			end,
		},
	}

	-- instruction definitions

	local instructionNames = {
		[0]="MOVE","LOADK","LOADKX","LOADBOOL","LOADNIL","GETUPVAL",
		"GETTABUP","GETTABLE","SETTABUP","SETUPVAL","SETTABLE","NEWTABLE",
		"SELF",
		"ADD","SUB","MUL","MOD","POW","DIV","IDIV","BAND","BOR","BXOR","SHL",
		"SHR","UNM","BNOT","NOT","LEN","CONCAT",
		"JMP","EQ","LT","LE","TEST","TESTSET",
		"CALL","TAILCALL","RETURN",
		"FORLOOP","FORPREP","TFORCALL","TFORLOOP",
		"SETLIST","CLOSURE","VARARG","EXTRAARG",
	}

	local iABC = 0
	local iABx = 1
	local iAsBx = 2
	local iAx = 3

	local instructionFormats = {
		[0]=iABC,iABx,iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,
		iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iAsBx,
		iABC,iABx,iABC,iAx
	}

	local ins = {}
	for i, v in pairs(instructionNames) do ins[v] = i end

	impl.instructionNames = instructionNames
	impl.instructions = ins
	impl.defaultReturn = ins.RETURN|(1<<6) -- RETURN 0 1 0

	-- instruction constants

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

	-- instruction encoding and decoding

	function impl.encode(inst,a,b,c)
		inst = type(inst) == "string" and ins[inst] or inst
		local format = instructionFormats[inst]
		if format == iABC then
			return (inst&0x3F)|((a&0xFF) << 6)|((b&0x1FF) << 23)|((c&0x1FF)<<14)
		elseif format == iABx then
			return (inst&0x3F)|((a&0xFF) << 6)|((b&0x3FFFF) << 14)
		elseif format == iAsBx then
			return (inst&0x3F)|((a&0xFF) << 6)|(((b+131071)&0x3FFFF) << 14)
		elseif format == iAx then
			return (inst&0x3F)|(a<<6)
		else
			error("unknown opcode "..inst)
		end
	end

	function impl.decode(inst)
		local opcode = inst&0x3F
		local format = instructionFormats[opcode]
		if format == iABC then
			return opcode, (inst >> 6)&0xFF, (inst >> 23)&0x1FF, (inst >> 14)&0x1FF
		elseif format == iABx then
			return opcode, (inst >> 6)&0xFF, (inst >> 14)&0x3FFFF
		elseif format == iAsBx then
			local sBx = ((inst >> 14)&0x3FFFF)-131071
			return opcode, (inst >> 6)&0xFF, sBx
		elseif format == iAx then
			return opcode, inst >> 6
		else
			error("unknown opcode "..opcode)
		end
	end

	function impl.new(header)
		return {
			header = header,
			name = "",
			lineDefined = 0,
			lastLineDefined = 0,
			nparam = 0,
			isvararg = 2,
			maxStack = 2,
			instructions = {count=1, [0]=impl.defaultReturn},
			constants = {count=0},
			upvalues = {count=0},
			functionPrototypes = {count=0},
			sourceLines = {count=0},
			locals = {count=0},
			upvaluesDebug = {count=0}
		}
	end

	-- bytecode loading

	function impl.loadHeader(bc)
		local header = {version = 0x53}

		local fmtver = bc:byte(6)
		header.fmtver = fmtver
		debug("Format Version: %02X", fmtver)

		local types = bc:sub(13, 17)
		debug("Types: "..types:gsub(".", function(c) return string.format("%02X ", c:byte()) end))

		local bigEndian = bc:byte(18) == 0
		header.bigEndian = bigEndian
		debug("Big Endian: %s", tostring(bigEndian))

		local integer = types:byte(1)
		header.integer = integer
		debug("Integer Size: %d bytes", integer)

		local size_t = types:byte(2)
		header.size_t = size_t
		debug("Size_T Size: %d bytes", size_t)

		local instruction = types:byte(3)
		header.instruction = instruction
		debug("Instruction Size: %d bytes", instruction)

		local luaint = types:byte(4)
		header.luaint = luaint
		debug("lua_Integer Size: %d bytes", luaint)

		debug(bc:sub(1,32):gsub(".", function(c) return string.format("%02X ", c:byte()) end))

		--integral or numerical number stuff
		do
			local size = types:byte(5)
			local integralNumbers = bc:byte(bigEndian and (18+luaint) or (18+luaint+size-1)) == 0x72
			header.number_integral = integralNumbers
			header.number = size
			debug("Numerical Format: %d bytes <%s>", size, integralNumbers and "integral" or "floating")
		end

		return header
	end

	function impl.load(bc)
		debug("Lua 5.3 Bytecode Loader")

		local idx = 13
		local integer, size_t, number, luaint
		local bigEndian
		local binarytypes = bytecode.binarytypes

		local function u1()
			idx = idx+1
			return binarytypes.decode.u1(bc, idx-1, bigEndian)
		end

		local function u2()
			idx = idx+2
			return binarytypes.decode.u2(bc, idx-2, bigEndian)
		end

		local function u4()
			idx = idx+4
			return binarytypes.decode.u4(bc, idx-4, bigEndian)
		end

		local function u8()
			idx = idx+8
			return binarytypes.decode.u8(bc, idx-8, bigEndian)
		end

		local function float()
			idx = idx+4
			return binarytypes.decode.float(bc, idx-4, bigEndian)
		end

		local function double()
			idx = idx+8
			return binarytypes.decode.double(bc, idx-8, bigEndian)
		end

		local function ub(n)
			idx = idx+n
			return bc:sub(idx-n,idx-1)
		end

		local function us()
			local size
			local bytesize = u1()
			if bytesize < 0xFF then
				size = bytesize
			else
				size = size_t()
			end
			return ub(size-1)
		end

		local integralSizes = {
			[1] = u1,
			[2] = u2,
			[4] = u4,
			[8] = u8
		}

		local numericSizes = {
			[4] = float,
			[8] = double
		}

		local header = impl.loadHeader(bc)

		assert(header.fmtver == 0 or header.fmtver == 255, "unknown format version: "..header.fmtver)
		bigEndian = header.bigEndian
		integer = assert(integralSizes[header.integer], "unsupported integer size: "..header.integer)
		size_t = assert(integralSizes[header.size_t], "unsupported size_t size: "..header.size_t)
		luaint = assert(integralSizes[header.luaint], "unsupported luaint size: "..header.luaint)
		assert(header.instruction == 4, "unsupported instruction size: "..header.instruction)

		--integral or numerical number stuff
		do
			local integralNumbers = header.number_integral
			local size = header.number
			number = assert(integralNumbers and integralSizes[size] or numericSizes[size], "unsupported number size: "..(integralNumbers and "integral" or "floating").." "..size)
		end

		assert(bc:sub(7, 12) == "\25\147\r\n\26\n", "header has invalid encoding")

		idx = 18+header.luaint+header.number

		local sizeupvalues = u1()

		debug("Size Upvalues: "..sizeupvalues)

		local function chunk()
			local function instructionList()
				local instructions = {}
				local count = integer()
				instructions.count = count
				for i=1, count do
					instructions[i-1] = u4()
				end
				return instructions
			end

			local function constantList()
				local constants = {}
				local c = integer()
				constants.count = c
				for i=1, c do
					local type = u1()
					local subtype = type>>4
					type = type&0xF
					if type == 0 then
						constants[i-1] = nil
					elseif type == 1 then
						constants[i-1] = u1() > 0
					elseif type == 3 and subtype == 0 then
						constants[i-1] = number()
					elseif type == 3 and subtype == 1 then
						constants[i-1] = luaint()
					elseif type == 4 then
						constants[i-1] = us()
					else
						error("Type: "..type)
					end
					debug("Constant %d: %s %s %s", i-1, tostring(constants[i-1]), type, subtype)
				end
				return constants
			end

			local function functionPrototypeList()
				local functionPrototypes = {}
				local c = integer()
				functionPrototypes.count = c
				for i=1, c do
					functionPrototypes[i-1] = chunk()
				end
				return functionPrototypes
			end

			local function sourceLineList()
				local sourceLines = {}
				local c = integer()
				sourceLines.count = c
				for i=1, c do
					sourceLines[i-1] = integer()
				end
				return sourceLines
			end

			local function localList()
				local locals = {}
				local c = integer()
				locals.count = c
				for i=1, c do
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
				local c = integer()
				upvalues.count = c
				for i=1, c do
					upvalues[i-1] = us()
				end
				return upvalues
			end

			local function upvalueDefinitionList()
				local upvalues = {}
				local c = integer()
				upvalues.count = c
				for i=1, c do
					upvalues[i-1] = {instack=u1(),idx=u1()}
					debug("upvalue %d instack=%d idx=%d", i-1, upvalues[i-1].instack, upvalues[i-1].idx)
				end
				return upvalues
			end

			--extract an lua chunk into a table--
			local c = {header = header}

			c.name = us()
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.upvalues = upvalueDefinitionList()
			c.functionPrototypes = functionPrototypeList()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvaluesDebug = upvalueList()
			return c
		end

		return chunk()
	end

	function impl.save(chunk)
		local header = chunk.header
		local bc = {"\27Lua", string.char(header.version, 0),
			"\25\147\r\n\26\n"}

		bc[#bc+1] = string.char(
			header.integer,
			header.size_t,
			header.instruction,
			header.luaint,
			header.number
		)

		local integer, size_t, luaint, number
		local bigEndian = header.bigEndian
		local binarytypes = bytecode.binarytypes

		local function u1(value)
			bc[#bc+1] = string.char(value)
		end

		local function u2(value)
			bc[#bc+1] = binarytypes.encode.u2(value, bigEndian)
		end

		local function u4(value)
			bc[#bc+1] = binarytypes.encode.u4(value, bigEndian)
		end

		local function u8(value)
			bc[#bc+1] = binarytypes.encode.u8(value, bigEndian)
		end

		local function float(value)
			bc[#bc+1] = binarytypes.encode.float(value, bigEndian)
		end

		local function double(value)
			bc[#bc+1] = binarytypes.encode.double(value, bigEndian)
		end

		local function us(str)
			local siz = #str+1
			if siz < 0xFF then
				u1(siz)
			else
				u1(0xFF)
				size_t(siz)
			end
			bc[#bc+1] = str
		end

		local function len(t)
			local n = 0
			for i, v in pairs(t) do n = n+1 end
			return n
		end

		local integralSizes = {
			[1] = u1,
			[2] = u2,
			[4] = u4,
			[8] = u8
		}

		local numericSizes = {
			[4] = float,
			[8] = double
		}

		assert(header.fmtver == 0 or header.fmtver == 255, "unknown format version: "..header.fmtver)
		bigEndian = header.bigEndian
		integer = assert(integralSizes[header.integer], "unsupported integer size: "..header.integer)
		size_t = assert(integralSizes[header.size_t], "unsupported size_t size: "..header.size_t)
		luaint = assert(integralSizes[header.luaint], "unsupported luaint size: "..header.luaint)
		assert(header.instruction == 4, "unsupported instruction size: "..header.instruction)

		--integral or numerical number stuff
		do
			local integralNumbers = header.number_integral
			local size = header.number
			number = assert(integralNumbers and integralSizes[size] or numericSizes[size], "unsupported number size: "..(integralNumbers and "integral" or "floating").." "..size)
		end

		luaint(0x5678)
		number(370.5)
		u1(chunk.upvalues.count or len(chunk.upvalues))

		local function dumpChunk(chunk)
			us(chunk.name)
			integer(chunk.lineDefined)
			integer(chunk.lastLineDefined)
			u1(chunk.nparam)
			u1(chunk.isvararg)
			u1(chunk.maxStack)

			local lenInstructions = chunk.instructions.count or len(chunk.instructions)
			integer(lenInstructions)
			for i=0, lenInstructions-1 do
				u4(chunk.instructions[i])
			end

			local lenConstants = chunk.constants.count or len(chunk.constants)
			integer(lenConstants)
			for i=0, lenConstants-1 do
				local v = chunk.constants[i]
				local t = type(v)
				local tt
				if t == "nil" then
					tt = 0
				elseif t == "boolean" then
					tt = 1
				elseif t == "number" then
					tt = 3 | (math.type(v) == "integer" and (1<<4) or 0)
				elseif t == "string" then
					tt = 4
				end
				u1(tt)
				if t == "boolean" then
					u1(v and 1 or 0)
				elseif t == "number" then
					if tt > 3 then
						luaint(v)
					else
						number(v)
					end
				elseif t == "string" then
					us(v)
				end
			end

			local lenUpvalueDefs = chunk.upvalues.count or len(chunk.upvalues)
			integer(lenUpvalueDefs)
			for i=0, lenUpvalueDefs-1 do
				local uv = chunk.upvalues[i]
				u1(uv.instack)
				u1(uv.idx)
			end

			local lenFunctionPrototypes = chunk.functionPrototypes.count or len(chunk.functionPrototypes)
			integer(lenFunctionPrototypes)
			for i=0, lenFunctionPrototypes-1 do
				dumpChunk(chunk.functionPrototypes[i])
			end

			local lenSourceLines = chunk.sourceLines.count or len(chunk.sourceLines)
			integer(lenSourceLines)
			for i=0, lenSourceLines-1 do
				integer(chunk.sourceLines[i])
			end

			local lenLocals = chunk.locals.count or len(chunk.locals)
			integer(lenLocals)
			for i=0, lenLocals-1 do
				local l = chunk.locals[i]
				us(l.name)
				integer(l.startpc)
				integer(l.endpc)
			end

			local lenUpvalues = chunk.upvaluesDebug.count or len(chunk.upvaluesDebug)
			integer(lenUpvalues)
			for i=0, lenUpvalues-1 do
				us(chunk.upvalues[i])
			end
		end

		dumpChunk(chunk)
		return table.concat(bc)
	end

	return impl
end
