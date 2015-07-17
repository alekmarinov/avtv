@ECHO OFF
SET LUA_BIN=D:\Projects\AVIQ\LRun\svn\config\codeblocks\bin\Release
SET OLD_LUA_PATH=%LUA_PATH%
SET OLD_LUA_CPATH=%LUA_CPATH%
SET OLD_PATH=%PATH%

SET LRUN_SRC_HOME=d:\Projects\AVIQ\LRun\svn
SET MOD_LUA=%LRUN_SRC_HOME%/modules/lua
SET LUA_PATH=%LUA_PATH%;?.lua;%AVTV_HOME%/lua/?.lua;%MOD_LUA%/?.lua;%MOD_LUA%/logging/?.lua;%MOD_LUA%/socket/?.lua;%MOD_LUA%/redis/?.lua;%MOD_LUA%/spore/?.lua;d:\Projects\AVIQ\LRun\projects\lua\luasolr\lua\?.lua
SET LUA_CPATH=%LUA_BIN%\lua\5.1\?.dll
SET PATH=%LUA_BIN%\bin;%AVTV_HOME%\bin
lua51 "%LRUN_SRC_HOME%\modules\lua\lrun\start.lua" avtv.main -c "%AVTV_HOME%/etc/avtv.conf" %*
SET LUA_PATH=%OLD_LUA_PATH%
SET LUA_CPATH=%OLD_LUA_CPATH%
SET PATH=%OLD_PATH%
SET LUA_BIN=