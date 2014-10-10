-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2014,  AVIQ Bulgaria Ltd.                      --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      epg.lua                                            --
-- Description:   SmartXMedia EPG provider                                --
--                                                                   --
-----------------------------------------------------------------------

local dw      = require "lrun.net.www.download.luasocket"
local html    = require "lrun.parse.html"
local lom     = require "lxp.lom"
local lfs     = require "lrun.util.lfs"
local string  = require "lrun.util.string"
local config  = require "avtv.config"
local log     = require "avtv.log"
local logging = require "logging"
local json    = require "json"

local io, os, type, assert, ipairs, tostring, tonumber, table =
      io, os, type, assert, ipairs, tostring, tonumber, table

local print, pairs = print, pairs

module "avtv.provider.smartxmedia.epg"

local function downloadfile(url)
	log.debug(_NAME..": downloading `"..url.."'")
	local ok, code, headers = dw.download(url)
	if not ok then
		-- error downloading url
		return nil, code.." while downloading "..url
	end
	return ok
end

function channelurl(url)
	local user = config.getstring("epg.smartxmedia.channels.user")
	local pass = config.getstring("epg.smartxmedia.channels.pass")
	url = string.gsub(url, "http://", "http://"..user..":"..pass.."@")
	return url
end

local function parsechannelsjson(jsonstr)
	local channels = {}
	local jsdoc = json.decode(jsonstr)
	for i, ch in pairs(jsdoc.demo) do
		local channel = {
			id = ch.id,
			title = ch.name,
			streams = {{url=channelurl(ch.url)}},
			thumbnail = ch.image
		}
		table.insert(channels, channel)
	end
	return channels
end

-- updates SmartXMedia channels
function update(channelids, sink)
	local channelsurl = config.getstring("epg.smartxmedia.channels.url")
	local json, err = downloadfile(channelsurl)
	if not json then
		log.error(channelsurl.."->"..err)
		return nil, err
	end

	local channels, err = parsechannelsjson(json)
	if not channels then
		log.error(err)
		return nil, err
	end

	if not sink then
		sink = channelids
		assert(type(sink) == "function", "sink function argument expected")
		-- sink channels
		for _, channel in ipairs(channels) do
			if not sink(channel) then
				return nil, "interrupted"
			end
		end
	else
		-- no programs for this provider
	end
	return true
end

return _M
