return function()
	local a,b,c
	local function set()
		a,b,c = 1,2,3
	end
	local function increment()
		a = a+c
		b = b+a
		c = c+b
	end
	set()
	increment()
	increment()
	return a,b,c
end,{},{13,19,28}
