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
local lom    = require "lxp.lom"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs, tostring, table =
      io, os, type, assert, ipairs, tostring, table

local print, pairs = print, pairs

module "avtv.provider.bulsat_com.channels"

local function downloadchannellogo(channelid, channeluri, targetdir)
	local baseurl = config.getstring("epg.bulsat_com.baseurl")
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

local function downloadexternalchannellogo(channelid, logourl, targetdir)
	local thumbname = "logo"..lfs.ext(logourl)
	local thumbfile = lfs.concatfilenames(targetdir, thumbname)
	if not lfs.exists(thumbfile) then
		log.debug(_NAME..": downloading `"..logourl.."' to `"..thumbfile.."'")
		local ok, code = dw.download(logourl, thumbfile)
		if not ok then
			lfs.delete(thumbfile)
			-- error downloading channel logo image
			return nil, code.." while downloading "..logourl
		end
	end
	return thumbname
end

local function parseexternalchannels(xmlfile)
	log.debug(_NAME..": parsing `"..xmlfile.."'")
	local file, err = io.open(xmlfile)
	if not file then
		return nil, err
	end
	local xml = file:read("*a")
	local dom, err = lom.parse(xml)
	if not dom then
		return nil, err
	end
	local extchannels = {}
	local idgen = 1
	for i, v in ipairs(dom) do
		if type(v) == "table" and string.lower(v.tag) == "tvlists" then
			for j, k in ipairs(v) do
				if type(k) == "table" and string.lower(k.tag) == "tv" then
					local extchannel = {}
					for l, m in ipairs(k) do
						if type(m) == "table" then
							local tag = string.lower(m.tag)
							if tag == "epg_id" then
								extchannel.epg_id = m[1]
							elseif tag == "title" then
								extchannel.title = m[1]
							elseif tag == "logo" then
								extchannel.logo = m[1]
							elseif tag == "sources" then
								extchannel.sources = m[1]
							elseif tag == "has_dvr" then
								extchannel.has_dvr = string.lower(m[1]) == "true"
							elseif tag == "ndvr" then
								extchannel.ndvr = m[1]
							end
						end
					end
					if not extchannel.epg_id then
						extchannel.epg_id = "noname_"..idgen
						idgen = idgen + 1
					end
					table.insert(extchannels, extchannel)
				end
			end
		end
	end
	return extchannels
end

local function updatechannelswithexternal(channel, extchannels)
	for i, extchannel in ipairs(extchannels) do
		if extchannel.epg_id == channel.id then
			channel.streams = 
			{
				{
					url = extchannel.sources,
					has_dvr = extchannel.has_dvr,
					ndvr = extchannel.ndvr
				}
			}
			channel.description = extchannel.title
			return extchannel
		end 
	end
	return nil, "Can't map channel "..channel.id.." to external channels"
end

-- updates Bulsat channels and call sink callback for each new channel extracted
function update(sink)
	assert(type(sink) == "function", "sink function argument expected")
	local dirdata = lfs.concatfilenames(config.getstring("dir.data"), "bulsat", os.date("%Y%m%d"))
	local dirstatic = config.getstring("epg.bulsat_com.dir.static")
	lfs.mkdir(dirdata)
	lfs.mkdir(dirstatic)

	local extchannelsurl = config.getstring("epg.bulsat_com.channels.url")
	local extchannelsfile = lfs.concatfilenames(dirdata, "extchannels-"..os.date("%Y%m%d")..".xml")
	log.debug(_NAME..": downloading `"..extchannelsurl.."' to `"..extchannelsfile.."'")
	local ok, code, headers = dw.download(extchannelsurl, extchannelsfile)
	if not ok then
		-- error downloading file
		return nil, code.." while downloading "..extchannelsurl
	end

	local extchannels, err = parseexternalchannels(extchannelsfile)
	if not extchannels then
		return nil, err
	end

	local channelsfile = lfs.concatfilenames(dirdata, "channels".."-"..os.date("%Y%m%d")..".html")
	local ok, file, xml, err
	if not lfs.exists(channelsfile) then
		local channelsurl = lfs.concatfilenames(config.getstring("epg.bulsat_com.baseurl"), "tv-programa.php")
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
	local sinkedchannelsmap = {}
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
		local channel =
		{
			id = id,
			title = title
		}
		local extchannel = updatechannelswithexternal(channel, extchannels)
		local thumbname, err
		if extchannel then
			thumbname, err = downloadexternalchannellogo(id, extchannel.logo, logotargetdir)
			if not thumbname then
				log.error(err)
			else
				log.info("Downloaded "..extchannel.logo.." to "..thumbname)
			end
		else
			err = "Channel "..id.." has no mapped external channel"
		end
		if not thumbname then
			log.warn(_NAME..": "..err)
			thumbname, err = downloadchannellogo(id, channeluri, logotargetdir)
			if not thumbname then
				log.error(_NAME..": "..err)
			end
		end
		channel.thumbnail = thumbname
		-- sink channel
		log.info(_NAME..": extracted channel "..channel.id)
		sinkedchannelsmap[channel.id] = true
		if not sink(channel) then
			return nil, "interrupted"
		end
	end

	log.info(_NAME.."Importing unmapped external channels")
	for _, extchannel in ipairs(extchannels) do
		local id = extchannel.epg_id
		if not sinkedchannelsmap[id] then
			local logotargetdir = lfs.concatfilenames(dirstatic, id)
			local thumbname, err = downloadexternalchannellogo(id, extchannel.logo, logotargetdir)
			if not thumbname then
				log.error(err)
			else
				log.info("Downloaded "..extchannel.logo.." to "..thumbname)
			end
			local channel =
			{
				id = id,
				title = id,
				thumbnail = thumbname
			}
			assert(updatechannelswithexternal(channel, extchannels))
			-- sink channel
			log.info(_NAME..": extracted channel "..channel.id)
			if not sink(channel) then
				return nil, "interrupted"
			end
		end
	end
	return true
end

return _M
