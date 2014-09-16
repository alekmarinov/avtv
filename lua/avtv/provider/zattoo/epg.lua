-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2014,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      epg.lua                                            --
-- Description:   Zattoo EPG provider                                --
--                                                                   --
-----------------------------------------------------------------------

local dw     = require "lrun.net.www.download.luasocket"
local Spore  = require "Spore"
local lfs    = require "lrun.util.lfs"
local string = require "lrun.util.string"
local config = require "avtv.config"
local log    = require "avtv.log"

local io, os, type, assert, ipairs, tostring, tonumber, table =
      io, os, type, assert, ipairs, tostring, tonumber, table

local print, pairs = print, pairs

module "avtv.provider.zattoo.epg" 

local DAYSECS = 24 * 60 * 60


local function downloadlogo(channelid, url)
	local function stripquery(u)
		u = string.gsub(u, "%?.*", "")
		return u
	end
	local ext = lfs.ext(stripquery(url))
	local thumbname = "logo"..ext
	local dirstatic = config.getstring("epg.zattoo.dir.static")
	local thumbfile = lfs.concatfilenames(dirstatic, channelid, thumbname)
	lfs.mkdir(lfs.dirname(thumbfile))
	log.debug(_NAME..": downloading `"..url.."' to `"..thumbfile.."'")
	ok, err = dw.download(url, thumbfile)
	if not ok then
		log.warn(_NAME..": "..err)
	else
		return thumbname
	end 
end

local function handleres(reqtag, res)
	if not res.body.success then
		local errmsg = "Error in "..reqtag
		if res.body.http_status then
			errmsg = errmsg..", http_status = "..res.body.http_status
		end
		if res.body.internal_code then
			errmsg = errmsg..", internal_code = "..res.body.internal_code
		end
		return nil, errmsg
	end
	return true
end

local function zapicreate(zapispec)
	zapispec = lfs.path(zapispec)
	-- initializes Spore with ZAPI spec
	Spore.debug = io.stdout
	log.info(_NAME..": zapicreate.zapispec = "..zapispec)
	local zapi = Spore.new_from_spec(zapispec)
	zapi:enable 'Format.JSON'
	zapi:enable('zattoo.ZapiCookie')

	-- say hello to ZAPI
	local res = zapi:hello{
		app_tid = config.getstring("epg.zattoo.app_tid"),
		uuid = config.getstring("epg.zattoo.uuid"),
		lang = config.getstring("epg.zattoo.lang")
	}

	local ok, err = handleres("hello", res)
	if not ok then
		return nil, err
	end

	zapi._pghash = res.body.session.power_guide_hash

	return zapi
end

local function zapilogin(zapi)
	-- ZAPI login
	res = zapi:login{
		login = config.getstring("epg.zattoo.username"),
		password = config.get("epg.zattoo.password")
	}
	return handleres("login", res)
end

local function loadchannels(zapi, sink)
	-- load channels
	res = zapi:channels()
	local ok, err = handleres("channels", res)
	if not ok then
		return nil, err
	end
	for _, channelinfo in ipairs(res.body.channels) do
		local thumbnail, err = downloadlogo(channelinfo.cid, channelinfo.logo_84)
		if not thumbnail then
			log.error(_NAME..": "..(err or "unknown error"))
		end
		local channel = {
			id = channelinfo.cid,
			title = channelinfo.title,
			thumbnail = thumbnail
		}
		ok, err = sink(channel)
		if not ok then
			return nil, err
		end
	end
	return true
end

local function loadprograms(zapi, channelids, sink)
	local ok, err
	-- load programs day by day
	for day = -config.getnumber("epg.zattoo.dayspast"), config.getnumber("epg.zattoo.daysfuture") do
		local function rndtime(time)
			return os.time{year=os.date("%Y", time), month=os.date("%m", time), day=os.date("%d", time), hour=os.date("%H", time)}
		end

		local function frmtime(time)
			return os.date("%Y-%m-%dT%H:00:00", time)
		end

		local function timeofs(ofs)
			return rndtime(os.time() + ofs)
		end

		local function mktime(ztime)
			-- 2014-06-19T15:30:15Z
			ztime = string.gsub(ztime, "%-", "")
			ztime = string.gsub(ztime, "T", "")
			ztime = string.gsub(ztime, ":", "")
			ztime = string.gsub(ztime, "Z", "")
			return ztime
		end

		local timefrom = day * DAYSECS
		local timeto = (day + 1) * DAYSECS

		-- load channels and programs
		res = zapi:programs{start = timeofs(timefrom), ["end"] = timeofs(timeto), pghash = zapi._pghash}
		ok, err = handleres("programs", res)
		if not ok then
			return nil, err
		end
		for _, channelinfo in ipairs(res.body.channels) do
			log.info(_NAME..": Extracting channel "..channelinfo.cid)
			for _, programinfo in ipairs(channelinfo.programs) do
				-- load program details
				res = zapi:programdetails{
					program_id = programinfo.id,
					complete="True"
				}
				ok, err = handleres("programdetails", res)
				if not ok then
					log.error(_NAME..": "..err)
					-- will not stop for one program details error, continue with next programs
				else
					local programdetails = res.body.program
					local program = {
						id = mktime(programdetails.start),
						stop = mktime(programdetails["end"]),
						description = programdetails.description,
						credits = programdetails.credits,
						year = programdetails.year,
						country = programdetails.country,
						categories = programdetails.categories,
						title = programdetails.title,
						episode_title = programdetails.episode_title
					}
					ok, err = sink(channelinfo.cid, program)
					if not ok then
						return nil, err
					end
				end
			end
		end
	end
	return true
end

-- updates Zattoo channels or programs and call sink callback for each new channel or program extracted
function update(channelids, sink)
	local zapispec = "file://"..config.getstring("epg.zattoo.zapi_spore")
	local zapi = assert(zapicreate(zapispec))
	assert(zapilogin(zapi))

	if not sink then
		sink = channelids
		assert(type(sink) == "function", "sink function argument expected")
		-- sink channels
		return loadchannels(zapi, sink)
	else
		assert(type(sink) == "function", "sink function argument expected")
		-- sink programs
		return loadprograms(zapi, channelids, sink)
	end
	return true
end
