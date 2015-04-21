selfcall = {}
function selfcall:call()
	return self
end

return function()
	return selfcall:call()
end,{},{selfcall}
