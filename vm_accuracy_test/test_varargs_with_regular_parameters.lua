return function(a, b, c, ...)
	local function closure(...)
		return ...
	end
	return closure(...)
end,{1,2,3,4,5,6,7},{4,5,6,7}
