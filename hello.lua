--[[print("Hello, World!");
print((4*5.5) < 5)

local nastyAssUpvalue = "LOL"
local function closureTest()
	print(nastyAssUpvalue,nastyAssUpvalue == "LOL")
	nastyAssUpvalue = nastyAssUpvalue == "LOL" and "LAWL" or "LOL"
end

closureTest()
closureTest()
closureTest()]]

local a,b = "\1",3
local c = a:byte(1) == b and "five" or "four"
print(c)

local a = os.clock()
local c = 0
local clk = os.clock
while true do
	if clk()-a > 1 then break end
	c = c+1
end
print("Loops per second: "..c)
