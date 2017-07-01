return function(decompiler)
	local format = {}

	do
		local function R(name)
			return {"reg", name}
		end
		local function K(name)
			return {"kst", name}
		end
		local function RK(name)
			return {"regkst", name}
		end
		local function RR(fromName, toName)
			return {"regrange", fromName, toName}
		end
		local function V(name)
			return {"value", name}
		end
		local function UV(name)
			return {"upvalue", name}
		end
		local function TI(tab, index)
			return {"tableindex", tab, index}
		end
		local function JUMP(name)
			return {"jump", name}
		end
		local function INV(name)
			return {"invert", name}
		end

		format.move = { R "dest", R "src" }
		format.loadk = { R "dest", K "kst" }
		format.loadbool = { R "dest", V "bool" }
		format.loadnil = { RR("from", "to") }
		format.getupval = { R "dest", UV "upvalue" }
		format.getglobal = { R "dest", K "index" }
		format.gettable = { R "dest", TI(R "table", RK "index") }
		format.setglobal = { K "index", R "src" }
		format.setupval = { UV "upvalue", R "src" }
		format.settable = { TI(R "table", RK "index"), R "src" }
		format.newtable = { R "dest" } -- TODO: Expose arraycnt and hashcnt
		format.self = { R "dest", R "object", RK "index" }
		format.binop = { R "dest", RK "lhs", RK "rhs" }
		format.unop = { R "dest", RK "rhs" }
		format.concat = { R "dest", RR("from", "to") }
		format.jump = { JUMP "to" }
		format.condop = { INV "invert", RK "lhs", RK "rhs" }
		format.condop.test = { INV "invert", R "target" }
		format.testset = { R "dest", INV "invert", R "target" }
	end

	function decompiler.prettyPrint(chunk, print)
		print = print or _G.print
		-- TODO: Get correct decoder
		local decoded = decompiler.decoder.native().decodeChunk(chunk)
	end
end
