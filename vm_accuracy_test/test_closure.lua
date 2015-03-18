return function()
	local function closure()
		return 1, 2, 3
	end
	local a,b,c = closure()
	return a,b,c
end,{},{1,2,3}
