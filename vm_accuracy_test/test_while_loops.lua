local i = 0

return function(func)
	local t = {}
	local n = func()
	while n ~= 10 do
		table.insert(t,n)
		n = func()
	end
	return t
end,{function() i = i+1 return i end},{{1,2,3,4,5,6,7,8,9}}
