return function(decompiler)
	local instr = {}

	decompiler.instr = instr

	local regDetailCache = setmetatable({}, {__mode = "k"})

	function instr.getRegisterDetails(instr)
		if not instr then return nil end

		local details = regDetailCache[instr]
		if not details then
			details = {
				write = {},
				read = {}
			}

			local typ = instr[1]

			local function write(reg)
				details.write[reg] = true
			end

			local function read(reg)
				details.read[reg] = true
			end

			local function readVA(base)
				details.read[-1] = base
			end

			local function writeVA(base)
				details.write[-1] = base
			end

			if instr.dest then
				write(instr.dest)
			end

			if instr.src then
				read(instr.src)
			end

			if instr.lhs and instr.lhs < 256 then
				read(instr.lhs)
			end

			if instr.rhs and instr.rhs < 256 then
				read(instr.rhs)
			end

			if typ == "call" or typ == "tailcall" then
				read(instr.base) -- function

				if instr.narg < 0 then
					readVA(instr.base+1) -- VA arguments
				else
					for i=instr.base+1, instr.base+instr.narg do
						read(i) -- argument
					end
				end

				if instr.nret < 0 then
					writeVA(instr.base) -- VA results
				else
					for i=instr.base, instr.base+instr.nret-1 do
						write(i) -- result
					end
				end
			elseif typ == "gettable" or typ == "settable" then
				read(instr.table)
				read(instr.index)
			elseif typ == "self" then
				read(instr.object)
				write(instr.base)
				write(instr.base+1)
			elseif typ == "concat" then
				for i=instr.from, instr.to do
					read(i)
				end
			elseif typ == "loadnil" then
				for i=instr.from, instr.to do
					write(i)
				end
			elseif typ == "condop" and (instr[2] == "test" or instr[2] == "testset") then
				read(instr.target)
			elseif typ == "return" then
				if instr.count < 0 then
					readVA(instr.base)
				else
					for i=instr.base, instr.base+instr.count-1 do
						read(i)
					end
				end
			elseif typ == "forprep" then
				read(instr.base)
				read(instr.base+2)
				write(instr.base)
			elseif typ == "forloop" then
				read(instr.base) -- index
				read(instr.base+1) -- limit
				read(instr.base+2) -- step
				write(instr.base)
				write(instr.base+3)
			elseif typ == "tforloop" then
				read(instr.base)
				read(instr.base+1)
				read(instr.base+2)
				for i=instr.base+3, instr.base+3+instr.count-1 do
					write(i)
				end
				write(instr.base+2)
			elseif typ == "setlist" then
				if instr.count < 0 then
					readVA(instr.base+1)
				else
					for i=0, instr.count-1 do
						read(instr.base+1+i)
					end
				end
			elseif typ == "vararg" then
				if instr.count < 0 then
					writeVA(instr.base)
				else
					for i=0, instr.count-1 do
						write(instr.base+1+i)
					end
				end
			end
		end
		return details
	end
end
