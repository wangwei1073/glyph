@echo off
rem Glyph 启动器：双击运行，自动调用 R 后端并打开浏览器
chcp 65001 >nul
title Glyph - ggplot2 GUI

setlocal
cd /d "%~dp0"
set "PORT=4321"

rem ---- 探测 Rscript：先查常见安装目录与 PATH（本机自定义路径交给下方的 for 通配覆盖） ----
set "RSCRIPT="
if not defined RSCRIPT (
  for /d %%D in ("C:\Program Files\R\R-*") do if not defined RSCRIPT set "RSCRIPT=%%D\bin\Rscript.exe"
)
if not defined RSCRIPT (
  for /d %%D in ("D:\R\R-*") do if not defined RSCRIPT set "RSCRIPT=%%D\bin\Rscript.exe"
)
if not defined RSCRIPT where Rscript >nul 2>nul && set "RSCRIPT=Rscript"
if not defined RSCRIPT (
  echo [错误] 未找到 R。请安装 R 4.6+，或将其路径加入本脚本。
  pause
  exit /b 1
)

echo 使用 R: %RSCRIPT%
echo 启动 Glyph (http://127.0.0.1:%PORT%) ...
rem 浏览器等端口真正可连后再打开（最多等 20 秒），避免服务还没起来就弹错误页；
rem PowerShell 后台轮询，R 退出后这些子进程自然结束
start "" /b powershell -NoProfile -Command "for($i=0; $i -lt 40; $i++){ try { $c = New-Object Net.Sockets.TcpClient('127.0.0.1', %PORT%); $c.Close(); Start-Process 'http://127.0.0.1:%PORT%'; exit } catch { Start-Sleep -Milliseconds 500 } }"
"%RSCRIPT%" run.R --port %PORT%
pause
