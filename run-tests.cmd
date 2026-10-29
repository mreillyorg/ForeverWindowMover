@echo off
rem Run every offline Lua harness. Thin launcher only: the runner itself is
rem tools\run_tests.py, so there is one implementation to maintain.
rem
rem Needs Python 3 and a Lua 5.1 interpreter. Set LUA51 to pick a specific one,
rem or pass -h for the options. For the full gate including luacheck, run
rem tools\check_lua_quality.py instead.
setlocal
python "%~dp0tools\run_tests.py" %*
if errorlevel 1 (
  echo.
  echo Harness failures above. Nothing was packaged.
  pause
  exit /b 1
)
echo.
echo All harnesses passed.
pause
