function foo(h)
	return h.."bar",h.."baz",h.."foo"
end

return function()
	return foo("foo")
end,{},{"foobar","foobaz","foofoo"}