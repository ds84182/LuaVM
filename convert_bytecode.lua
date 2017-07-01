local bcfilename, targetheader = ...
local bcfile = io.open(bcfilename, 'rb')
local bytecode = require 'luavm.bytecode'

local header

if targetheader then
  if targetheader:sub(1,1) == "@" then
    local i = 2
    header = {
      fmtver = 0,
    }
    while i <= #targetheader do
      local cmd = targetheader:sub(i, i)
      if cmd == "v" then
        -- Version
        header.version = tonumber("0x"..targetheader:sub(i+1, i+2))
        i = i+2
      elseif cmd == "e" then
        -- Endian
        header.bigEndian = targetheader:sub(i+1, i+1) == "b"
        i = i+1
      elseif cmd == "i" then
        -- Integer
        header.integer = tonumber(targetheader:sub(i+1, i+2))
        i = i+2
      elseif cmd == "s" then
        -- SizeT
        header.size_t = tonumber(targetheader:sub(i+1, i+2))
        i = i+2
      elseif cmd == "o" then
        -- Instruction (opcode)
        header.instruction = tonumber(targetheader:sub(i+1, i+2))
        i = i+2
      elseif cmd == "f" then
        -- Floats
        header.number_integral = false
        header.number = tonumber(targetheader:sub(i+1, i+2))
        i = i+2
      elseif cmd == "n" then
        -- Integers
        header.number_integral = true
        header.number = tonumber(targetheader:sub(i+1, i+2))
        i = i+2
      else
        io.stderr:write("Ignoring header command `"..cmd.."`\n")
      end
      i = i+1
    end
  else
    targetheader = io.open(targetheader, 'rb'):read('*a')
    local version = targetheader:byte(5)
    header = bytecode.version[version].loadHeader(targetheader)
  end
else
  header = bytecode.new().header
end

local decoded = bytecode.load(bcfile:read("*a"))
decoded.header = header
local output = bytecode.save(decoded)
io.open(bcfilename..'-conv.bc', 'wb'):write(output)
