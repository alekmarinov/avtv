-----------------------------------------------------------------------
--                                                                   --
-- Copyright (C) 2007-2015,  Intelibo Ltd                            --
--                                                                   --
-- Project:       AVTV                                               --
-- Filename:      images.lua                                         --
-- Description:   Manage storage of the static images                --
--                                                                   --
----------------------------------------------------------------------- 

local table    = require "lrun.util.table"
local lfs      = require "lrun.util.lfs"
local string   = require "lrun.util.string"
local log      = require "avtv.log"
local config   = require "avtv.config"
local base64   = require "base64"

local setmetatable, os, io =
      setmetatable, os, io

local print, pairs, type, assert = print, pairs, type, assert

module "avtv.images"

MOD_CHANNEL = "channel"
MOD_PROGRAM = "program"
MOD_VOD = "vod"

LOGO_SELECTED = "selected"
LOGO_FAVORITE = "favorite"
PROGRAM_IMAGE = "program_image"

local function mklogoname(imagefile, modifier, resolution)
	local ext = lfs.ext(imagefile)
	if modifier then
		modifier = "_"..modifier
	else
		modifier = ""
	end
	local logoname
	if modifier == PROGRAM_IMAGE then
		logoname = "placeholder"..ext
	else
		logoname = "logo"..modifier..ext
	end
	if resolution then
		logoname = lfs.concatfilenames(resolution, logoname)
	end
	return logoname
end

local function islogoname(imagefile)
	local imagename = lfs.stripext(lfs.basename(imagefile))
	return imagename == "logo" or imagename == "logo_"..LOGO_SELECTED or imagename == "logo_"..LOGO_FAVORITE or imagename == "logo_"..PROGRAM_IMAGE
end

 -- e.g., epg.bulsat.dir.static
local function getdirstatic(provider, modulename)
	local prefix = modulename
	if MOD_CHANNEL == modulename or MOD_PROGRAM == modulename then
		prefix = "epg"
	end
	return config.getstring(prefix.."."..provider..".dir.static")
end

local function collectimages(dirstatic, modulename)
	assert(modulename == MOD_CHANNEL or modulename == MOD_PROGRAM or modulename == MOD_VOD)

	local images = {}

	if not lfs.isdir(dirstatic) then
		return images
	end

	if MOD_CHANNEL == modulename or MOD_PROGRAM == modulename then
		for dirname in lfs.dir(dirstatic, "directory") do
			local dirpath = lfs.concatfilenames(dirstatic, dirname)

			for imagefile in lfs.dir(dirpath, "file") do
				local imagepath = lfs.concatfilenames(dirpath, imagefile)
				images[imagepath] = (islogoname(imagefile) and MOD_CHANNEL == modulename) or (not islogoname(imagefile) and MOD_PROGRAM == modulename)
				if images[imagepath] then
					log.debug(_NAME..": "..imagepath.." collected for deletion")
				else
					log.debug(_NAME..": "..imagepath.." skipped for deletion")
				end
			end
		end
	elseif MOD_VOD == modulename then
		for resolution in lfs.dir(dirstatic, "directory") do
			local dirpath = lfs.concatfilenames(dirstatic, resolution)
			for imagefile in lfs.dir(dirpath, "file") do
				local imagepath = lfs.concatfilenames(dirpath, imagefile)
				images[imagepath] = true
				log.debug(_NAME..": "..imagepath.." collected for deletion")
			end
		end
	end
	return images
end

local function deleteimages(imageset)
	for imagefile, isdel in pairs(imageset) do
		if isdel then
			log.info(_NAME..": deleting "..imagefile)
			os.remove(imagefile)
		end
	end
end

local function deleteemptydirs(dirpath)
	for dirname in lfs.dir(dirpath, "directory") do
		local delete = true
		local dircandidate = lfs.concatfilenames(dirpath, dirname)
		for trydir in lfs.dir(dircandidate) do
			delete = false
			break
		end
		if delete then
			log.info(_NAME..": deleting "..dircandidate)
			lfs.delete(dircandidate)
		end
	end
end

local function rename(filename1, filename2)
	os.remove(filename2)
	return os.rename(filename1, filename2)
end

-- add new channel logo
function _M:addchannellogo(channelid, imagepath, modifier, resolution)
	assert(type(channelid) == "string")
	assert(type(imagepath) == "string")
	assert(not resolution or type(resolution) == "string")
	assert(not modifier or modifier == LOGO_SELECTED or modifier == LOGO_FAVORITE or modifier == PROGRAM_IMAGE)

	local imagename = mklogoname(imagepath, modifier, resolution)
	local localpath = lfs.concatfilenames(self.dirstatic, channelid, imagename)
	if self.deleteimageset[localpath] then
		log.debug(_NAME..": undelete "..localpath)
		self.deleteimageset[localpath] = nil
	end
	lfs.mkdir(lfs.dirname(localpath))
	if resolution then
		log.debug(_NAME..": copy "..imagepath.." to "..localpath)
		local imagemagickexec = config.getstring("tool.imagemagick")
		local cmd = imagemagickexec.." -thumbnail "..resolution.." \""..imagepath.."\" \""..localpath.."\""
		local rc = os.execute(cmd)
		if rc ~= 0 then
			return nil, "Failed to execute "..cmd
		end
	else
		log.debug(_NAME..": rename "..imagepath.." to "..localpath)
		local ok, err = rename(imagepath, localpath) 
		if not ok then
			return nil, err
		end
	end
	-- encode to base64
	local file, err = io.open(localpath, "rb")
	if not file then
		return nil, err
	end
	local base64encoded = base64.encode(file:read("*a"))
	file:close()
	return imagename, base64encoded
end

-- add new program image
function _M:addprogramimage(channelid, imagepath, imagename, resolution)
	assert(type(channelid) == "string")
	assert(type(imagepath) == "string")
	assert(type(imagename) == "string")
	assert(type(resolution) == "string")
	local localpath = lfs.concatfilenames(self.dirstatic, channelid, resolution, imagename)
	if self.deleteimageset[localpath] then
		log.debug(_NAME..": undelete "..localpath)
		self.deleteimageset[localpath] = nil
	end
	log.debug(_NAME..": copy "..imagepath.." to "..localpath)
	lfs.mkdir(lfs.dirname(localpath))
	local imagemagickexec = config.getstring("tool.imagemagick")
	local cmd = imagemagickexec.." -thumbnail "..resolution.." \""..imagepath.."\" \""..localpath.."\""
	local rc = os.execute(cmd)
	if rc ~= 0 then
		return nil, "Failed to execute "..cmd
	end
	-- encode to base64
	local file, err = io.open(localpath, "rb")
	if not file then
		return nil, err
	end
	local base64encoded = base64.encode(file:read("*a"))
	file:close()
	return imagename, base64encoded
end

-- FIXME: handle image resolution
function _M:addvodimage(vodid, imagepath, resolution)
	assert(self.modulename == MOD_VOD)
	local ext = self.vodext
	if not ext then
		ext = lfs.ext(imagepath)
	end
	local imagename = vodid..ext
	local localpath = lfs.concatfilenames(self.dirstatic, resolution, imagename)
	if self.deleteimageset[localpath] then
		log.debug(_NAME..": undelete "..localpath)
		self.deleteimageset[localpath] = nil
	end
	local resultname = lfs.concatfilenames(resolution, imagename)
			
	log.debug(_NAME..": copy "..imagepath.." to "..localpath .. " - " ..lfs.dirname(localpath))
	lfs.mkdir(lfs.dirname(localpath))
	local imagemagickexec = config.getstring("tool.imagemagick")
	local cmd = imagemagickexec.." -thumbnail "..resolution.." \""..imagepath.."\" \""..localpath.."\""
	local rc = os.execute(cmd)
	if rc ~= 0 then
		return nil, "Failed to execute "..cmd
	end

	-- encode to base64
	local file, err = io.open(localpath, "rb")
	if not file then
		return nil, err
	end
	local base64encoded = base64.encode(file:read("*a"))
	file:close()

	return resultname, base64encoded
end

-- closes the image manager
function _M:close()
	-- delete the unused images
	deleteimages(self.deleteimageset)
	deleteemptydirs(self.dirstatic)
	self.deleteimageset = nil
	self.modulename = nil
end

-- opens the images for specified provider and module ("program", "channel", "vod")
-- vodext is optional and specifies the outout image format to be converted with ImageMagick
function new(provider, modulename, vodext)
	local o = setmetatable({}, {__index = _M})
	assert(modulename == MOD_CHANNEL or modulename == MOD_PROGRAM or modulename == MOD_VOD)

	o.provider = provider
	o.modulename = modulename
	o.vodext = vodext
	o.dirstatic = getdirstatic(provider, modulename)

	-- collect all existing images
	o.deleteimageset = collectimages(o.dirstatic, modulename)
	return o
end

return _M
