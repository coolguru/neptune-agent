@echo off
rem Global variables
set NEPTUNEIOAGENT=nagent.py
set NEPTUNEIOAGENT_CONFIG=nagent.cfg
set NEPTUNEIOAGENT_STABLE_URL=https://raw.githubusercontent.com/neptuneio/nagent/prod/src

rem Set the endpoint
if [%NEPTUNE_ENDPOINT%] == [] (
  set END_POINT=www.neptune.io
) ELSE (
  set END_POINT=%NEPTUNE_ENDPOINT%
  set NEPTUNEIOAGENT_STABLE_URL="https://raw.githubusercontent.com/neptuneio/nagent/staging/src"
)

rem Check if python is installed
echo -------------------------------------
echo Checking for python dependency
python --version 2>NUL
if ERRORLEVEL 1 goto errorNoPython

echo Python is installed.
goto installAgent

:errorNoPython
echo.
echo Error^: Python not installed or is not in the path.
goto :EOF

:installAgent
rem Start install of agent
echo Installing Neptuneio agent...

rem Download pip directly and install
powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://bootstrap.pypa.io/get-pip.py', 'get-pip.py')"
python get-pip.py
DEL get-pip.py

rem Install pip packages
pip install -U simplejson
pip install -U boto
pip install -U requests

rem Create Neptune agent home directory
mkdir neptuneio

rem Fetch the latest stable neptune agent and neptune agent daemon
echo Fetching the latest stable version of neptuneio agent and daemon
powershell -Command "(New-Object System.Net.WebClient).DownloadFile('%NEPTUNEIOAGENT_STABLE_URL%/%NEPTUNEIOAGENT%', 'neptuneio\%NEPTUNEIOAGENT%')"

if [%NEPTUNEIO_KEY%] == [] (
echo Please set NEPTUNEIO_KEY in the environment and rerun this.
goto :EOF
)

rem Populate the neptuneio config
echo Populating neptuneio agent config
(
echo [NEPTUNEIO]
echo API_KEY=%NEPTUNEIO_KEY%
echo END_POINT=%END_POINT%
) > neptuneio\%NEPTUNEIOAGENT_CONFIG%

echo Running agent...
python neptuneio\%NEPTUNEIOAGENT%
