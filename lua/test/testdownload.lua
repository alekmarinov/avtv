local dw = require "lrun.net.www.download.luacurl"

-- rayv
--[[
local gzip = require "luagzip"

local xmlchannels = "http://md2.rayv-inc.com/V1/API/Channels/DistributorChannels?DistributorKey=vtx&ListType=All"
local filename = "channels.xml"

local ok, code, headers = dw.downloadfile(xmlchannels, filename)
if headers["content-encoding"] == "gzip" then
	print("decompressing...")
	local file = gzip.open(filename)
	print(file:read())
	file:close()
end
]]
local url = "http://www.wilmaa.com/channels/ch/founder500_de.xml"
local result, code, headers = dw.download(url, "test.xml", {proxy = "http://proxy.aviq.com:30228"})
print(result, code, headers)
if headers then
	for i,v in pairs(headers) do
		print(i,v)
	end
end
