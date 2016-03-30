return function()
	local getA, getB, getC
	-- Simple Close
	do
		local a = 32
		function getA() return a end
	end
	-- Loop Close
	do
		for i=1, 128 do
			if i == 65 then
				function getB() return i end
			end
		end
	end
	-- Implicit Function Close
	getC = (function(c) return function() return c end end)(123)
	
	return getA(), getB(), getC()
end,{},{32, 65, 123}
