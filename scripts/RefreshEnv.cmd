@echo off
REM ============================================================================
REM RefreshEnv.cmd - 环境变量刷新脚本
REM ============================================================================
REM
REM 功能: 刷新当前终端的环境变量，使其反映最新的 Scoop 配置
REM
REM 使用方法:
REM   - 在 CMD 中直接运行: RefreshEnv
REM   - 在 PowerShell 中调用: cmd /c "RefreshEnv.cmd"
REM   - 在脚本中调用: call RefreshEnv.cmd
REM
REM ============================================================================

setlocal EnableDelayedExpansion

REM 设置编码支持中文
chcp 65001 >nul 2>&1

REM 设置日志文件路径
set "LOG_FILE=%TEMP%\RefreshEnv-%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%.log"

echo [RefreshEnv] 正在刷新环境变量...
echo [%TIME%] 开始刷新环境变量 >> "%LOG_FILE%"

REM 查找并调用 Scoop 的 refreshenv.cmd
set "SCOOP_REFRESH="
set "REFRESHED=0"
set "FOUND_PATH="

REM 方法1: 使用 SCOOP 环境变量
if defined SCOOP (
    if exist "!SCOOP!\shims\refreshenv.cmd" (
        set "FOUND_PATH=!SCOOP!\shims\refreshenv.cmd"
        call "!SCOOP!\shims\refreshenv.cmd"
        set REFRESHED=1
        echo [%TIME%] 使用 SCOOP 环境变量: !SCOOP! >> "%LOG_FILE%"
    )
)

REM 方法2: 使用默认用户目录
if "!REFRESHED!" == "0" (
    set "USER_SCOOP=%USERPROFILE%\scoop"
    if exist "!USER_SCOOP!\shims\refreshenv.cmd" (
        set "FOUND_PATH=!USER_SCOOP!\shims\refreshenv.cmd"
        call "!USER_SCOOP!\shims\refreshenv.cmd"
        set REFRESHED=1
        echo [%TIME%] 使用用户目录: !USER_SCOOP! >> "%LOG_FILE%"
    )
)

REM 方法3: 检查常见的安装目录（smartddd-claude-tools 等）
if "!REFRESHED!" == "0" (
    for %%d in (D E F C) do (
        if exist "%%d:\smartddd-claude-tools\scoop\shims\refreshenv.cmd" (
            set "FOUND_PATH=%%d:\smartddd-claude-tools\scoop\shims\refreshenv.cmd"
            call "%%d:\smartddd-claude-tools\scoop\shims\refreshenv.cmd"
            set REFRESHED=1
            echo [%TIME%] 使用自定义目录: %%d:\smartddd-claude-tools\scoop >> "%LOG_FILE%"
            goto :refresh_done
        )
        if exist "%%d:\scoop\shims\refreshenv.cmd" (
            set "FOUND_PATH=%%d:\scoop\shims\refreshenv.cmd"
            call "%%d:\scoop\shims\refreshenv.cmd"
            set REFRESHED=1
            echo [%TIME%] 使用根目录: %%d:\scoop >> "%LOG_FILE%"
            goto :refresh_done
        )
    )
)

:refresh_done

if "!REFRESHED!" == "1" (
    echo [OK] 环境变量已刷新
    echo [%TIME%] 刷新成功: !FOUND_PATH! >> "%LOG_FILE%"
) else (
    echo [!] 未找到 Scoop refreshenv.cmd
    echo     请确保 Scoop 已正确安装
    echo [%TIME%] 刷新失败: 未找到 Scoop >> "%LOG_FILE%"
    echo.
    echo 可选操作:
    echo   1. 确认 Scoop 安装路径
    echo   2. 手动运行: %%SCOOP%%\shims\refreshenv.cmd
    echo   3. 重启终端
    echo.
    echo 日志文件: %LOG_FILE%
)

echo [%TIME%] 刷新操作完成 >> "%LOG_FILE%"

endlocal
goto :eof
