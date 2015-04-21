function foo()
	return "foo","bar","guize"
end

return function()
	return {foo()}
end,{},{{"foo","bar","guize"}}
