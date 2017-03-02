-- many2one lua program to combine many lua files (linked by require) to one lua file for easy distribution
-- Written by Milind Gupta
-- For usage and questions visit http://milindsweb.amved.com/Many2One.html
-- The way it does is to read all files and convert them to strings and wraps the require function to check if
-- it has the file as a string then it sources the code from the string otherwise the normal require function works as before


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
print("Many2One version 1.17.3.1")
print("Usage: lua many2one.lua [configFile]")
print("For usage and help see:  http://milindsweb.amved.com/Many2One.html")
print(" ")
local screen = io.output(io.stdout)
local f=io.open(configFile,"r")
if f~=nil then 
	f:close() 
	-- load the configuration file
	screen:write("Read Configuration file "..configFile.."...")
	dofile(configFile)
	screen:write("DONE\n")
	if not fileList then
		print("No fileList table defined by the configuration file. Exiting")
	else
		local mf = mainFile or fileList[1]
		print("Processing the main file: "..mf)
		for i = 1,#fileList do
			-- Convert all files except the main file to strings
			if type(fileList[i]) == "string" and fileList[i] ~= mf or type(fileList[i]) == "table" and fileList[i][1] ~= mf then
				local fn = (type(fileList[i]) == "string" and fileList[i]) or (type(fileList[i]) == "table" and fileList[i][1])
				print("Reading "..fn.." to include.")
				f = io.open(fn,"r")
				if f ~=nil then
					local fileStr = f:read("*a")
					if type(fileList[i]) == "table" then
						luaCode[fileList[i][2]] = fileStr
					else
						luaCode[fileTitle(fileList[i])] = fileStr
					end
					f:close()
				end
			end
		end	-- for i = 1,#fileList do
		-- Add the files in the begining of the main file
		local mainFilePre
		if loadstring then
			mainFilePre = [[do
	local __MANY2ONEFILES={}
	local reqCopy = require 
	require = function(str)
		if __MANY2ONEFILES[str] then
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
		else
			return reqCopy(str)
		end
	end
]]
		else
			mainFilePre = [[do
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
]]
		end
		local addedFiles = {}
		--[[
		-- Now find and replace  require in all the read files with the custom code
		for k,v in pairs(luaCode) do
			for k1,v1 in pairs(luaCode) do
				local pre,post = v:find("require%s*%(?%s*[%\"%']"..k1.."[%\"%']%s*%)?%s*")
				if pre then
					luaCode[k] = luaCode[k]:gsub("require%s*%(?%s*[%\"%']"..k1.."[%\"%']%s*%)?","requireLuaString('"..k1.."')\n")
					if not addedFiles[k1] then
						addedFiles[k1] = true
					end
				end
			end
		end]]
		-- Add all files listed in the config
		for k,v in pairs(luaCode) do
			addedFiles[k] = true
		end
		-- Add all the required files in the beginning of Main file in MailFilePre
		print("Including all files in the beginning of the output file")
		for k,v in pairs(addedFiles) do
			mainFilePre = mainFilePre.."\t__MANY2ONEFILES['"..k.."']="..string.format("%q",luaCode[k]).."\n"
		end
		mainFilePre = mainFilePre.."end\n"	-- To end the do scope block
		-- Now write the main code output file
		print("Generate the output file")
		local of = outputFile or "output.lua"
		local fo = io.open(of,"w+")
		f = io.open(mf,"r")
		local mainFileStr = f:read("*a")
		f:close()
		-- Replace all require in main file with custom code
		--[[
		for k,v in pairs(luaCode) do
			local pre,post = mainFileStr:find("require%s*%(?%s*[%\"%']"..k.."[%\"%']%s*%)?%s*")
			if pre then
				mainFileStr = mainFileStr:gsub("require%s*%(?%s*[%\"%']"..k.."[%\"%']%s*%)?","requireLuaString('"..k.."')\n")
				if not addedFiles[k] then
					mainFilePre = mainFilePre.."__MANY2ONEFILES['"..k.."']="..string.format("%q",v).."\n"
					addedFiles[k] = true
				end
			end
		end]]
		mainFileStr = mainFilePre..mainFileStr
		fo:write(mainFileStr)
		fo:close()
	end		-- if not fileList then ends
else
	print("No Configuration file found. Exiting.")
end		-- if f~=nil then ends

