// --------------------------------------------------------------------
//                                                                   --
// Copyright (C) 2007-2013,  AVIQ Bulgaria Ltd                       --
//                                                                   --
// Project:       AVTV                                               --
// Filename:      api.js                                             --
// Description:   EPG API WebService in NodeJS                       --
//                                                                   --
// -------------------------------------------------------------------- 

var redis = require("redis")
var restify = require("restify")
var apiV1 = require("./v1")

var server = restify.createServer(
{
	name: 'AVTV',
})

server.use(restify.gzipResponse());
server.use(restify.queryParser());
server.get(/v1\/(.*)/, apiV1(redis.createClient()))
server.get(/\/static\/*.*/, restify.serveStatic({
  directory: './node/epg'
}));

server.listen(9090, function() {
  console.log('%s listening at %s', server.name, server.url)
})
