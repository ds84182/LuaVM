return function(i)
	local t = {}
	for i,v in pairs(i) do
		t[v] = i
	end
	return t
end,{{a=1,b=2,c=3,d=4}},{{"a","b","c","d"}}
