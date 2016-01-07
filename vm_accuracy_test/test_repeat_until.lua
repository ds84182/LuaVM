local i = 0

return function(func)
	local t = {}
	repeat
		table.insert(t,func())
	until t[#t] == 10
	return t
end,{function() i = i+1 return i end},{{1,2,3,4,5,6,7,8,9,10}}
