do
	local __MANY2ONEFILES={}
	local reqCopy = require 
	require = function(str)
		if __MANY2ONEFILES[str] then
			if not package.loaded[str] then 
				package.loaded[str] = true
				local res = load(__MANY2ONEFILES[str])
				res = res(str)
				if res ~= nil then
					package.loaded[str] = res
				end
			end 
			return package.loaded[str] 		
		else
			return reqCopy(str)
		end
	end
	__MANY2ONEFILES['req']="local _G = G\
\
local M = {}\
_ENV = M\
\
_G.c=10"
end
require("req")

a = 4
print(a+b)
print(c)