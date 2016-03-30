local decompiler = {}

decompiler.decoder = require "luavm.decompiler.decoder"
decompiler.analyzer = require "luavm.decompiler.analyzer"

decompiler.pass = {
	require "luavm.decompiler.pass.inline"(decompiler)
}

return decompiler
