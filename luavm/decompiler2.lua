local decompiler = {}

decompiler.decoder = require "luavm.decompiler.decoder"
decompiler.analyzer = require "luavm.decompiler.analyzer"
decompiler.formatter = require "luavm.decompiler.formatter"

-- Do the table inline pass before general inline so tables can be inlined
decompiler.pass = {
	require "luavm.decompiler.pass.inline"(decompiler),
	require "luavm.decompiler.pass.table_inline"(decompiler),
}

return decompiler
