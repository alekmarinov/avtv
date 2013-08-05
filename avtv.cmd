@ECHO OFF
SET OLD_LUA_PATH=%LUA_PATH%
SET LUA_PATH=%LUA_PATH%;%AVTV_HOME%/lua/?.lua
lua51 "%LRUN_SRC_HOME%\modules\lua\lrun\start.lua" avtv.main -c "%AVTV_HOME%/etc/avtv.conf" %*
SET LUA_PATH=%OLD_LUA_PATH%
