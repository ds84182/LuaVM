return function(...)
	local function closure(...)
		return ...
	end
	return closure(...)
end,{1,2,3},{1,2,3}
