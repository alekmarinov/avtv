-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      programs.lua                                       --
-- Description:   Bulsat programs provider                           --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local html   = require "lrun.parse.html"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"
local utf8   = require "unicode"

local io, os, type, assert, ipairs, table, tonumber, tostring =
      io, os, type, assert, ipairs, table, tonumber, tostring
local print, pairs = print, pairs

module "avtv.provider.bulsat_com.programs"

local MonthNames = {"януари", "февруари", "март", "април", "май", "юни", "юли", "август", "септември", "октомври", "ноември", "декември"}

local function monthindex(monthname)
	for i, name in ipairs(MonthNames) do
		if monthname == name then
			return i
		end
	end
end

-- updates Bulsat programs for given channel list and call sink callback for each new program extracted
function update(channelids, sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"))
	for _, channelid in ipairs(channelids) do
		local programsfile = lfs.concatfilenames(dirdata, "programs".."_"..channelid.."-"..os.date("%Y%m%d")..".html")
		if not lfs.exists(programsfile) then
			local channelurl = lfs.concatfilenames(config.getstring("epg.bulsat_com.baseurl"), "tv-programa.php")
			channelurl = channelurl.."?go="..channelid
			local ok, code = dw.download(channelurl, programsfile)
			if not ok then
				log.error(_NAME..": "..code.." while downloading "..channelurl)
			end
		end

		log.debug(_NAME..": parsing `"..programsfile.."'")
		local file, err = io.open(programsfile)
		local htmltext = file:read("*a")
		file:close()
		local hom = html.parse(htmltext)
		local programs = hom{ tag="div", class="prgdetails" }
		local lastprogram
		for _, prg in ipairs(programs) do
			local program = {
				title = tostring(prg.h2[1]),
				description = tostring(prg.p[2])
			}
			local datetime = tostring(prg.p[1])
			local YY = os.date("%Y")
			local mm, DD, HH, MM
			string.gsub(datetime, ".-(%d+) (.-), (%d%d):(%d%d)", function (day, month, hour, min)
				mm = string.format("%02d", monthindex(utf8.lower(month)))
				DD = string.format("%02d", tonumber(day))
				HH = string.format("%02d", tonumber(hour))
				MM = string.format("%02d", tonumber(min))
			end)
			program.id = YY..mm..DD..HH..MM.."00"

			-- sink program
			log.debug(_NAME..": extracted program "..channelid.."/"..program.id)
			if lastprogram then
				lastprogram.stop = program.id
				if not sink(channelid, lastprogram) then
					return nil, "interrupted"
				end
			end
			lastprogram = program
		end
	end
	return true
end

return _M
