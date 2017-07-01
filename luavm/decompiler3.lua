-- Third times the charm.
local decompiler = {}

decompiler.decoder = require "luavm.decompiler3.decoder"
decompiler.core = require "luavm.decompiler3.decompiler"
require "luavm.decompiler3.pretty"(decompiler)

return decompiler
