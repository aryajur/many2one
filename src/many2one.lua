-- many2one lua program to combine many lua files (linked by require) to one lua file for easy distribution
-- Written by Milind Gupta
-- For usage and questions visit http://milindsweb.amved.com/Many2One.html
-- The way it does is to read all files and convert them to strings and wraps the require function to check if
-- it has the file as a string then it sources the code from the string otherwise the normal require function works as before

-- Config File Example
--[[
exclude = {
	"llthreads",
	"cURL"
}
 
mainFile = "myscript.lua"
outputFile = "myScriptApp.lua"
deployDir = "../deploy/"
]]

-- CAUTION:
-- If using multithreading using for example like llthreads, to reuse all the included modules in the thread do the following:
--     * The __MANY2ONEFILES declaration in the beginning of the combined file should be made global instead of local
--     * The following code should be added to the beginning of the thread code to refer these included modules:
--[[
		do
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
		end
]]

-- TODO:
-- 1. Add option to have __MANY2ONEFILES global
-- 2. Add file obfuscation
-- 3. Add file compression

require("submodsearcher")

local tu = require("tableUtils")
local lfs = require("lfs")
local diskOP = require("diskOP")

local logConsole = require("logging.console")

local logger = logConsole()

local ap = require("argparse")
local parser = ap():name("Many2One"):description("This app helps package a Lua project and its dependencies. See http://milindsweb.amved.com/Many2One.html for reference.")	-- Create a parser

parser:argument("configFile")
	:description("Configuration file for the run.")
	:default("config.lua")
	:args("?")
parser:option("--wd")
	:description("Specify working directory where. Config file is loaded after changing to working directory.")
	:args(1)
	:count("?")
parser:flag("--depwarnonly")
	:description("Only give warning and not error if a dependency is not found.")
parser:mutex(
	parser:flag("--lua51")
		:description("Force Lua 5.1 semantics in the generated output. loadstring will be used to load the module string."),
	parser:flag("--lua52p")
		:description("Force Lua 5.2+ semantics in the generated output. load function will be used to load the module string.")
)

local luaCode = {}
local args = parser:parse()
--local configFile = args[1] or "Config.lua"
logger:info("------------------------------------------------------------------")
logger:info("Many2One version 1.21.09.28")
logger:info(" ")

local txtExt = {"lua"}			-- List of file extensions that are text files and will be combined with the lua script file
local exclude = {		-- Any modules that need not be packaged
	"string",
	"table",
	"package",
	"os",
	"io",
	"math",
	"coroutine",
	"debug",
	"utf8"
}
local mainFile, outFile, moreExclude, deployDir, clearDeployDir, include

local configFile = args.configFile or "config.lua"
-- Change the directory
local curDir,err = lfs.currentdir()
if not curDir then
	logger:error("Cannot determine current directory "..err)
	os.exit()
end
local workingDir = args.wd or curDir

lfs.chdir(workingDir)

local f,msg = io.open(configFile)
if not f then
	logger:error("Could not open the configuration file "..configFile)
	os.exit()
end
f:close() 
-- load the configuration file
logger:info("Read Configuration file "..configFile.."...")
dofile(configFile)
mainFile = _G.mainFile
txtExt = _G.txtExt or txtExt
outFile = _G.outFile
moreExclude = _G.exclude or {}
include = _G.include or {}
deployDir = _G.deployDir or curDir
clearDeployDir = _G.clearDeployDir
depwarnonly = args.depwarnonly or _G.depwarnonly

deployDir = diskOP.sanitizePath(deployDir)

if not diskOP.verifyPath(deployDir) then
	logger:error("Deploy directory "..deployDir.." is not valid.")
	os.exit()
end

if clearDeployDir then
	diskOP.emptyDir(deployDir)
end

tu.mergeArrays(moreExclude,exclude)

if not mainFile then 
	logger:error("Need a main file name to package. The configuration file should specify a mainFile.")
	os.exit()
end

-- Function to remove comments from a lua file passed as a string
local function removeComments(str)
	-- Do a simple tokenizer for strings and comments
	local strout = {}
	local CODE,STRING,COMMENT = 0,1,2
	local strenc = ""
	local comenc = ""
	local token = CODE
	local currChar 
	local pos = 1
	local lastToken = 0
	while pos <= #str do
		currChar = str:sub(pos,pos)
		if currChar == "-" and token ~= STRING and token ~= COMMENT then
			-- Possibility of starting the comment
			if str:sub(pos + 1,pos + 1) == "-" then
				-- This is definitely starting of a comment
				token = COMMENT
				-- Add all code till now before starting the comment
				strout[#strout + 1] = str:sub(lastToken + 1,pos-1)
				pos = pos + 1
				lastToken = pos
				-- Check if this is a square bracket comment
				local strt,stp = str:find("%[=*%[",pos+1)
				if strt and strt == pos + 1 then
					-- This is a square bracket comment
					comenc = str:sub(pos+1,stp):gsub("%[","]")
					print("Square bracket comment at "..strt.." ending with "..comenc)
					pos = stp
					lastToken = pos
				else
					comenc = "--"
				end
			end
		elseif currChar == "]" and (token == COMMENT or token == STRING) then
			-- Possibility of ending a comment or a string
			local enc
			if token == COMMENT then 
				enc = comenc
			else
				enc = strenc
			end
			local strt,stp = str:find(enc,pos,true)
			if strt and strt == pos then
				-- Comment/string ends here
				if token == STRING then
					-- Add all the code till now till ending of string
					strout[#strout + 1] = str:sub(lastToken + 1,pos-1+#strenc)
					strenc = ""
				else
					comenc = ""
				end
				token = CODE
				pos = pos - 1 + #enc
				lastToken = pos
			end
		elseif currChar == "\n" and token == COMMENT then
			-- Possibily of ending a comment
			if comenc == "--" then
				-- End the comment here
				token = CODE
				lastToken = pos-1	-- No code to add
				comenc = ""
			end
		elseif currChar == "[" and token ~= COMMENT and token ~= STRING then
			-- Possibility of starting a string
			-- Check if this is a square bracket string
			local strt,stp = str:find("%[=*%[",pos)
			if strt and strt == pos then
				-- This is a square bracket string
				token = STRING
				strenc = str:sub(pos,stp):gsub("%[","]")
				pos = stp
				-- Add all the code till now
				strout[#strout + 1] = str:sub(lastToken + 1,pos)
				lastToken = pos
			end
		elseif currChar == "'" and token ~= COMMENT then
			-- Possibility of starting or ending a string
			if token == STRING then
				if strenc == "'" then
					-- String ends here
					token = CODE
					strenc = ""
					-- Add all the code till now
					strout[#strout + 1] = str:sub(lastToken + 1,pos)
					lastToken = pos
				end
			else
				-- String starts here
				token = STRING
				strenc = "'"
				-- Add all the code till now
				strout[#strout + 1] = str:sub(lastToken + 1,pos)
				lastToken = pos
			end
		elseif currChar == '"' and token ~= COMMENT then
			-- Possibility of starting or ending a string
			if token == STRING then
				if strenc == '"' then
					-- String ends here
					token = CODE
					strenc = ""
					-- Add all the code till now
					strout[#strout + 1] = str:sub(lastToken + 1,pos)
					lastToken = pos
				end
			else
				-- String starts here
				token = STRING
				strenc = '"'
				-- Add all the code till now
				strout[#strout + 1] = str:sub(lastToken + 1,pos)
				lastToken = pos
			end
		elseif currChar == [[\]] and token == STRING then
			-- Possibility of escaping the next character
			if strenc == "'" or strenc == '"' then
				pos = pos + 1	-- Escape the next character
			end
		end
		pos = pos + 1
	end
	return table.concat(strout)
end

local fileQ = {
	{mainFile,"MAIN"}	-- File name and dependency cross reference
}		-- Table to store files that need to be processed for dependencies

local reference,maxref
maxref = 0

local function addAllRequires(fDat)
	-- Search for requires
	for depends in fDat:gmatch([=[require%s*%(?%s*(%f[%["']..-%f[%]"'])%s*%)?]=]) do 
		--logger:info("Found dependency "..depends)
		depends = depends:match([=[['"%[%]%=]+(.+)]=])
		if not luaCode[depends] and not tu.inArray(exclude,depends) then
			-- Find the dependency using the searchers
			logger:info("Processing dependency "..depends)
			local found
			for i = 2,#package.searchers do
				local fun,path = package.searchers[i](depends)
				
				if type(fun) == "function" and type(path) == "string" then
					luaCode[depends] = {
						path = path,
						reference = reference
					}
					maxref = (#reference+#depends) > maxref and (#reference+#depends) or maxref
					for j = 1,#txtExt do
						if path:match(txtExt[j].."$") then
							found = true
							break
						end
					end
					if found then
						-- Process as a text file
						logger:info("Process "..path.." as a text file.")
						f,msg = io.open(path)
						if not f then
							logger:error("Cannot read file: "..msg)
							os.exit()
						end
						luaCode[depends].text = f:read("*a")
						f:close()
					else
						logger:info("Process "..path.." as a binary file.")
					end
					
					found = true
					break
				end			
			end		-- for i = 2,#package.searchers do
			if not found then
			    if depwarnonly then
					logger:warn("Could not find the dependency "..depends)
				else
					logger:error("Could not find the dependency "..depends)
					os.exit()
				end
			else
				-- Add the dependency to fileQ
				fileQ[#fileQ+1] = luaCode[depends].path ~= mainFile and {luaCode[depends].path,reference.."->"..depends}
			end
		end		-- if not luaCode[depends] then and not tu.inArray(exclude,depends) 
	end
end 

-- First process all the include files
logger:info("Process all include files")
reference = "INCLUDE"
local incFiles = ""
for i = 1,#include do
	incFiles = incFiles.."require('"..include[i].."')\n"
end
addAllRequires(incFiles)

while #fileQ > 0 do
	logger:info("Reading file "..fileQ[1][1].." to look for dependencies.")
	f,msg = io.open(fileQ[1][1],"r")
	if not f then
		logger:error("Cannot read file: "..msg)
		os.exit()
	end
	local fDat = f:read("*a")
	f:close()
	reference = fileQ[1][2]
	logger:info("File reading done.")
	addAllRequires(removeComments(fDat))
	-- Remove the item from fileQ
	table.remove(fileQ,1)
end

logger:info("Write the combined application script")
local mainFilePre
if args.lua51 or (not args.lua52p and loadstring) then
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

local sep = package.config:match("(.-)%s")

local copiedFiles = {}

-- Add all the required files in the beginning of Main file in MailFilePre
logger:info("Including all text files in the beginning of the output file and copying the binaries.")
local totalText,totalBinary = 0,0
for k,v in pairs(luaCode) do
	logger:info("Dependency: "..k.." File: "..v.path)
	if v.text then
		mainFilePre = mainFilePre.."\t__MANY2ONEFILES['"..k.."']="..string.format("%q",v.text).."\n"
		totalText = totalText + 1
	else
		-- Copy over the binary file to deployDir here
		local subst = k:gsub("%.",sep)			-- The whole module name separated by the system separator instead of dots
		local fileName = diskOP.getFileName(v.path)
		-- Check if this is a C submodule 
		local found
		for p in package.cpath:gmatch("(.-);") do
			if p:gsub("%?",subst) == v.path then
				found = true
				break
			end
		end
		local newPath,newFile
		if not found then
			-- Submodule in a C module file (package.searcher[4])
			subst = k:match("^(.-)%.")
		end
		-- figure out the relative path for package
		newPath = deployDir..subst
		for i = #v.path,1,-1 do
			local testPath = newPath..v.path:sub(i,-1)
			if testPath:sub(-1*(#fileName),-1) == fileName then
				if fileName ~= diskOP.getFileName(testPath) then
					testPath = newPath..sep..v.path:sub(i,-1)
				end
				newFile = testPath
				break
			end
		end
		if not newFile then
			if depwarnonly then
				logger:warn("Cannot find the new path for dependency "..k.." file: "..v.path)
			else
				logger:error("Cannot find the new path for dependency "..k.." file: "..v.path)
				os.exit()
			end
		end
		-- newFile is the new file name and location
		newPath = newFile:sub(1,-1*(#fileName+1))
		local stat,msg = diskOP.createPath(newPath)
		if not stat then
			logger:error("Could not create path "..newPath.." to copy "..fileName)
			os.exit()
		end
		if not copiedFiles[newPath..fileName] then
			logger:info("Copy file "..v.path.." to "..newPath)
			stat,msg = diskOP.copyFile(v.path,newPath,fileName)
			if not stat then
				logger:error("Could not copy file "..fileName.." to "..newPath..": "..msg)
				os.exit()
			end
			copiedFiles[newPath..fileName] = true
			totalBinary = totalBinary + 1
		end
	end
end
mainFilePre = mainFilePre.."end\n"	-- To end the do scope block
-- Now write the main code output file
logger:info("Generate the output file")
local of = deployDir..(outputFile or "output.lua")
local fo = io.open(of,"w+")
f = io.open(mainFile,"r")
local mainFileStr = f:read("*a")
f:close()
mainFileStr = mainFilePre..mainFileStr
fo:write(mainFileStr)
fo:close()
-- Now display a summary
logger:info("#########################################")
logger:info("                 SUMMARY				  ")
logger:info("#########################################")
logger:info("Total Text files = "..totalText)
logger:info("Total Binary files = "..totalBinary)
logger:info("Total files = "..(totalText + totalBinary))
logger:info("TEXT FILES:")
for k,v in pairs(luaCode) do
	if v.text then
		logger:info(v.reference.."->"..k..string.rep(" ",maxref+4-(#v.reference+#k))..v.path)
	end
end

logger:info("BINARY FILES:")
for k,v in pairs(luaCode) do
	if not v.text then
		logger:info(v.reference.."->"..k..string.rep(" ",maxref+4-(#v.reference+#k))..v.path)
	end
end

lfs.chdir(curDir)
logger:info("All Done!")
