__MANY2ONEFILES={}
			function requireLuaString(str) 
				if not package.loaded[str] then 
					package.loaded[str] = true
					local res = load(__MANY2ONEFILES[str])
					res = res(str)
					if res ~= nil then
						package.loaded[str] = res
					end
				end 
				return package.loaded[str] 
			end
			__MANY2ONEFILES['req']="local _G = G\
\
local M = {}\
_ENV = M\
\
_G.c=10"
requireLuaString('req')

a = 4
print(a+b)
print(c)