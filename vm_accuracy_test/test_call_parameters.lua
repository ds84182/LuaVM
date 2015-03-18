function foo(h)
	return h.."bar",h.."baz",h.."foo"
end

return function()
	local b,bz,f = foo("foo")
	return b,bz,f
end,{},{"foobar","foobaz","foofoo"}