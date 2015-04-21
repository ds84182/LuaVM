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
			registerUsageMap[a+2][pc] = "get"
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
	end
end

function decompiler.decompile(bc)
	local pc = 0
	local block
	
	local function isExpressionOp(op,a,b,c)
		return op == GETGLOBAL or op == LOADK or op == CALL
	end
	
	local expressionRegisters = {}
	local function decompileExpression(s,e)
		local expression = {}
		local pc = s
		while true do
			local op,a,b,c = decodeInstruction(bc.instructions[pc])
			if isExpressionOp(op,a,b,c) then
				
		end
		return expression
	end
	
	local function decompileBlock()
		if not bc.instructions[pc] then return end
		
		local previous = block
		local blk = {}
		block = blk
		
		local expBegin
		local expEnd
		
		while bc.instructions[pc] do
			local op,a,b,c = decodeInstruction(bc.instructions[pc])
			expBegin = -1
			expEnd = -1
			while isExpressionOp(op,a,b,c) do
				expBegin = pc
				--expression opcode, advance until next block opcode
				pc = pc+1
				op,a,b,c = decodeInstruction(bc.instructions[pc])
			end
			expEnd = pc
			
			if op == RETURN then
				local exp
				if expBegin ~= -1 then
					--generate expression--
					exp = decompileExpression(expBegin, expEnd)
				end
				blk[#blk+1] = {type="expression",expression=exp}
				blk[#blk+1] = {type="return",begin=a,size=b-1}
			end
			pc = pc+1
		end
		
		block = previous
		return blk
	end
	
	local blocks = {
		info = {locals = bc.maxStack}
	}
	local block = decompileBlock()
	while block do
		blocks[#blocks+1] = block
		block = decompileBlock()
	end
	
	return blocks
end

function decompiler.constructSyntax(syntaxrep, way)
	way = way or "basic"
	local tabs = ""
	local source = {}
	
	local function emit(line)
		source[#source+1] = tabs..line
	end
	
	local function tab()
		if way == "pretty" then
			tabs = tabs.."\t"
		end
	end
	
	local function detab()
		if way == "pretty" then
			tabs = tabs:sub(1,-2)
		end
	end
	
	registerPrefix = makeRandomString()
	
	do
		local i = 0
		emit("local "..string.rep(registerPrefix.."r,", syntaxrep.info.locals):sub(1,-2):gsub("r",function() i = i+1 return "r"..(i-1) end))
	end
	
	local function decodeSyntaxExpression(expression)
		
	end
	
	local function decodeSyntaxBlock(block)
		local t = block.type
		
		if t == "if" then
			local exp = decodeSyntaxExpression(block.exp)
			emit("if "..exp.." then")
			tab()
			for _,block in ipairs(block.blocks) do
				decodeSyntaxBlock(block)
			end
			detab()
			emit("end")
		elseif t == "call" then
			local exp = decodeSyntaxExpression(block.func)
			local args = {}
			for i, v in ipairs(block.args) do
				args[i] = decodeSyntaxExpression(v)
			end
			emit(exp.."("..table.concat(args,", ")..")")
		elseif t == "expression" then
			
		elseif t == "return" then
			
		end
	end
	
	return table.concat(source, "\n")
end
