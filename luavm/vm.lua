--loads the vm for the current lua version--
local vmversion = _VERSION:gsub("%D","")
return vm["lua"..vmversion]
