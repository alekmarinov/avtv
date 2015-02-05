-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      main.lua                                           --
-- Description:   Main interface to avtv support tool                --
--                                                                   --
-----------------------------------------------------------------------

local config      = require "lrun.util.config"
local lfs         = require "lrun.util.lfs"
local log         = require "avtv.log"
local cmdupdate   = require "avtv.command.update"

module ("avtv.main", package.seeall)

_NAME = "AVTV"
_VERSION = "0.1"
_DESCRIPTION = "Support tool for EPG maintenance"

local appwelcome = _NAME.." ".._VERSION.." Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd"
local usagetext = "Usage: ".._NAME:lower().." [OPTION]... COMMAND [ARGS]..."
local usagetexthelp = "Try ".._NAME:lower().." --help' for more options."
local errortext = _NAME:lower()..": %s"
local helptext = [[
-c   --config CONFIG  config file path (default avtv.conf)
-q   --quiet          no output messages
-v   --verbose        verbose messages
-h,  --help           print this help.

where COMMAND can be one below:

]]

local commands =
{
	cmdupdate
}

for i,v in ipairs(commands) do
	commands[v._NAME] = v
end

--- exit with usage information when the application arguments are wrong 
local function usage(errmsg)
    assert(type(errmsg) == "string", "expected string, got "..type(errmsg))
    io.stderr:write(string.format(usagetext, errmsg).."\n\n")
    io.stderr:write(usagetexthelp.."\n")
    os.exit(1)
end

--- exit with error message
local function exiterror(errmsg)
    assert(type(errmsg) == "string", "expected string, got "..type(errmsg))
    io.stderr:write(string.format(errortext, errmsg).."\n")
    os.exit(1)
end

-----------------------------------------------------------------------
-- Setup prorgam start ------------------------------------------------
-----------------------------------------------------------------------

--- parses program arguments
local function parseoptions(...)
	local opts = {}
	local args = {...}
	local err
	local i = 1
	while i <= #args do
		local arg = args[i]
		if not opts.command then
			if arg == "-h" or arg == "--help" then
				io.stderr:write(appwelcome.."\n")
				io.stderr:write(usagetext.."\n\n")
				io.stderr:write(helptext)

				for i,v in ipairs(commands) do
					io.stderr:write(v._HELP.."\n")
				end

				os.exit(1)
			elseif arg == "-c" or arg == "--config" then
				i = i + 1
				opts.config = args[i]
				if not opts.config then
					exiterror(arg.." option expects parameter")
				end
			elseif arg == "-v" or arg == "--verbose" then
				opts.verbose = true
				if opts.quiet then
					exiterror(arg.." cannot be used together with -v")
				end
			elseif arg == "-q" or arg == "--quiet" then
				opts.quiet = true
				if opts.verbose then
					exiterror(arg.." cannot be used together with -q")
				end
			else
				opts.command = {string.lower(arg)}
			end
		else
			table.insert(opts.command, arg)
		end
		i = i + 1
	end
	if not opts.command then
		usage("Missing parameter COMMAND")
	end

	--- set program defaults
	opts.config = opts.config or "avtv.conf"
	return opts
end

-----------------------------------------------------------------------
-- Entry Point --------------------------------------------------------
-----------------------------------------------------------------------

function main(...)
	local args = {...}

	-- parse program options
	local opts = parseoptions(...)

	-- load configuration
	if not lfs.isfile(opts.config) then
		exiterror("Config file `"..opts.config.."' is missing")
	end
	-- load configuration and set it globaly
	if not opts.quiet then
		print(_NAME..": loading configuration")
	end
	local ok, err
	_G._conf, err = config.load(opts.config)
	if not _G._conf then
		exiterror(err)
	end

	-- set logging verbosity
	log.setverbosity(opts.quiet, opts.verbose)

	local cmdname = table.remove(opts.command, 1):lower()
	log.info(_NAME.." started with command "..cmdname:lower().." "..table.concat(opts.command, " "))
	
	if not commands[cmdname] then
		exiterror("Unknown command "..cmdname)
	end

	ok, err = commands[cmdname](unpack(opts.command))
	if not ok then
		exiterror(err)
	end
end
