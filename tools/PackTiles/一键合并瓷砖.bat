@echo off
chcp 65001 >nul
title 瓷砖图集自动合并工具
cd /d "%~dp0"
echo ==================================================
echo   瓷砖图集自动合并工具 (Pack Tiles Atlas)
echo   目标目录: %~dp0
echo ==================================================
echo.
python "%~dp0pack_tiles.py"
echo.
pause

