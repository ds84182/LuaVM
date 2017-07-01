--[[
Decodes Lua 5.1 bytecode into a more generic form.

This does not aim to reconstruct loops or any other high level operations.
Just instruction decoding.

MOVE a, b -> {"move", dest = a, src = b}
LOADK a, b -> {"loadk", dest = a, kst = b}
LOADBOOL a, b -> {"loadbool", dest = a, bool = b ~= 0}
LOADNIL a, b -> {"loadnil", from = a, to = b}
GETUPVAL a, b -> {"getupval", dest = a, upvalue = b}
GETGLOBAL a, b -> {"getglobal", dest = a, index = b}
GETTABLE a, b, c -> {"gettable", dest = a, table = b, index = c}
SETGLOBAL a, b -> {"setglobal", src = a, index = b}
SETUPVAL a, b -> {"setupval", src = a, upvalue = b}
SETTABLE a, b, c -> {"settable", src = c, table = a, index = b}
NEWTABLE a, b, c -> {"newtable", dest = a, arraycnt = b, hashcnt = c}
SELF a, b, c -> {"self", dest = a, object = b, method = c}
<BINOP> a, b, c -> {"binop", "<symbol>", dest = a, lhs = b, rhs = c}
<UNOP> a, b -> {"unop", "<symbol>", dest = a, rhs = b}
CONCAT a, b, c -> {"concat", dest = a, from = b, to = c}
JMP sBx -> {"jump", to = pc+1+sBx}
EQ; LT; LE a, b, c -> {"condop", "<op>", lhs = b, rhs = c, invert = a ~= 0}
TEST a, c -> {"condop", "test", target = a, invert = c ~= 0}
TESTSET a, b, c -> {"testset", dest = a, target = b, invert = c ~= 0}
CALL a, b, c -> {"call", base = a, nret = c-2, narg = b-2}
TAILCALL a, b, c -> {"tailcall", base = a, nret = c-2, narg = b-2}
RETURN a, b -> {"return", base = a, count = b-2}
FORLOOP a, sBx -> {"forloop", base = a, target = pc+1+sBx}
FORPREP a, sBx -> {"forprep", base = a, target = pc+1+sBx}
TFORLOOP a, c -> {"tforloop", base = a, count = c}
SETLIST a, b, c -> {"setlist", base = a, count = b, set = c}
CLOSE a -> {"close", base = a}
CLOSURE a, Bx -> {"closure", dest = a, proto = Bx}
VARARG a, b -> {"vararg", base = a, count = b}
]]

local bytecode = require "luavm.bytecode"
local version = bytecode.version.lua51

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
}

return function(decoder)
	local target = {}

	local function decodeInstruction(chunk, i)
		local op, a, b, c = version.decode(chunk.instructions[i])

		if op == MOVE then
			return {"move", dest = a, src = b}
		elseif op == LOADK then
			return {"loadk", dest = a, kst = b}
		elseif op == LOADBOOL then
			return {"loadbool", dest = a, value = b ~= 0, skipNext = c ~= 0}
		elseif op == LOADNIL then
			return {"loadnil", from = a, to = b}
		elseif op == GETUPVAL then
			return {"getupval", dest = a, upvalue = b}
		elseif op == GETGLOBAL then
			return {"getglobal", dest = a, index = b}
		elseif op == GETTABLE then
			return {"gettable", dest = a, table = b, index = c}
		elseif op == SETGLOBAL then
			return {"setglobal", src = a, index = b}
		elseif op == SETUPVAL then
			return {"setupval", src = a, upvalue = b}
		elseif op == SETTABLE then
			return {"settable", src = c, table = a, index = b}
		elseif op == NEWTABLE then
			return {"newtable", dest = a, arraycnt = b, hashcnt = c}
		elseif op == SELF then
			return {"self", base = a, object = b, method = c}
		elseif binaryOps[op] then
			return {"binop", binaryOps[op], dest = a, lhs = b, rhs = c}
		elseif unaryOps[op] then
			return {"unop", unaryOps[op], dest = a, rhs = b}
		elseif op == CONCAT then
			return {"concat", dest = a, from = b, to = c}
		elseif op == JMP then
			return {"jump", to = i+1+b}
		elseif conditionalOps[op] then
			return {"condop", conditionalOps[op], lhs = b, rhs = c, invert = a ~= 0}
		elseif op == TEST then
			return {"condop", "test", target = a, invert = c ~= 0}
		elseif op == TESTSET then
			return {"testset", dest = a, target = b, invert = c ~= 0}
		elseif op == CALL then
			return {"call", base = a, nret = c-1, narg = b-1}
		elseif op == TAILCALL then
			return {"tailcall", base = a, nret = c-1, narg = b-1}
		elseif op == RETURN then
			return {"return", base = a, count = b-1}
		elseif op == FORLOOP then
			return {"forloop", base = a, target = i+1+b}
		elseif op == FORPREP then
			return {"forprep", base = a, target = i+1+b}
		elseif op == TFORLOOP then
			return {"tforloop", base = a, count = c}
		elseif op == SETLIST then
			local set, ni = c-1, i+1
			if set < 0 then
				set, ni = chunk.instructions[i+1], i+2
			end
			return {"setlist", base = a, count = b, set = set}, ni
		elseif op == CLOSE then
			return {"close", base = a}
		elseif op == CLOSURE then
			local upvalues = {}

			local nupvals = chunk.functionPrototypes[b].nupval

			for j=1, nupvals do
				upvalues[j] = decodeInstruction(chunk, i+j)
			end

			return {"closure", dest = a, proto = b, upvalues = upvalues}, i+1+nupvals
		elseif op == VARARG then
			return {"vararg", base = a, count = b-1}
		end
	end

	function target.decodeChunk(chunk)
		-- We subtract an extra instruction to skip the default return instruction
		local decoded = {last = -1}
		local i, j = 0, chunk.instructions.count-1
		while i <= j do
			local s, ni = decodeInstruction(chunk, i)
			if not s then
				return nil, "failed to decode instruction at "..i
			end
			decoded[i] = s
			decoded.last = i
			i = ni or (i+1)
		end
		decoded.protos = {}
		for i=0, chunk.functionPrototypes.count-1 do
			local dec, e = target.decodeChunk(chunk.functionPrototypes[i])
			if not dec then return nil, e end
			decoded.protos[i] = dec
		end
		return decoded
	end

	return target
end
