// --------------------------------------------------------------------
//                                                                   --
// Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
//                                                                   --
// Project:       AVTV                                               --
// Filename:      v1.js                                              --
// Description:   EPG API V1                                         --
//                                                                   --
// -------------------------------------------------------------------- 

var CMD_CHANNELS = "channels"
var CMD_PROGRAMS = "programs"

function onError(err, res, next)
{
	if (err)
	{
		console.log("Error: " + err)
		res.send(500)
		next()
		return false
	}
	return true
}

function rawQuery(res, next, rclient, keyArr)
{
	var PATTERNS_ALLOW =
	[
		"^[^\\.]+\\." // something . something
	]

	// extract query key
	var keys = 'epg.' + keyArr.join('.')

	// validates if the key is allowed
	var isAllowed = PATTERNS_ALLOW.some(function eachAllowed(allow)
	{
		return keys.match(allow)
	})
	if (!isAllowed)
	{
		res.send(403)
		next()
		return false;
	}

	// request all keys in epg namespace
	return rclient.keys(keys + '*', function onKeys(err, resKeys)
	{
		if (err) return onError(err, res, next)
		if (resKeys.length == 0)
		{
			res.send(404)
			next()
			return ;
		}
		// request all key values
		rclient.mget(resKeys, function onMGet(err, resValues)
		{
			if (err) return onError(err, res, next)
			var json
			if (resKeys.length == 1 && resKeys[0].length == keys.length)
			{
				json = resValues[0]
			}
			else
			{
				var stripKey = keys.length + 1;
				// create json object { key = value }
				json = {}
				for (var i = 0; i < resKeys.length; i++)
				{
					json[resKeys[i].substring(stripKey)] = resValues[i]
				}
			}
			res.send(json)
			next()
		})
	})
}

function channelsQuery(res, next, rclient, params)
{
	if (params.length < 1)
	{
		res.send(403)
		next()
		return false;
	}
	// extract provider
	var provider = params[0]
	var prefix = 'epg.' + provider + '.'
	switch (params.length)
	{
		case 1:
			// use redis sort to extract additional objects info
			return rclient.sort(prefix + 'channels', 'by', 'nosort', 'get', '#', 'get', prefix + '*.title', 'get', prefix + '*.thumbnail', function onSortChannels(err, channelrows)
			{
				if (err) return onError(err, res, next)
				if (channelrows.length > 0)
				{
					var json = []
					for (var i = 0; i < channelrows.length / 3; i++)
					{
						json.push({id: channelrows[i * 3], title: channelrows[i * 3 + 1], thumbnail: channelrows[i * 3 + 2]})
					}
					res.send(json)
				}
				else
				{
					res.send(404)
				}
				next()
			});
		break;
		case 2:
			var channelId = params[1]
			// request channel info
			prefix = prefix + channelId + '.'
			return rclient.mget(prefix + 'id', prefix + 'title', prefix + 'thumbnail', function onMGet(err, resValues)
			{
				if (err) return onError(err, res, next)
				if (resValues[0] != null)
				{
					var json = {
						id: resValues[0],
						title: resValues[1],
						thumbnail: resValues[2]
					}
					res.send(json)
				}
				else
				{
					res.send(404)
				}
				next()
			})
		break;
		default:
			return rawQuery(res, next, rclient, params);
		break;
	}
}

function programsQuery(res, next, rclient, params)
{
	if (params.length < 2)
	{
		res.send(403)
		next()
		return false;
	}

	if (params.length == 2)
	{
		// extract provider and channelId
		var provider = params[0]
		var channelId = params[1]
		var prefix = 'epg.' + provider + '.' + channelId + '.'

		// use redis sort to extract additional objects info
		return rclient.sort(prefix + 'programs', 'get', '#', 'get', prefix + '*.stop', 'get', prefix + '*.title', function onSortPrograms(err, programsrows)
		{
			if (err) return onError(err, res, next)
			if (programsrows.length > 0)
			{
				var json = []
				for (var i = 0; i < programsrows.length / 3; i++)
				{
					json.push({id: programsrows[i * 3], stop: programsrows[i * 3 + 1], title: programsrows[i * 3 + 2]})
				}
				res.send(json)
			}
			else
			{
				res.send(404)
			}
		});
	}
	else
	{
		return rawQuery(res, next, rclient, params);
	}
}

function apiV1(rclient)
{
	return function respond(req, res, next)
	{
		var params = req.params[0]

		// strip last / if any
		if (params.charAt(params.length-1) == '/')
			params = params.substring(0, params.length-1)

		// strip to array
		var params = params.split('/')

		// strip empty params
		for (var i = 0; i < params.length; i++)
		{
			if (params[i].length == 0)
			{
				params.splice(i, 1)
				i--;
			}
		}

		// get command
		var cmd = params[0]
		params = params.slice(1)

		switch (cmd)
		{
			case CMD_CHANNELS:
				return channelsQuery(res, next, rclient, params)
			break;
			case CMD_PROGRAMS:
				return programsQuery(res, next, rclient, params)
			break;
			default:
				res.send(404)
				next();
			break;
		}
		return false
	}
}

module.exports = apiV1
