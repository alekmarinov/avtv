redis = require "lrun.db.redis"
table = require "lrun.util.table"

rcli = redis.connect{
    host = '127.0.0.1',
    port = 6379,
}

--[[ INSERT
local wilmaa = {
	channels = {
		{ id = "tele_1",  channel_group_id = "tele_1", category = "Sports", short_name = "Tele 1", name = "Tele 1", language = "de" },
		{ id = "rts_un_hd",  channel_group_id = "rts_un", category = "Information", short_name = "RTS1HD", name = "RTS UN HD", language = "fr" }
	},
	programs = {
		{ id = 76541851, channel_id = "3_plus", startsFrom = 1373436000, endsTo = 1373439600, title = "Eso.tv", subtitle = "", genre = "Information", subgenre = "newsinformation", image_id = "" }
	}
}
rcli{
	wilmaa = wilmaa
}

wilmaa.programs(
	{id = 99999999, channel_id = "4_plus", startsFrom = 1111111111, endsTo = 2222222222, title = "title", subtitle = "subtitle", genre = "genre", subgenre = "subgenre", image_id = "image_id" },
	{id = 99999998, channel_id = "5_plus", startsFrom = 3333333333, endsTo = 4444444444, title = "title2", subtitle = "subtitle2", genre = "genre2", subgenre = "subgenre2", image_id = "image_id2" }
)

wilmaa.categories = 
{
	{id = "news" },
	{id = "documentary" },
	{id = "nature" }
}

wilmaa.categories[1].subcategories = {
	{ id = "news-sub1" }, { id = "news-sub2" }, { id = "news-sub3" }
}

wilmaa.categories[2].subcategories = {
	{ id = "documentary-sub1"}, { id = "documentary-sub2" }, { id = "documentary-sub3" }
}

wilmaa.categories[3].subcategories = {
	{ id = "nature-sub1" }, { id = "nature-sub2" }, { id = "nature-sub3" }
}
]]

--[[ RETRIEVE
-- print(table.makestring(rcli.wilmaa.channels.tele2))

for i,v in ipairs(rcli.wilmaa.channels["tele_?"]) do
	print(i, "wilmaa.channels."..v.."->"..rcli.wilmaa.channels[v])
end
--]]


--[[ UNUSUAL
rcli.wilmaa.channels = {
	{
		category = "NEWS2",
		channel_group_id = "TV2",
		language = "bg",
		name = "TV 2",
		short_name = "TV 2",
		--id = "tv1"
	}
}
]]

--[[ UPDATE

rcli.wilmaa.channels.tele2 = {
	category = "Show",
	channel_group_id = "tele",
	language = "bg",
	name = "Tele 2",
	short_name = "Tele 2",
	id = "tele2"
}

rcli.wilmaa.channels.tele2.category = "No Show"
print(rcli.wilmaa.channels.tele2.category)

rcli.wilmaa.channels.tele2 = {
	category = "Mega Show"
}
print(rcli.wilmaa.channels.tele2.category)
]]

--[[ DISCONNECT
print(rcli.wilmaa.channels.tele2.category)
rcli:disconnect()
print(rcli.wilmaa.channels.tele2.category) -- error 'closed'
--]]

--[[ DELETE
channels = rcli.wilmaa.channels

channels.tele1 = { name = "Tele 1", bame = "Tele 2"}
channels.tele1.__delete("?ame")

rcli.wilmaa.channels.tele1.id="tele1"
print(rcli.wilmaa.channels.tele1.id)
print(rcli.wilmaa.channels.tele1.__delete("id"))
print(rcli.wilmaa.channels.tele1.__delete("id"))
print(rcli.wilmaa.channels.tele1.id.__exists())
--]]

rcli["prop1.prop2.value"].delete()
print(rcli["prop1.prop2.value"].exists())
