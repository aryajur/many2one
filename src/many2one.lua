-- many2one lua program to combine many lua files (linked by require) to one lua file for easy distribution
-- Written by Milind Gupta
-- For usage and questions visit http://milindsweb.amved.com/Many2One.html
-- The way it does is to read all files and convert them to strings and to replace the require for each file with a special 
-- require that uses loadstring rather than loadfile

function fileTitle(path)
	-- Find the name of the file without extension (that would be in Lua)
	local strVar
	local intVar1 = -1
	for intVar = #path,1,-1 do
		if string.sub(path, intVar, intVar) == "." then
	    	intVar1 = intVar
		end
		if string.sub(path, intVar, intVar) == "\\" or string.sub(path, intVar, intVar) == "/" then
	    	strVar = string.sub(path, intVar + 1, intVar1-1)
	    	break
		end
	end
	if not strVar then
		if intVar1 ~= -1 then
			strVar = path:sub(1,intVar1-1)
		else
			strVar = path
		end
	end
	return strVar
end

local luaCode = {}
local args = {...}
local configFile = args[1] or "Config.lua"
print("Many2One version 1.14.09.19"
print("Usage: lua many2one.lua [configFile]")
print("For usage and help see:  http://milindsweb.amved.com/Many2One.html")
print(" ")
local f=io.open(configFile,"r")
if f~=nil then 
	f:close() 
	-- load the configuration file
	dofile(configFile)
	if not fileList then
		print("No fileList table defined by the configuration file. Exiting")
	else
		local mf = mainFile or fileList[1]
		for i = 1,#fileList do
			-- Convert all files except the main file to strings
			if fileList[i] ~= mf then
				f = io.open(fileList[i],"r")
				if f ~=nil then
					local fileStr = f:read("*a")
					luaCode[fileTitle(fileList[i])] = fileStr
					f:close()
				end
			end
		end	-- for i = 1,#fileList do
		-- Add the files in the begining of the main file
		local mainFilePre
		if loadstring then
			mainFilePre = [[__MANY2ONEFILES={}
			function requireLuaString(str) 
				if not package.loaded[str] then 
					package.loaded[str] = true
					local res = loadstring(__MANY2ONEFILES[str])
					res = res(str)
					if res ~= nil then
						package.loaded[str] = res
						_G[str] = str
					end
				end 
				return package.loaded[str] 
			end
			]]
		else
			mainFilePre = [[__MANY2ONEFILES={}
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
			]]
		end
		local addedFiles = {}
		-- Now find and replace  require in all the read files with the custom code
		for k,v in pairs(luaCode) do
			local added = nil
			for k1,v1 in pairs(luaCode) do
				local pre,post = v:find("require%([%\"%']"..k1.."[%\"%']%)")
				if pre and not added then
					luaCode[k] = "local requireLuaString = requireLuaString\n"..v
				end
				if pre then
					luaCode[k] = luaCode[k]:gsub("require%([%\"%']"..k1.."[%\"%']%)","requireLuaString('"..k1.."')")
					if not addedFiles[k1] then
						addedFiles[k1] = true
					end
				end
			end
		end
		-- Add all the required files in the beginning of Main file in MailFilePre
		for k,v in pairs(addedFiles) do
			mainFilePre = mainFilePre.."__MANY2ONEFILES['"..k.."']="..string.format("%q",luaCode[k]).."\n"
		end
		-- Now write the main code output file
		local of = outputFile or "output.lua"
		local fo = io.open(of,"w+")
		f = io.open(mf,"r")
		local mainFileStr = f:read("*a")
		f:close()
		-- Replace all require in main file with custom code
		for k,v in pairs(luaCode) do
			local pre,post = mainFileStr:find("require%([%\"%']"..k.."[%\"%']%)")
			if pre then
				mainFileStr = mainFileStr:gsub("require%([%\"%']"..k.."[%\"%']%)","requireLuaString('"..k.."')")
				if not addedFiles[k] then
					mainFilePre = mainFilePre.."__MANY2ONEFILES['"..k.."']="..string.format("%q",v).."\n"
					addedFiles[k] = true
				end
			end
		end
		mainFileStr = mainFilePre..mainFileStr
		fo:write(mainFileStr)
		fo:close()
	end		-- if not fileList then ends
else
	print("No Configuration file found. Exiting.")
end		-- if f~=nil then ends

