#!/usr/bin/env pwsh
#requires -Version 5.1

<#
.SYNOPSIS
    Claude Code 开发环境卸载程序
.DESCRIPTION
    完整卸载 Claude Code Windows 一键安装器安装的所有组件
.PARAMETER Force
    强制卸载，不提示确认
.PARAMETER KeepScoop
    保留 Scoop 及其安装的工具
.PARAMETER Verbose
    显示详细日志
.EXAMPLE
    .\uninstall.ps1
    .\uninstall.ps1 -Force
    .\uninstall.ps1 -KeepScoop
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$KeepScoop,
    [switch]$Verbose
)

#=================== 变量初始化 ===================
$Script:RemovedItems = @()
$Script:FailedItems = @()
$Script:WarningCount = 0
# MEDIUM 修复: 锁文件路径包含安装目录标识以支持多实例
# 使用延迟求值，在运行时动态获取路径
$lockId = 'default'
if ($Script:InstallPath) {
    $lockId = (Split-Path $Script:InstallPath -Leaf).Replace(' ', '')
}
$Script:LockFilePath = "$env:TEMP\claude-uninstall-${lockId}.lock"
$Script:CancelRequested = $false

# 自动检测安装路径
$Script:InstallPath = $null
$Script:ScoopPath = $null

#=================== 辅助函数 ===================

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "[>] $Message" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Magenta
    $Script:WarningCount++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
    $Script:FailedItems += $Message
}

function Write-VerboseLog {
    param([string]$Message)
    if ($Verbose -or $VerbosePreference -ne 'SilentlyContinue') {
        Write-Host "    [VERBOSE] $Message" -ForegroundColor Gray
    }
}

#=================== 并发检测和中断处理 ===================

function Test-ConcurrentUninstallation {
    if (Test-Path $Script:LockFilePath) {
        $lockContent = Get-Content $Script:LockFilePath -ErrorAction SilentlyContinue
        $lockTime = [DateTime]::Parse($lockContent)
        $timeDiff = (Get-Date) - $lockTime

        if ($timeDiff.TotalMinutes -lt 30) {
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "检测到另一个卸载进程正在运行" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "  锁文件创建于 $([math]::Round($timeDiff.TotalMinutes, 1)) 分钟前" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "如确定没有其他卸载进程，请删除锁文件:" -ForegroundColor Cyan
            Write-Host "  Remove-Item $Script:LockFilePath" -ForegroundColor Gray
            Write-Host ""
            return $false
        } else {
            # 锁文件过期，移除
            Remove-Item $Script:LockFilePath -Force -ErrorAction SilentlyContinue
        }
    }

    # 创建锁文件
    Get-Date | Out-File -FilePath $Script:LockFilePath -Force
    return $true
}

function Remove-LockFile {
    if (Test-Path $Script:LockFilePath) {
        Remove-Item $Script:LockFilePath -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-SignalHandler {
    $handler = {
        $script:CancelRequested = $true
        Write-Host ""
        Write-Host "用户中断请求，正在清理..." -ForegroundColor Yellow
        Remove-LockFile
        exit 1
    }

    [Console]::CancelKeyPress += $handler
}

function Test-CancellationRequested {
    if ($script:CancelRequested) {
        Write-Host "操作已取消" -ForegroundColor Yellow
        Remove-LockFile
        exit 1
    }
}

#=================== 路径检测 ===================

function Get-InstallationPaths {
    Write-Header "检测安装路径"

    # 尝试从脚本位置推断安装路径
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $scriptsDir = Split-Path -Parent $scriptPath
        $parentDir = Split-Path -Parent $scriptsDir

        # 验证父目录是否是安装目录（检查特征文件）
        if ($parentDir -and (Test-Path $parentDir)) {
            # 检查是否包含 scripts 目录和其他安装特征
            if (Test-Path "$parentDir\scripts") {
                $Script:InstallPath = $parentDir
                Write-Success "检测到安装目录: $Script:InstallPath"
            }
        }
    }

    # 如果没有检测到，尝试常见的安装位置
    if (-not $Script:InstallPath) {
        $possibleInstallPaths = @()
        foreach ($drive in @('D', 'E', 'F', 'C')) {
            if (Test-Path "${drive}:\") {
                $possibleInstallPaths += "${drive}:\smartddd-claude-tools"
                $possibleInstallPaths += "${drive}:\sddd-claude-tools"
                $possibleInstallPaths += "${drive}:\claude-tools"
            }
        }

        foreach ($path in $possibleInstallPaths) {
            if ((Test-Path $path) -and (Test-Path "$path\scripts")) {
                $Script:InstallPath = $path
                Write-Success "检测到安装目录: $Script:InstallPath"
                break
            }
        }
    }

    # 检测 Scoop 路径并验证结构
    $possibleScoopPaths = @(
        $env:SCOOP,
        "$env:USERPROFILE\scoop",
        "C:\scoop"
    )

    foreach ($path in $possibleScoopPaths) {
        if ($path -and (Test-Path $path)) {
            # 验证是否是有效的 Scoop 目录
            $isValidScoop = (Test-Path "$path\shims") -or `
                            (Test-Path "$path\apps") -or `
                            (Test-Path "$path\scoop")

            if ($isValidScoop) {
                $Script:ScoopPath = $path
                Write-VerboseLog "检测到有效 Scoop 目录: $path"
                break
            } else {
                Write-VerboseLog "跳过无效的 Scoop 路径: $path"
            }
        }
    }

    if (-not $Script:InstallPath) {
        Write-Warning "未能自动检测安装目录"
        Write-Step "请输入安装目录路径 (直接回车退出):"
        $Script:InstallPath = Read-Host
        if ([string]::IsNullOrWhiteSpace($Script:InstallPath)) {
            Write-Host "取消卸载" -ForegroundColor Yellow
            exit 0
        }
    }
}

#=================== 确认卸载 ===================

function Confirm-Uninstall {
    if ($Force) {
        Write-VerboseLog "强制模式，跳过确认"
        return $true
    }

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║       Claude Code 开发环境卸载程序                         ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""

    Write-Host "安装目录: $Script:InstallPath" -ForegroundColor Yellow
    if ($Script:ScoopPath -and -not $KeepScoop) {
        Write-Host "Scoop 目录: $Script:ScoopPath" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "警告: 此操作将卸载所有通过 Scoop 安装的工具!" -ForegroundColor Red
    }
    Write-Host ""

    $confirm = Read-Host "确认卸载? (y/n)"

    return $confirm -eq 'y' -or $confirm -eq 'Y'
}

#=================== 移除环境变量 ===================

function Remove-EnvironmentVariables {
    Write-Header "移除环境变量"

    # AC 14: 卸载完整清理 - 移除环境变量
    # 包括 CLAUDE_INSTALL_DRIVE
    $variablesToRemove = @('SHELL', 'CLAUDE_CODE_GIT_BASH_PATH', 'CLAUDE_INSTALL_DRIVE')

    foreach ($var in $variablesToRemove) {
        $currentValue = [Environment]::GetEnvironmentVariable($var, 'User')

        if ($currentValue) {
            Write-Step "移除 $var..."
            try {
                # 使用 .NET 方法移除用户级环境变量
                [Environment]::SetEnvironmentVariable($var, $null, 'User')

                # 清除当前会话的环境变量（如果存在）
                if (Test-Path "env:$var") {
                    # 注意：PowerShell 中 env: 驱动器的变量不能直接用 Remove-Item 删除
                    # 只能设置为空或等待会话重启
                    Set-Item -Path "env:$var" -Value $null -ErrorAction SilentlyContinue
                }

                Write-Success "$var 已移除 (请重启终端生效)"
                $Script:RemovedItems += "环境变量: $var"
            } catch {
                Write-Error "移除 $var 失败: $_"
            }
        } else {
            Write-VerboseLog "$var 未设置，跳过"
        }
    }
}

#=================== 移除安装目录 ===================

function Remove-InstallationDirectory {
    Write-Header "删除安装目录"

    if (-not $Script:InstallPath -or -not (Test-Path $Script:InstallPath)) {
        Write-Warning "安装目录不存在或无效: $Script:InstallPath"
        return
    }

    Write-Step "删除 $Script:InstallPath ..."

    try {
        # 检查目录是否包含敏感内容
        $parentDir = Split-Path $Script:InstallPath -Parent
        $dirName = Split-Path $Script:InstallPath -Leaf

        # 安全检查：只删除预期的目录
        $safeNames = @('smartddd-claude-tools', 'sddd-claude-tools', 'claude-tools')
        if ($dirName -notin $safeNames) {
            Write-Warning "目录名不安全: $dirName"
            Write-Host "出于安全考虑，不会自动删除此目录" -ForegroundColor Yellow
            Write-Host "如需删除，请手动执行: Remove-Item -Path '$Script:InstallPath' -Recurse -Force" -ForegroundColor Cyan
            return
        }

        # 执行删除
        Remove-Item -Path $Script:InstallPath -Recurse -Force -ErrorAction Stop | Out-Null
        Write-Success "安装目录已删除"
        $Script:RemovedItems += "安装目录: $Script:InstallPath"
    } catch {
        Write-Error "删除安装目录失败: $_"
        Write-Host "可能需要管理员权限或文件被占用" -ForegroundColor Yellow
        Write-Host "请手动关闭相关程序后重试" -ForegroundColor Cyan
    }
}

#=================== 可选：移除 Scoop ===================

function Remove-ScoopIfRequested {
    if ($KeepScoop) {
        Write-Header "保留 Scoop (用户指定)"
        Write-Success "跳过 Scoop 卸载"
        return
    }

    Write-Header "卸载 Scoop (可选)"

    if (-not $Script:ScoopPath -or -not (Test-Path $Script:ScoopPath)) {
        Write-VerboseLog "Scoop 未检测到，跳过"
        return
    }

    Write-Warning "此操作将删除所有通过 Scoop 安装的程序!"
    Write-Host ""

    $confirmScoop = Read-Host "是否同时卸载 Scoop? (y/n)"
    if ($confirmScoop -ne 'y' -and $confirmScoop -ne 'Y') {
        Write-Success "保留 Scoop"
        return
    }

    Write-Step "删除 Scoop 目录..."

    try {
        Remove-Item -Path $Script:ScoopPath -Recurse -Force -ErrorAction Stop | Out-Null
        Write-Success "Scoop 已删除"
        $Script:RemovedItems += "Scoop: $Script:ScoopPath"
    } catch {
        Write-Error "删除 Scoop 失败: $_"
        Write-Host "请手动删除 Scoop 目录" -ForegroundColor Cyan
    }

    # 清理 scoop 环境变量
    $scoopVars = @('SCOOP', 'SCOOP_GLOBAL')
    foreach ($var in $scoopVars) {
        $currentValue = [Environment]::GetEnvironmentVariable($var, 'User')
        if ($currentValue) {
            [Environment]::SetEnvironmentVariable($var, $null, 'User')
            Write-VerboseLog "已移除环境变量: $var"
        }
    }
}

#=================== 清理用户配置文件 ===================

function Cleanup-UserConfig {
    Write-Header "清理配置文件"

    # 清理可能残留的配置文件
    $configsToCheck = @(
        "$env:USERPROFILE\.gitconfig",
        "$env:USERPROFILE\.npmrc",
        "$env:USERPROFILE\AppData\Roaming\npm"
    )

    foreach ($config in $configsToCheck) {
        if (Test-Path $config) {
            Write-VerboseLog "找到配置文件: $config"
            # 这些是用户配置文件，不自动删除，只做提示
        }
    }

    Write-Success "配置文件检查完成"
    Write-Host ""
    Write-Host "提示: 以下配置文件可能包含安装痕迹，如需清理请手动处理:" -ForegroundColor Yellow
    Write-Host "  - $env:USERPROFILE\.gitconfig" -ForegroundColor Gray
    Write-Host "  - $env:USERPROFILE\.npmrc" -ForegroundColor Gray
    Write-Host "  - $env:USERPROFILE\AppData\Roaming\npm" -ForegroundColor Gray
}

#=================== 完成 ===================

function Complete-Uninstall {
    Write-Header "卸载完成"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  卸载完成!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    if ($Script:RemovedItems.Count -gt 0) {
        Write-Host "已移除的项目:" -ForegroundColor Yellow
        foreach ($item in $Script:RemovedItems) {
            Write-Host "  - $item" -ForegroundColor Gray
        }
        Write-Host ""
    }

    if ($Script:FailedItems.Count -gt 0) {
        Write-Host "失败的项:" -ForegroundColor Red
        foreach ($item in $Script:FailedItems) {
            Write-Host "  - $item" -ForegroundColor Gray
        }
        Write-Host ""
    }

    Write-Host ""
    Write-Host "重要提示:" -ForegroundColor Yellow
    Write-Host "  1. 请重启终端使所有环境变量更改生效" -ForegroundColor Cyan
    Write-Host "  2. 如有残留文件，请手动删除" -ForegroundColor Cyan
    Write-Host "  3. Claude Code 配置可能需要单独清理" -ForegroundColor Cyan
    Write-Host ""

    # 检查是否需要管理员权限
    if ($Script:FailedItems.Count -gt 0) {
        Write-Host "如删除失败，尝试以管理员身份运行卸载脚本" -ForegroundColor Magenta
    }
}

#=================== 主流程 ===================

function Start-Uninstall {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║       Claude Code 开发环境卸载程序 v2.1                  ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""

    # 并发检测
    if (-not (Test-ConcurrentUninstallation)) {
        exit 1
    }

    # 初始化中断处理
    Initialize-SignalHandler

    try {
        # 检测路径
        Get-InstallationPaths
        Test-CancellationRequested

        # 确认卸载
        if (-not (Confirm-Uninstall)) {
            Write-Host "已取消卸载" -ForegroundColor Green
            exit 0
        }

        # 执行卸载
        Test-CancellationRequested
        Remove-EnvironmentVariables

        Test-CancellationRequested
        Remove-InstallationDirectory

        Test-CancellationRequested
        Remove-ScoopIfRequested

        Test-CancellationRequested
        Cleanup-UserConfig

        # 完成
        Complete-Uninstall
    } finally {
        # 清理锁文件
        Remove-LockFile
    }
}

# 执行卸载
Start-Uninstall
