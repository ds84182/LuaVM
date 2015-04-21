selfcall = {}
function selfcall:call(...)
	return self, ...
end

return function(...)
	return selfcall:call(...)
end,{1,2,3},{selfcall,1,2,3}
