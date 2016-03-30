return function(a, b, c, ...)
	local function closure(...)
		return ...
	end
	return closure(...)
end,{1,2,3},{}
