@echo off
rem Glyph 启动器：双击运行，自动调用 R 后端并打开浏览器
chcp 65001 >nul
title Glyph - ggplot2 GUI

setlocal
cd /d "%~dp0"
set "PORT=4321"
set "PYTHONIOENCODING=utf-8"

rem ---- 探测 Rscript：优先 R-4.6.1，其次已安装的各版本 ----
set "RSCRIPT="
if exist "D:\R\R-4.6.1\bin\Rscript.exe" set "RSCRIPT=D:\R\R-4.6.1\bin\Rscript.exe"
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
start "" /b cmd /c "timeout /t 4 /nobreak >nul & start http://127.0.0.1:%PORT%"
"%RSCRIPT%" run.R --port %PORT%
pause
