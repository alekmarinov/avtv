local m = {}

function m:call (req, ...)
	req.headers["cookie"] = self.cookie
	return function (res)
		if res.headers["set-cookie"] then
			self.cookie = res.headers["set-cookie"]
		end
		return res
	end
end

return m
