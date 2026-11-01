@echo off
rem One-click deploy from Windows: double-click, or run "deploy.cmd root@192.168.1.1".
rem Uses the ssh.exe and tar.exe built into Windows 10/11.
setlocal
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=root@10.99.99.1"
if "%SSH_KEY%"=="" set "SSH_KEY=%USERPROFILE%\.ssh\id_ed25519_gateway"
set "KEYOPT="
if exist "%SSH_KEY%" set KEYOPT=-i "%SSH_KEY%"
cd /d "%~dp0"

echo Deploying to %TARGET%...
tar -czf - install.sh uninstall.sh src | ssh -o ConnectTimeout=10 %KEYOPT% %TARGET% "sh -c 'rm -rf /tmp/os-telegram-alerts && mkdir -p /tmp/os-telegram-alerts && tar -xzf - -C /tmp/os-telegram-alerts && sh /tmp/os-telegram-alerts/install.sh'"
if errorlevel 1 (echo. & echo Deploy FAILED.) else (echo. & echo Deploy finished.)
pause
