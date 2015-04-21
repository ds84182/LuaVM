return function(tab)
	tab[#tab+1] = "a"
	tab[#tab+1] = "b"
	tab[#tab+1] = "c"
	return tab
end,{{}},{{"a","b","c"}}
