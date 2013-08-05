local rayvchannels = require "avtv.provider.rayv.channels"
local dom = rayvchannels.update("vtx")

function parsechannels()
	for i,v in ipairs(dom[1]) do
		if v.tag == "item" then
			local channel = {}
			for j, k in ipairs(v) do
				if k.tag == "guid" then
					channel.id = v[1]
				elseif k.tag == "title" then
					channel.title = v[1]
				elseif k.tag == "media:thumbnail" then
					channel.thumbnail = k.attr.url
					print("thumbnail = ", channel.thumbnail)
				end
			end
			break
		end
	end
end

parsechannels{}
