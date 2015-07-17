-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      epgutils.lua                                       --
-- Description:   EPG utility functions                              --
--                                                                   --
-----------------------------------------------------------------------

local dw       = require "lrun.net.www.download.luasocket"
local lfs      = require "lrun.util.lfs"
local string   = require "lrun.util.string"
local config   = require "avtv.config"
local log      = require "avtv.log"
local logging  = require "logging"
local gzip     = require "luagzip"
local unicode  = require "unicode"

local io, os, type, ipairs, tostring, table, math, pairs =
      io, os, type, ipairs, tostring, table, math, pairs

module "avtv.provider.bulsat.epgutils"

local DEBUG = false
local DISABLE_IMAGE_DOWNLOAD = DEBUG

local errormessages = {}

function _M.logerror(errmsg)
	table.insert(errormessages, _NAME..": "..errmsg)
end

function _M.sendlogerrors()
	if #errormessages > 0 then
		local logmsgs = {}
		for i, errmsg in ipairs(errormessages) do
			table.insert(logmsgs, logging.prepareLogMsg(nil, os.date(), logging.ERROR, errmsg))
		end
		log.error(_NAME..": update errors:\n"..table.concat(logmsgs, "\n"))
	end
end

function _M.channeltostring(channel)
	local function mkstring(t)
		if type(t) == "table" then
			if #t > 0 then
				local tabval = {}
				for i, v in ipairs(t) do
					table.insert(tabval, mkstring(v))
				end
				return "{"..table.concat(tabval, ",").."}"
			else
				local tabval = {}
				for i, v in pairs(t) do
					table.insert(tabval, i.."="..mkstring(v))
				end
				return "{"..table.concat(tabval, ",").."}"
			end
		end
		t = tostring(t)
		if string.len(t) > 10 then
			t = string.sub(t, 1, 7).."..."
		end
		return t
	end
	local channelinfo = ""
	for i, v in pairs(channel) do
		if string.len(channelinfo) > 0 then
			channelinfo = channelinfo..", "
		end
		channelinfo = channelinfo..i.."="..mkstring(v)
	end
	return channelinfo
end

function _M.mktempfile(ext)
	local tmpfile = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"), string.format("tmp_%08x", math.random(99999999)))
	if ext then
		tmpfile = tmpfile..ext
	end
	return tmpfile
end

function _M.downloadtempimage(url)
	if DISABLE_IMAGE_DOWNLOAD then
		return nil, "image download is disable"
	end
	local tmpfile = mktempfile(lfs.ext(url))
	lfs.mkdir(lfs.dirname(tmpfile))
	log.debug(_NAME..": downloading `"..url.."' to `"..tmpfile.."'")
	local ok, err = dw.download(url, tmpfile)
	if not ok then
		logerror(url.."->"..err)
		return nil, err
	else
		return tmpfile
	end 
end

-- cyrilic to latin
local cyr = {"а", "б", "в", "г", "д", "е", "ж", "з", "и", "й", "к", "л", "м", "н", "о", "п", "р", "с", "т", "у", "ф", "х", "ц", "ч", "ш", "щ", "ъ", "ь", "ю", "я",
"А", "Б", "В", "Г", "Д", "Е", "Ж", "З", "И", "Й", "К", "Л", "М", "Н", "О", "П", "Р", "С", "Т", "У", "Ф", "Х", "Ц", "Ч", "Ш", "Щ", "Ъ", "Ь", "Ю", "Я"}
local lat = {"a", "b", "v", "g", "d", "e", "j", "z", "i", "j", "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f", "h", "c", "c", "s", "t", "u", "_", "u", "a", 
"A", "B", "V", "G", "D", "E", "J", "Z", "I", "J", "K", "L", "M", "N", "O", "P", "R", "S", "T", "U", "F", "H", "C", "C", "S", "T", "U", "_", "U", "A"}

for i, c in ipairs(cyr) do
	cyr[c] = i
end

function _M.normchannelid(id)
	id = tostring(id)
	id = string.gsub(id, "%.", "_")
	id = string.gsub(id, " ", "_")

	local newid = ""
	for ci = 1, unicode.len(id) do
		local c = unicode.sub(id, ci, ci)
		if cyr[c] then
			newid = newid..lat[cyr[c]]
		else
			newid = newid..c
		end
	end
	return newid
end

function _M.downloadurl(url, opts)
	local tmpfile = mktempfile()
	log.debug(_NAME..": downloading `"..url.."' to `"..tmpfile.."'")
	lfs.mkdir(lfs.dirname(tmpfile))
	local ok, code, headers = dw.download(url, tmpfile, opts)
	if not ok then
		-- error downloading url
		return nil, code.." while downloading "..url
	end
	local content
	if headers["content-encoding"] == "gzip" then
		local gzfile = tmpfile..".gz"
		lfs.move(tmpfile, gzfile)
		-- decompressed file
		log.debug(_NAME..": decompressing `"..gzfile.."' -> `"..tmpfile.."'")
		local file, err = gzip.open(gzfile)
		if not file then
			return nil, err
		end
		content = file:read("*a")
		file:close()
	else
		local file, err = io.open(tmpfile)
		if not file then
			return nil, err
		end
		content = file:read("*a")
		file:close()
	end
	lfs.delete(tmpfile)
	return content
end

return _M
