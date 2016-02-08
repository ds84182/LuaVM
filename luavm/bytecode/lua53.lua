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
	
	return impl
end
