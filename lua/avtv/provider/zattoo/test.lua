local Spore = require 'Spore'

Spore.debug = io.stdout
local zapi = Spore.new_from_spec 'zapi.json'

zapi:enable 'Format.JSON'
zapi:enable('zattoo.ZapiCookie')

function dumpres(name, res)
	print(name.."...")
	for i,v in pairs(res) do
		print(i,v)
	end
end

hellores = zapi:hello{
	app_tid = "a48d93cd-0247-4225-8063-301d540f3553",
	uuid = "c7fb5bb2-c201-4b3a-9b76-7c25d5090cad",
	lang = "en"
}
dumpres("hello", hellores)

pghash = hellores.body.session.power_guide_hash
loginres = zapi:login{login="samtest@zattoo.com", password="12345"}
dumpres("login", loginres)

res = zapi:channels()
dumpres("res", res.body)
os.exit()

channels = res.body.channels
for i, channel in ipairs(channels) do
	dumpres("channels "..i, channel)
	assert(channel.logo_84)
end
os.exit()

local DAYSECS = 24*60*60

function getprograms(dayofs)
	function rndtime(time)
		return os.time{year=os.date("%Y", time), month=os.date("%m", time), day=os.date("%d", time), hour=os.date("%H", time)}
	end

	function frmtime(time)
		return os.date("%Y-%m-%dT%H:00:00", time)
	end

	function timeofs(ofs)
		return rndtime(os.time() + ofs)
	end

	local timefrom = dayofs * DAYSECS
	local timeto = (dayofs + 1) * DAYSECS

	print("from = ", frmtime(timeofs(timefrom)), ", to = ", frmtime(timeofs(timeto)))

	programsres = zapi:programs{start = timeofs(timefrom), ["end"] = timeofs(timeto), pghash = pghash}
	for i, channel in ipairs(programsres.body.channels) do
		print("programs of "..channel.cid)
		for j, program in ipairs(channel.programs) do
			programdetailsres = zapi:programdetails{program_id = program.id, complete="True"}
			program = programdetailsres.body.program
			dumpres(j..". ", program)
			print("credits")
			for m, n in pairs(program.credits) do
				dumpres("credit "..m, n)
			end
			print("end of credits")
			if j == 5 then break end
		end
		break
	end
end

for day = 0, 0 do
	print("============== DAY "..day)
	getprograms(day)
	print()
end
