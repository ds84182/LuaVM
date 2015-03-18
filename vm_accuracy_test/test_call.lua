function foo()
	return "bar","baz","foo"
end

return function()
	local b,bz,f = foo()
	return b,bz,f
end,{},{"bar","baz","foo"}