return function()
	local function closure()
		return 1, 2, 3
	end
	return closure()
end,{},{1,2,3}
