@ECHO OFF
SET OLD_LUA_PATH=%LUA_PATH%

SET MOD_LUA=%LRUN_SRC_HOME%/modules/lua
SET LUA_PATH=%LUA_PATH%;?.lua;%AVTV_HOME%/lua/?.lua;%MOD_LUA%/?.lua;%MOD_LUA%/logging/?.lua;%MOD_LUA%/socket/?.lua;%MOD_LUA%/redis/?.lua;%MOD_LUA%/spore/?.lua;
lua51 "%LRUN_SRC_HOME%\modules\lua\lrun\start.lua" avtv.main -c "%AVTV_HOME%/etc/avtv.conf" %*
SET LUA_PATH=%OLD_LUA_PATH%
