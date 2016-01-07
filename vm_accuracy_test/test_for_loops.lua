return function()
	local t = {}
	for i=1, 10 do
		table.insert(t,i)
	end
	return t
end,{},{{1,2,3,4,5,6,7,8,9,10}}
