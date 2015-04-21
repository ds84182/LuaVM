local a,b,c = math.random(1,10),math.random(1,10),math.random(1,10)

return function(a,b,c)
	return a+b+c, a-b-c, a*b*c, a/b/c, a%b%c, a^b^c
end,{a,b,c},{{a+b+c, a-b-c, a*b*c, a/b/c, a%b%c, a^b^c}}
