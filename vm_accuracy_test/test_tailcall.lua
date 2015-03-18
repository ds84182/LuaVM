function foo()
	return "bar","baz","foo"
end

return function()
	return foo()
end,{},{"bar","baz","foo"}