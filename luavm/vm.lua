local vm = {}
vm.debug = false
vm.typechecking = false

local pkgname = ...

function vm.get(version)
	return require(pkgname..version)
end

function vm.native()
	local major, minor = _VERSION:match("Lua (%d)%.(%d)")

	return vm.get(major..minor)
end

return vm
