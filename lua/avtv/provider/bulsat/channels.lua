-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2014,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      channels.lua                                       --
-- Description:   Bulsat channels provider                             --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local html   = require "lrun.parse.html"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs, tostring =
      io, os, type, assert, ipairs, tostring

local print, pairs = print, pairs

module "avtv.provider.bulsat.channels"

local function downloadchannellogo(channelid, channeluri, targetdir)
	local baseurl = config.getstring("epg.bulsat.baseurl")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"))
	local programsfile = lfs.concatfilenames(dirdata, "programs".."_"..channelid.."-"..os.date("%Y%m%d")..".html")
	local channelurl = baseurl..channeluri

	if not lfs.exists(programsfile) then
		log.debug(_NAME..": downloading `"..channelurl.."' to `"..programsfile.."'")
		local ok, code = dw.download(channelurl, programsfile)
		if not ok then
			-- error downloading programs html file
			return nil, code.." while downloading "..channelurl
		end
	end
	local file, err = io.open(programsfile)
	local htmltext = file:read("*a")
	file:close()
	local hom = html.parse(htmltext)
	local logouri = tostring(hom{ tag = "ul", id = "tvnav" }[1]{class="tab first"}[1].img[1]("src"))
	local thumbname = "logo"..lfs.ext(logouri)
	local thumbfile = lfs.concatfilenames(targetdir, thumbname)
	local logourl = baseurl.."/"..logouri

	if not lfs.exists(thumbfile) then
		log.debug(_NAME..": downloading `"..logourl.."' to `"..thumbfile.."'")
		ok, code = dw.download(logourl, thumbfile)
		if not ok then
			-- error downloading channel logo image
			return nil, code.." while downloading "..logourl
		end
	end
	return thumbname
end

-- updates Bulsat channels and call sink callback for each new channel extracted
function update(sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"))
	local dirstatic = config.getstring("epg.bulsat.dir.static")
	lfs.mkdir(dirdata)
	lfs.mkdir(dirstatic)
	local channelsfile = lfs.concatfilenames(dirdata, "programs".."-"..os.date("%Y%m%d")..".html")

	local ok, file, xml, err
	if not lfs.exists(channelsfile) then
		local channelsurl = lfs.concatfilenames(config.getstring("epg.bulsat.baseurl"), "tv-programa.php")
		log.debug(_NAME..": downloading `"..channelsurl.."' to `"..channelsfile.."'")
		local ok, code, headers = dw.download(channelsurl, channelsfile)
		if not ok then
			-- error downloading file
			return nil, code.." while downloading "..channelsurl
		end
	end

	-- parse channels html
	log.debug(_NAME..": parsing `"..channelsfile.."'")
	file, err = io.open(channelsfile)
	local htmltext = file:read("*a")
	file:close()
	local hom = html.parse(htmltext)
	local taglist = hom{ tag = "ul", id = "tvnav" }[1].li[3].div[2]{tag="a"}
	for i, entry in pairs(taglist) do
		local title = tostring(entry)
		title = string.gsub(title, ",.*", "")
		local channeluri = entry("href")
		local id
		string.gsub(channeluri, "go=(.*)", function (_id)
			id = _id
		end)
		local logotargetdir = lfs.concatfilenames(dirstatic, id)
		lfs.mkdir(logotargetdir)
		local thumbname, err = downloadchannellogo(id, channeluri, logotargetdir)
		if not thumbname then
			log.error(_NAME..": "..err)
		end
		local channel = {
			id = id,
			title = title,
			thumbnail = thumbname
		}
		-- sink channel
		log.info(_NAME..": extracted channel "..channel.id)
		if not sink(channel) then
			return nil, "interrupted"
		end
	end
	return true
end

return _M
