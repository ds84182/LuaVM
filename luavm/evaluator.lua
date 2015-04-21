--evaluates and compiles any lua bytecode (as long as the instruction set is supported--
evaluator = {}

evaluator.lua = {
	keywords = {"do","end","function","while","repeat","until","if","then","elseif","then","else","for","in","local","return","break",
		"nil","false","true",
		"%.%.%.","==","~=","%.%.","<=",">=","and","or","not",
		"[-+;.:+*/,=%[%]%(%)%<%>%^%%#{}]"},
	ast = {},
	comment = "%-%-[^\n]*\n",
	blockCommentStart = "%-%-%[%[",
	blockCommentEnd = "%]%]",
}

function evaluator.eval(code, name, language, disallowCustomMatchers)
	name = name or "[string]"
	language = language or evaluator.lua
	local tokens = {}
	do
		local pos = 1
	
		local line = 1
		local char = 1

		local lasttok
		local function accept(regex)
			--print(regex, " ", pos)
			--yield()
			local r = code:match("^"..regex, pos)
			if r == nil then return false end
			lasttok = r
			pos = pos + #lasttok
		
			for k=1,#r do
				if r:sub(k,k) == "\n" then
					line = line + 1
					char = 1
				else
					char = char + 1
				end
			end
		
			return true
		end
	
		local function getContext()
			return {prefix=locprefix, line=line, char=char}
			--return c:sub(pos, pos+100)
		end

		local keywords = language.keywords
		local function tokenise1()
			accept("[ \r\n\t]+")
			if accept(language.blockCommentStart) then
				while not accept(language.blockCommentEnd) do
					if not accept("[^%]]+") then accept(".") end
				end
				return tokenise1()
			end
			if accept(language.comment) then return tokenise1() end
			if accept("[a-zA-Z_][a-zA-Z_0-9]*") then
				for k,v in ipairs(keywords) do
					if lasttok == v then return v end
				end
				return "id"
			end
			for k,v in ipairs(keywords) do if accept(v) then return lasttok end end
			if accept("[0-9]+%.[0-9]*") or accept("[0-9]+") then return "num" end
			if accept("\"") or accept("%[%[") then
				local s = ""
				local long = lasttok == "[["
				local _end = long and "%]%]" or "\""
				while not accept(_end) do
					if accept("\\") then
							if accept("a") then s=s.."\a"
						elseif accept("b") then s=s.."\b"
						elseif accept("f") then s=s.."\f"
						elseif accept("n") then s=s.."\n"
						elseif accept("r") then s=s.."\r"
						elseif accept("t") then s=s.."\t"
						elseif accept("v") then s=s.."\v"
						elseif accept("\\") then s=s.."\\"
						elseif accept("\"") then s=s.."\""
						elseif accept("'") then s=s.."\'"
						elseif accept("%[") then s=s.."["
						elseif accept("%]") then s=s.."]"
						elseif accept("[0-9][0-9][0-9]") or accept("[0-9][0-9]") or accept("[0-9]") then s=s..string.char(tonumber(lasttok))
						end
					elseif accept(long and "[^%]\\]+" or "[^\n\"\\]+") then s=s..lasttok
					else error("unfinished string")
					end
				end
				lasttok = s
				return "str"
			end
			if pos > #c then lasttok="" return "<eof>" end
			error("Unknown token near "..c:sub(pos-50,pos+100))
			return nil
		end

		while pos <= #c do
			local t = tokenise1()
			if t == nil then --[[print(c:sub(pos,pos+100))]] break end
			table.insert(tokens, {t, lasttok, getContext()})
		end
	end
end
