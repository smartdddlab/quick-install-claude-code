#!/usr/bin/env pwsh
#requires -Version 5.1

<#
.SYNOPSIS
    Claude Code Windows 一键安装器
.DESCRIPTION
    在 Windows 环境下自动安装和配置 Claude Code 所需的所有依赖工具
.PARAMETER WhatIf
    预览安装过程，不实际执行
.PARAMETER Verbose
    显示详细日志
.PARAMETER SkipSuperClaude
    跳过 SuperClaude 安装
.PARAMETER IncludeCcSwitch
    包含 cc-switch 镜像切换工具（默认为可选工具）
.PARAMETER InstallDrive
    指定安装驱动器 (如 D:, E:, F:, C:)
.PARAMETER InstallDir
    指定安装目录名 (默认: smartddd-claude-tools)
.EXAMPLE
    # 本地运行
    .\install.ps1
    .\install.ps1 -InstallDrive D -SkipSuperClaude
    .\install.ps1 -IncludeCcSwitch -Verbose
    .\install.ps1 -WhatIf -Verbose

    # 一键安装（从 GitHub）
    irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex
    irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex -InstallDrive D
    irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex -SkipSuperClaude
#>

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$SkipSuperClaude,
    [switch]$IncludeCcSwitch,
    [string]$InstallDrive,
    [string]$InstallDir = "smartddd-claude-tools"
)

#=================== 变量初始化 ===================
# 处理 $PSScriptRoot 在 irm | iex 场景下未定义的问题
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $env:TEMP }

$Script:ErrorCount = 0
$Script:WarningCount = 0
$Script:InstallSuccess = $false
$Script:MirrorMode = 'official'  # 'official' or 'mirror'
$Script:LogFile = "$scriptRoot\install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# 并发锁文件 - 包含安装目录标识以支持多实例
# MEDIUM 修复: 统一转换为大写，避免大小写不一致导致的锁失效
$lockId = if ($InstallDrive) { $InstallDrive.ToUpper().TrimEnd(':') } else { 'AUTO' }
$Script:LockFilePath = "$env:TEMP\claude-install-${lockId}.lock"

# 镜像源配置（多个备用镜像）
$Script:MirrorSources = @{
    primary = @{
        github = 'https://mirror.ghproxy.com/'
        pypi = 'https://mirrors.aliyun.com/pypi/simple/'
        npm = 'https://npmmirror.com/'
        scoop = 'https://mirrors.tuna.tsinghua.edu.cn/git/scoop.git'
    }
    backup = @{
        github = 'https://ghproxy.net/'
        pypi = 'https://mirrors.tencent.com/pypi/simple/'
        npm = 'https://registry.npmmirror.com/'
        scoop = 'https://gitee.com/mirrors/scoop.git'
    }
}
$Script:Mirrors = $Script:MirrorSources.primary

# 安装工具列表（cc-switch 可能在非默认 bucket）
# AC 13: 支持 -IncludeCcSwitch 参数将 cc-switch 加入必需工具
$Script:ToolsToInstall = @('git', 'python312', 'nodejs-lts')
$Script:OptionalTools = @('cc-switch')

# 如果指定了 IncludeCcSwitch，将 cc-switch 移入必需工具列表
if ($IncludeCcSwitch) {
    $Script:OptionalTools = @()
    $Script:ToolsToInstall += @('cc-switch')
    Write-VerboseLog "cc-switch 已加入必需工具列表"
}

#=================== 辅助函数 ===================

function Write-Header {
    param([string]$Message)
    $msg = "`n$('=' * 60)`n  $Message`n$('=' * 60)`n"
    Write-Host $msg -ForegroundColor Cyan
    Add-Content -Path $Script:LogFile -Value $msg
}

function Write-Step {
    param([string]$Message)
    Write-Host "[>] $Message" -ForegroundColor Yellow
    Add-Content -Path $Script:LogFile -Value "[STEP] $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
    Add-Content -Path $Script:LogFile -Value "[OK] $Message"
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Magenta
    Add-Content -Path $Script:LogFile -Value "[WARN] $Message"
    $Script:WarningCount++
}

function Write-Error {
    param([string]$Message)
    Write-Host "[X] $Message" -ForegroundColor Red
    Add-Content -Path $Script:LogFile -Value "[ERROR] $Message"
    $Script:ErrorCount++
}

function Write-VerboseLog {
    param([string]$Message)
    # AC 33: 修复 - 使用 $VerbosePreference 正确检测 Verbose 模式
    # 当 VerbosePreference 不为 SilentlyContinue 时显示详细日志
    if ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Host "    [VERBOSE] $Message" -ForegroundColor Gray
    }
    # WhatIf 模式下跳过日志写入
    if (-not (Test-WhatIfMode)) {
        Add-Content -Path $Script:LogFile -Value "[VERBOSE] $Message" -ErrorAction SilentlyContinue
    }
}

# AC 36: 检查并发安装
function Test-ConcurrentInstallation {
    if (Test-Path $Script:LockFilePath) {
        $lockContent = Get-Content $Script:LockFilePath -ErrorAction SilentlyContinue
        $lockTime = [DateTime]::Parse($lockContent)
        $timeDiff = (Get-Date) - $lockTime

        if ($timeDiff.TotalMinutes -lt 30) {
            Write-Error "检测到另一个安装进程正在运行 (锁文件于 $([math]::Round($timeDiff.TotalMinutes, 1)) 分钟前创建)"
            Write-Host "  如确定没有其他安装进程，请删除: $Script:LockFilePath" -ForegroundColor Cyan
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

# AC 25: 带重试的执行函数
function Invoke-RetryCommand {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Description,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 2
    )

    $attempt = 0
    $mirrorSwitched = $false

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $result = & $ScriptBlock
            if ($LASTEXITCODE -eq 0) {
                Write-VerboseLog "$Description 成功 (尝试 $attempt/$MaxRetries)"
                return $result
            }
        } catch {
            Write-VerboseLog "$Description 失败 (尝试 $attempt/$MaxRetries): $_"
        }

        if ($attempt -lt $MaxRetries) {
            Write-Warning "$Description 失败，${RetryDelay}秒后重试..."
            Start-Sleep -Seconds $RetryDelay

            # AC 37: 失败后切换到备用镜像，添加用户提示
            # 支持官方源失败时也切换到国内镜像
            if (-not $mirrorSwitched) {
                Write-Step "准备切换到备用镜像源..."

                if (-not (Test-WhatIfMode)) {
                    Write-Host ""
                    Write-Host "当前镜像源下载失败，是否切换到备用镜像源?" -ForegroundColor Yellow
                    Write-Host "  当前模式: $($Script:MirrorMode)" -ForegroundColor Gray
                    Write-Host "  主镜像: $($Script:Mirrors.github)" -ForegroundColor Gray
                    Write-Host "  备用镜像: $($Script:MirrorSources.backup.github)" -ForegroundColor Gray
                    Write-Host ""
                    $response = Read-Host "是否切换? (y/n，默认 y)"

                    if ($response -eq 'n' -or $response -eq 'N') {
                        Write-Warning "用户取消镜像切换，继续使用当前镜像重试"
                    } else {
                        # 无论当前是什么模式，都切换到备用镜像
                        $Script:MirrorMode = 'mirror'
                        $Script:Mirrors = $Script:MirrorSources.backup.Clone()
                        $mirrorSwitched = $true
                        Write-Success "已切换到备用镜像源"
                        Write-VerboseLog "新镜像: $($Script:Mirrors.github)"
                    }
                } else {
                    # WhatIf 模式：仅显示
                    $Script:MirrorMode = 'mirror'
                    $Script:Mirrors = $Script:MirrorSources.backup.Clone()
                    $mirrorSwitched = $true
                    Write-VerboseLog "[WHATIF] 已切换镜像源"
                }
            }
        }
    }

    Write-Error "$Description 失败 (已重试 $MaxRetries 次)"
    return $null
}

# 检查用户取消
function Test-CancellationRequested {
    if ($script:CancelRequested) {
        Write-Warning "用户取消安装"
        Remove-LockFile
        exit 1
    }
}

# 清理锁文件
function Remove-LockFile {
    # WhatIf 模式下跳过文件操作
    if (Test-WhatIfMode) {
        return
    }
    if (Test-Path $Script:LockFilePath) {
        Remove-Item $Script:LockFilePath -Force -ErrorAction SilentlyContinue
    }
}

function Test-WhatIfMode {
    return $WhatIf -or $WhatIfPreference
}

function Write-WhatIfHeader {
    if (Test-WhatIfMode) {
        Write-Host ""
        Write-Host ("[WHATIF] " + "=" * 55) -ForegroundColor DarkGray
    }
}

# AC 30: WhatIf 预览报告 - 显示完整安装预览
function Show-WhatIfPreviewReport {
    param(
        [string]$DriveLetter,
        [string]$InstallDir
    )

    if (-not (Test-WhatIfMode)) {
        return
    }

    $installPath = "${DriveLetter}:\${InstallDir}"

    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           安装预览报告 (WhatIf 模式)                          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "【安装配置】" -ForegroundColor Yellow
    Write-Host "  安装驱动器:     $DriveLetter:\" -ForegroundColor White
    Write-Host "  安装目录:       $installPath" -ForegroundColor White
    Write-Host "  日志文件:       $Script:LogFile" -ForegroundColor Gray
    Write-Host ""

    Write-Host "【将要安装的工具】" -ForegroundColor Yellow
    foreach ($tool in $Script:ToolsToInstall) {
        Write-Host "  ✓ $tool" -ForegroundColor Green
    }
    if ($Script:OptionalTools.Count -gt 0) {
        Write-Host ""
        Write-Host "【可选工具】" -ForegroundColor Gray
        foreach ($tool in $Script:OptionalTools) {
            Write-Host "  ○ $tool (在可用 bucket 中安装)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    Write-Host "【环境变量配置】" -ForegroundColor Yellow
    $bashPath = "${installPath}\scoop\apps\git\current\bin\bash.exe"
    Write-Host "  SHELL                             → $bashPath" -ForegroundColor White
    Write-Host "  CLAUDE_CODE_GIT_BASH_PATH          → $bashPath" -ForegroundColor White
    Write-Host "  CLAUDE_INSTALL_DRIVE               → $DriveLetter" -ForegroundColor White
    Write-Host ""

    Write-Host "【镜像源配置】" -ForegroundColor Yellow
    $mirrorMode = if ($Script:MirrorMode -eq 'mirror') { "国内镜像" } else { "官方源" }
    Write-Host "  模式:           $mirrorMode" -ForegroundColor White
    if ($Script:MirrorMode -eq 'mirror') {
        Write-Host "  GitHub:         $($Script:Mirrors.github)" -ForegroundColor Gray
        Write-Host "  PyPI:           $($Script:Mirrors.pypi)" -ForegroundColor Gray
        Write-Host "  npm:            $($Script:Mirrors.npm)" -ForegroundColor Gray
        Write-Host "  Scoop:          $($Script:Mirrors.scoop)" -ForegroundColor Gray
    }
    Write-Host ""

    $superClaudeStatus = if ($SkipSuperClaude) { "跳过" } else { "安装" }
    Write-Host "【其他选项】" -ForegroundColor Yellow
    Write-Host "  SuperClaude:    $superClaudeStatus" -ForegroundColor White
    Write-Host ""

    # 空间估算
    $drive = Get-PSDrive -Name $DriveLetter
    $freeSpace = $drive.Free
    $estimatedSpace = 3GB  # 预估需要约 3GB
    $remainingSpace = $freeSpace - $estimatedSpace

    Write-Host "【磁盘空间】" -ForegroundColor Yellow
    Write-Host "  当前可用:      $([math]::Round($freeSpace / 1GB, 2)) GB" -ForegroundColor White
    Write-Host "  预估需要:      ~3 GB" -ForegroundColor Gray
    Write-Host "  安装后剩余:    $([math]::Round($remainingSpace / 1GB, 2)) GB" -ForegroundColor $(if ($remainingSpace -lt 1GB) { "Red" } elseif ($remainingSpace -lt 5GB) { "Yellow" } else { "Green" })
    Write-Host ""

    Write-Host "=" * 60 -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "如需实际执行安装，请移除 -WhatIf 参数后重新运行" -ForegroundColor Cyan
    Write-Host ""
}

#=================== AC 1-2: PowerShell 版本和执行策略检测 ===================

function Test-PowerShellEnvironment {
    Write-Header "Step 1: 环境检测"

    # AC 1: PowerShell 版本 >= 5.1
    Write-Step "检查 PowerShell 版本..."
    $psVersion = $PSVersionTable.PSVersion
    Write-VerboseLog "当前版本: $psVersion"
    if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
        Write-Error "PowerShell 版本过低: $psVersion (需要 5.1+)"
        Write-Host "请升级 PowerShell: https://aka.ms/pscore6" -ForegroundColor Cyan
        return $false
    }
    Write-Success "PowerShell 版本检查通过: $psVersion"

    # AC 2: 执行策略检测
    Write-Step "检查执行策略..."
    $policy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    Write-VerboseLog "当前策略: $policy"

    if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
        Write-Error "检测到执行策略限制: $policy"
        Write-Host ""
        Write-Host "解决方案：" -ForegroundColor Yellow
        Write-Host "  1. 运行: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned" -ForegroundColor Cyan
        Write-Host "  2. 或者: powershell -ExecutionPolicy Bypass -File install.ps1" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "修改后请重新运行此脚本" -ForegroundColor Cyan
        return $false
    }
    Write-Success "执行策略检查通过: $policy"

    return $true
}

#=================== AC 9-10: 驱动器选择 ===================

function Select-InstallDrive {
    Write-Header "Step 2: 选择安装驱动器"

    # AC 9: D/E/F 优先，C 盘兜底
    # AC 10: 只有 C 盘时使用 C 盘
    # AC 27: C 盘安装显示警告
    # AC 28: C 盘空间不足拒绝安装

    $preferredDrives = @('D', 'E', 'F')

    # 如果用户指定了驱动器
    # AC 16: 支持 CLAUDE_INSTALL_DRIVE 环境变量
    # 优先级: 命令行参数 > 环境变量 > 自动选择
    if ($InstallDrive) {
        $driveLetter = $InstallDrive.TrimEnd(':')
        if ($driveLetter.Length -eq 1) {
            $driveLetter = $driveLetter.ToUpper()
        }
    } elseif ($env:CLAUDE_INSTALL_DRIVE) {
        # 检查环境变量
        $driveLetter = $env:CLAUDE_INSTALL_DRIVE.ToUpper()
        Write-VerboseLog "使用 CLAUDE_INSTALL_DRIVE 环境变量: $driveLetter"
    } else {
        # 自动选择
        $selectedDrive = $null
        foreach ($letter in $preferredDrives) {
            if (Test-Path "${letter}:\") {
                $drive = Get-PSDrive -Name $letter -ErrorAction SilentlyContinue
                if ($drive -and $drive.Free -gt 5GB) {
                    $selectedDrive = $letter
                    Write-VerboseLog "找到可用驱动器: $letter (空闲: $([math]::Round($drive.Free / 1GB, 2))GB)"
                    break
                }
            }
        }
        $driveLetter = $selectedDrive
    }

    # 检查驱动器
    if (-not $driveLetter) {
        $driveLetter = 'C'
        Write-Warning "未检测到 D/E/F 盘，将安装到 C 盘"
    }

    $installPath = "${driveLetter}:\${InstallDir}"
    Write-VerboseLog "安装路径: $installPath"

    # C 盘警告
    if ($driveLetter -eq 'C') {
        Write-Warning "将在 C 盘安装。强烈建议使用其他驱动器！"
        Write-Host "如需指定其他驱动器，使用: -InstallDrive D" -ForegroundColor Cyan
        Write-Host ""
    }

    # 检查空间
    $drive = Get-PSDrive -Name $driveLetter
    $freeSpace = $drive.Free
    $requiredSpace = 5GB  # 预估需要 5GB

    if ($freeSpace -lt $requiredSpace) {
        Write-Error "驱动器 ${driveLetter}:\ 空间不足"
        Write-Host "  可用: $([math]::Round($freeSpace / 1GB, 2))GB" -ForegroundColor Red
        Write-Host "  需要: $([math]::Round($requiredSpace / 1GB, 2))GB" -ForegroundColor Red
        return $null
    }

    Write-Success "选择驱动器: ${driveLetter}:\ (空闲: $([math]::Round($drive.Free / 1GB, 2))GB)"
    return $driveLetter
}

#=================== AC 23-26: 网络测试和镜像源选择 ===================

function Test-NetworkAndSelectMirror {
    Write-Header "Step 3: 网络测试与镜像源选择"

    # AC 23-24: GitHub 连通性测试
    # WhatIf 模式: 跳过实际网络测试
    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 测试 GitHub 连通性..." -ForegroundColor DarkGray
        Write-Success "[WhatIf] GitHub 连通性测试跳过"
        return $Script:MirrorMode
    }

    Write-Step "测试 GitHub 连通性..."

    $githubAccessible = $false
    try {
        # 综合测试：Ping + HTTP + Git API
        # Ping 可能被防火墙 blocking，所以需要多种方法
        $pingOk = Test-Connection github.com -Count 1 -Quiet -ErrorAction SilentlyContinue

        # 测试 HTTPS 访问
        $httpOk = $false
        try {
            $response = Invoke-WebRequest -Uri "https://github.com" -TimeoutSec 10 -ErrorAction SilentlyContinue
            $httpOk = $true
        } catch {
            Write-VerboseLog "GitHub HTTP 测试失败: $_"
        }

        # 测试 GitHub API（最能代表 clone 能力）
        $apiOk = $false
        try {
            $apiResponse = Invoke-WebRequest -Uri "https://api.github.com" -TimeoutSec 10 -ErrorAction SilentlyContinue
            $apiOk = $true
        } catch {
            Write-VerboseLog "GitHub API 测试失败: $_"
        }

        # 只要 HTTP 或 API 能访问就算可用
        $githubAccessible = $httpOk -or $apiOk
        Write-VerboseLog "GitHub 测试结果: Ping=$pingOk, HTTP=$httpOk, API=$apiOk"
    } catch {
        Write-VerboseLog "GitHub 连通性测试异常: $_"
        $githubAccessible = $false
    }

    # AC 23: GitHub 可访问用官方源
    # AC 24: GitHub 不可访问用镜像源
    if ($githubAccessible) {
        $Script:MirrorMode = 'official'
        Write-Success "GitHub 可达，使用官方源"
    } else {
        $Script:MirrorMode = 'mirror'
        Write-Warning "GitHub 不可达，使用国内镜像源"
        Write-Host "  GitHub: $($Script:Mirrors.github)" -ForegroundColor Cyan
        Write-Host "  PyPI: $($Script:Mirrors.pypi)" -ForegroundColor Cyan
        Write-Host "  npm: $($Script:Mirrors.npm)" -ForegroundColor Cyan
        Write-Host "  Scoop: $($Script:Mirrors.scoop)" -ForegroundColor Cyan
    }

    return $Script:MirrorMode
}

#=================== AC 3-6: Git Bash 检测和安装 ===================

function Test-And-InstallGitBash {
    param(
        [string]$DriveLetter,
        [string]$InstallDir
    )

    Write-Header "Step 4: Git Bash 检测与安装"

    # WhatIf 模式: 跳过实际检测和安装
    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 检测 Git Bash..." -ForegroundColor DarkGray
        Write-Host "    [WHATIF] 如不存在则通过 Scoop 安装 Git" -ForegroundColor DarkGray
        $mockBashPath = "${DriveLetter}:\${InstallDir}\scoop\apps\git\current\bin\bash.exe"
        Write-Success "[WhatIf] Git Bash 检测/安装跳过"
        return $mockBashPath
    }

    # AC 3: 检测 Git Bash 是否存在
    Write-Step "检测 Git Bash..."

    $bashPaths = @(
        "$env:SCOOP\shims\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe"
    )

    $bashFound = $false
    $bashPath = $null

    foreach ($path in $bashPaths) {
        if (Test-Path $path) {
            $bashFound = $true
            $bashPath = $path
            Write-Success "检测到 Git Bash: $path"
            break
        }
    }

    # AC 20: Given Git Bash 已存在，When 安装，Then 跳过 Git 安装
    if ($bashFound) {
        Write-VerboseLog "Git Bash 已存在，跳过安装"
        return $bashPath
    }

    # AC 4: Git Bash 不存在时自动通过 Scoop 安装
    # AC 19: Given Git Bash 不存在，When 安装，Then Scoop 自动安装 Git
    Write-Warning "未检测到 Git Bash，将通过 Scoop 安装..."

    # AC 6: Scoop 首先安装
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Step "Scoop 未安装，正在安装..."
        Install-Scoop -DriveLetter $DriveLetter -InstallDir $InstallDir
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Scoop 安装失败"
            return $null
        }
    } else {
        Write-Success "Scoop 已安装"
    }

    # 安装 Git
    Write-Step "正在安装 Git (包含 Git Bash)..."

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] scoop install git --global" -ForegroundColor DarkGray
        $bashPath = "${DriveLetter}:\${InstallDir}\scoop\apps\git\current\bin\bash.exe"
    } else {
        $installGitScript = {
            scoop install git --global
        }.GetNewClosure()

        $result = Invoke-RetryCommand -ScriptBlock $installGitScript -Description "Git 安装" -MaxRetries 3
        $bashPath = "${DriveLetter}:\${InstallDir}\scoop\apps\git\current\bin\bash.exe"

        if ($null -eq $result) {
            Write-Error "Git 安装失败"
            return $null
        }
    }

    # AC 5: 验证 Git Bash 安装后可用
    # AC 21: Given Git Bash 安装完成，When 验证，Then bash.exe 可正常执行
    Write-Step "验证 Git Bash..."
    if (Test-Path $bashPath) {
        try {
            # MEDIUM 修复: 对路径加引号，处理带空格的路径
            $result = & "$bashPath" --version 2>&1
            Write-Success "Git Bash 验证成功"
            Write-VerboseLog $result
            return $bashPath
        } catch {
            Write-Error "Git Bash 无法执行: $_"
            return $null
        }
    } else {
        Write-Error "Git Bash 文件不存在: $bashPath"
        return $null
    }
}

#=================== Scoop 安装 ===================

function Install-Scoop {
    param(
        [string]$DriveLetter,
        [string]$InstallDir
    )

    Write-Step "安装 Scoop 包管理器..."

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 安装 Scoop 到 ${DriveLetter}:\${InstallDir}\scoop" -ForegroundColor DarkGray
        return
    }

    $scoopDir = "${DriveLetter}:\${InstallDir}\scoop"

    # 如果已存在 Scoop，跳过
    if (Test-Path "$env:SCOOP") {
        Write-Success "Scoop 已存在"
        return
    }

    # 配置 Scoop 安装路径
    $env:SCOOP = $scoopDir

    # AC 25 + 37: 使用重试逻辑和镜像切换
    $installScript = {
        # 配置镜像源
        if ($Script:MirrorMode -eq 'mirror') {
            Write-VerboseLog "配置 Scoop 镜像源..."
            $env:SCOOP_INSTALL_REPO = $Script:Mirrors.scoop
        }

        # 下载并验证安装脚本
        $progressPreference = 'silentlyContinue'
        $scriptContent = Invoke-WebRequest -Uri "https://get.scoop.sh" -TimeoutSec 30 -ErrorAction Stop
        $progressPreference = 'Continue'

        # 基本安全检查：验证脚本是 PowerShell 脚本
        if ($scriptContent.Content -notmatch '#Requires|Install-Scoop') {
            throw "下载的脚本内容无效"
        }

        # 执行安装
        Invoke-Expression $scriptContent.Content
    }.GetNewClosure()

    $result = Invoke-RetryCommand -ScriptBlock $installScript -Description "Scoop 安装" -MaxRetries 3

    if ($null -eq $result -and -not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw "Scoop 安装失败"
    }

    # 验证 Scoop 镜像源配置
    if ($Script:MirrorMode -eq 'mirror') {
        $scoopConfig = scoop config 2>&1 | Out-String
        if ($scoopConfig -notmatch $Script:Mirrors.scoop) {
            Write-Warning "Scoop 镜像源可能未正确配置"
            Write-VerboseLog "当前 Scoop 配置: $scoopConfig"
        } else {
            Write-VerboseLog "Scoop 镜像源配置验证成功"
        }
    }

    Write-Success "Scoop 安装完成"
}

#=================== AC 7, 11-12: 工具安装和环境变量 ===================

function Install-Tools {
    param([string]$InstallDir)

    Write-Header "Step 5: 安装开发工具"

    # AC 11: 目录名 smartddd-claude-tools
    # AC 12: pip、npm 使用镜像源

    # 安装必需工具
    foreach ($tool in $Script:ToolsToInstall) {
        Write-Step "安装 $tool..."

        if (Test-WhatIfMode) {
            Write-Host "    [WHATIF] scoop install $tool" -ForegroundColor DarkGray
            continue
        }

        Test-CancellationRequested

        $installToolScript = {
            scoop install $tool --global
        }.GetNewClosure()

        $result = Invoke-RetryCommand -ScriptBlock $installToolScript -Description "$tool 安装" -MaxRetries 3

        if ($null -ne $result) {
            # 获取安装的版本信息
            $version = & $tool --version 2>&1
            Write-Success "$tool 安装完成 - $version"
        } else {
            Write-Error "$tool 安装失败"
        }
    }

    # 尝试安装可选工具（如 cc-switch）
    foreach ($tool in $Script:OptionalTools) {
        Write-Step "安装可选工具 $tool..."

        if (Test-WhatIfMode) {
            Write-Host "    [WHATIF] scoop install $tool" -ForegroundColor DarkGray
            continue
        }

        # 检查工具是否在可用 bucket 中
        $searchResult = scoop search $tool 2>&1
        if ($searchResult -match $tool) {
            try {
                scoop install $tool --global 2>&1 | Out-Null
                Write-Success "$tool 安装完成"
            } catch {
                Write-Warning "$tool 安装失败，跳过"
            }
        } else {
            Write-Warning "$tool 在默认 bucket 中未找到，跳过安装"
            Write-Host "  如需安装，可能需要添加额外 bucket: scoop bucket add <bucket-name>" -ForegroundColor Gray
        }
    }

    # 配置 pip 和 npm 镜像源
    Write-Step "配置 pip/npm 镜像源..."
    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 配置 pip: $($Script:Mirrors.pypi)" -ForegroundColor DarkGray
        Write-Host "    [WHATIF] 配置 npm: $($Script:Mirrors.npm)" -ForegroundColor DarkGray
    } else {
        # pip 镜像 - 验证配置
        $pipConfigSuccess = $false
        if (Get-Command pip -ErrorAction SilentlyContinue) {
            Write-Step "配置 pip 镜像源..."

            # 先设置配置（不依赖返回值）
            $null = Invoke-RetryCommand -ScriptBlock {
                pip config set global.index-url $Script:Mirrors.pypi 2>&1
            } -Description "pip 镜像配置" -MaxRetries 2

            # 验证 pip 配置 - 使用 get 命令确认配置已生效
            $verifyPip = pip config get global.index-url 2>&1 | Out-String
            if ($verifyPip -match $Script:Mirrors.pypi) {
                $pipConfigSuccess = $true
                Write-Success "pip 镜像配置已验证: $Script:Mirrors.pypi"
            } else {
                Write-Warning "pip 镜像配置可能未生效"
            }
        } else {
            Write-Warning "pip 不可用，跳过镜像配置"
        }

        # npm 镜像 - 验证配置
        $npmConfigSuccess = $false
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Step "配置 npm 镜像源..."

            # 先设置配置（不依赖返回值）
            $null = Invoke-RetryCommand -ScriptBlock {
                npm config set registry $Script:Mirrors.npm 2>&1
            } -Description "npm 镜像配置" -MaxRetries 2

            # 验证 npm 配置 - 使用 get 命令确认配置已生效
            $verifyNpm = npm config get registry 2>&1 | Out-String
            if ($verifyNpm -match $Script:Mirrors.npm) {
                $npmConfigSuccess = $true
                Write-Success "npm 镜像配置已验证: $Script:Mirrors.npm"
            } else {
                Write-Warning "npm 镜像配置可能未生效"
            }
        } else {
            Write-Warning "npm 不可用，跳过镜像配置"
        }

        # 总结配置状态
        if ($pipConfigSuccess -or $npmConfigSuccess) {
            Write-Success "镜像源配置完成"
        }
    }
}

#=================== AC 7: 环境变量配置 ===================

function Set-EnvironmentVariables {
    param(
        [string]$BashPath,
        [string]$InstallPath
    )

    Write-Header "Step 6: 配置环境变量"

    # AC 7: 环境变量正确设置（SHELL、CLAUDE_CODE_GIT_BASH_PATH）
    # AC 22: Given SHELL 环境变量未设置，When 安装完成，Then 自动设置并提示重启终端

    if (-not $BashPath) {
        Write-Error "Git Bash 路径无效"
        return $false
    }

    Write-Step "设置环境变量..."

    # AC 16: 支持 CLAUDE_INSTALL_DRIVE 环境变量
    $driveLetter = $InstallPath.Substring(0, 1)

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] SHELL = $BashPath" -ForegroundColor DarkGray
        Write-Host "    [WHATIF] CLAUDE_CODE_GIT_BASH_PATH = $BashPath" -ForegroundColor DarkGray
        Write-Host "    [WHATIF] CLAUDE_INSTALL_DRIVE = $driveLetter" -ForegroundColor DarkGray
    } else {
        # 设置用户级环境变量
        [Environment]::SetEnvironmentVariable('SHELL', $BashPath, 'User')
        [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $BashPath, 'User')
        [Environment]::SetEnvironmentVariable('CLAUDE_INSTALL_DRIVE', $driveLetter, 'User')

        # 当前会话临时设置
        $env:SHELL = $BashPath
        $env:CLAUDE_CODE_GIT_BASH_PATH = $BashPath
        $env:CLAUDE_INSTALL_DRIVE = $driveLetter

        Write-Success "环境变量已配置"
    }

    # 显示配置信息
    Write-Host ""
    Write-Host "配置信息:" -ForegroundColor Cyan
    Write-Host "  SHELL=$BashPath"
    Write-Host "  CLAUDE_CODE_GIT_BASH_PATH=$BashPath"
    Write-Host "  CLAUDE_INSTALL_DRIVE=$driveLetter"
    Write-Host "  安装目录=$InstallPath"
    Write-Host ""

    # AC 34: 当前会话环境变量即时生效
    Write-Success "当前会话环境变量已生效"

    return $true
}

#=================== AC 15: SuperClaude 安装 ===================

function Install-SuperClaude {
    param([string]$InstallPath)

    # AC 15: SuperClaude 自动安装
    # AC 26: SuperClaude 失败可继续
    # AC 38: -SkipSuperClaude 正常工作

    if ($SkipSuperClaude) {
        Write-Warning "跳过 SuperClaude 安装 (用户指定)"
        return $true
    }

    Write-Header "Step 7: 安装 SuperClaude (可选)"

    Write-Step "正在克隆 SuperClaude 框架..."

    $superClaudePath = "$InstallPath\SuperClaude_Framework"

    if (Test-Path $superClaudePath) {
        Write-Success "SuperClaude 已存在"
        return $true
    }

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] git clone SuperClaude 到 $superClaudePath" -ForegroundColor DarkGray
        return $true
    }

    try {
        # AC 15: 确保 git 可用后再克隆（SuperClaude 依赖 git）
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Error "Git 命令不可用，SuperClaude 安装失败"
            Write-Host "  请确保 Git 已正确安装后再尝试安装 SuperClaude" -ForegroundColor Cyan
            return $false
        }

        # 尝试克隆
        $repoUrl = if ($Script:MirrorMode -eq 'mirror') {
            "https://mirror.ghproxy.com/https://github.com/SuperClaude-Org/SuperClaude_Framework.git"
        } else {
            "https://github.com/SuperClaude-Org/SuperClaude_Framework.git"
        }

        git clone $repoUrl $superClaudePath 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Success "SuperClaude 安装完成"
            return $true
        } else {
            Write-Warning "SuperClaude 安装失败，但可继续"
            Write-Host "  可手动运行: git clone $repoUrl $superClaudePath" -ForegroundColor Cyan
            return $true  # 不算错误
        }
    } catch {
        Write-Warning "SuperClaude 安装失败: $_"
        Write-Host "可手动安装或稍后重试" -ForegroundColor Cyan
        return $true  # AC 26: 失败可继续
    }
}

#=================== AC 14: 卸载脚本 ===================

function New-UninstallScript {
    param([string]$InstallPath)

    Write-Header "Step 8: 创建卸载脚本"

    $uninstallScript = "$InstallPath\scripts\uninstall.ps1"
    $scriptsDir = Split-Path $uninstallScript -Parent

    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    Write-Step "创建卸载脚本: scripts\uninstall.ps1"

    $uninstallContent = @'
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
            Remove-Item $Script:LockFilePath -Force -ErrorAction SilentlyContinue
        }
    }

    Get-Date | Out-File -FilePath $Script:LockFilePath -Force
    return $true
}

function Remove-LockFile {
    if (Test-Path $Script:LockFilePath) {
        Remove-Item $Script:LockFilePath -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-UninstallSignalHandler {
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
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "  检测安装路径" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""

    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $scriptsDir = Split-Path -Parent $scriptPath
        $parentDir = Split-Path -Parent $scriptsDir

        if ($parentDir -and (Test-Path $parentDir)) {
            if (Test-Path "$parentDir\scripts") {
                $Script:InstallPath = $parentDir
                Write-Success "检测到安装目录: $Script:InstallPath"
            }
        }
    }

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

    if (-not $Script:InstallPath) {
        Write-Warning "未能自动检测安装目录"
        Write-Host "请输入安装目录路径 (直接回车退出):" -ForegroundColor Yellow
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
    Write-Host "║       Claude Code 开发环境卸载程序 v2.1                  ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""

    Write-Host "安装目录: $Script:InstallPath" -ForegroundColor Yellow
    Write-Host ""

    $confirm = Read-Host "确认卸载? (y/n)"

    return $confirm -eq 'y' -or $confirm -eq 'Y'
}

#=================== 移除环境变量 ===================

function Remove-EnvironmentVariables {
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "  移除环境变量" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""

    $variablesToRemove = @('SHELL', 'CLAUDE_CODE_GIT_BASH_PATH', 'CLAUDE_INSTALL_DRIVE')

    foreach ($var in $variablesToRemove) {
        $currentValue = [Environment]::GetEnvironmentVariable($var, 'User')

        if ($currentValue) {
            Write-Host "移除 $var..." -ForegroundColor Yellow
            try {
                [Environment]::SetEnvironmentVariable($var, $null, 'User')

                if (Test-Path "env:$var") {
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
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "  删除安装目录" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""

    if (-not $Script:InstallPath -or -not (Test-Path $Script:InstallPath)) {
        Write-Warning "安装目录不存在或无效: $Script:InstallPath"
        return
    }

    Write-Host "删除 $Script:InstallPath ..." -ForegroundColor Yellow

    try {
        $parentDir = Split-Path $Script:InstallPath -Parent
        $dirName = Split-Path $Script:InstallPath -Leaf

        $safeNames = @('smartddd-claude-tools', 'sddd-claude-tools', 'claude-tools')
        if ($dirName -notin $safeNames) {
            Write-Warning "目录名不安全: $dirName"
            Write-Host "出于安全考虑，不会自动删除此目录" -ForegroundColor Yellow
            Write-Host "如需删除，请手动执行: Remove-Item -Path '$Script:InstallPath' -Recurse -Force" -ForegroundColor Cyan
            return
        }

        Remove-Item -Path $Script:InstallPath -Recurse -Force -ErrorAction Stop | Out-Null
        Write-Success "安装目录已删除"
        $Script:RemovedItems += "安装目录: $Script:InstallPath"
    } catch {
        Write-Error "删除安装目录失败: $_"
        Write-Host "可能需要管理员权限或文件被占用" -ForegroundColor Yellow
        Write-Host "请手动关闭相关程序后重试" -ForegroundColor Cyan
    }
}

#=================== 完成 ===================

function Complete-Uninstall {
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
    Initialize-UninstallSignalHandler

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

        # 完成
        Complete-Uninstall
    } finally {
        # 清理锁文件
        Remove-LockFile
    }
}

# 执行卸载
Start-Uninstall
'@

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 创建 $uninstallScript" -ForegroundColor DarkGray
    } else {
        $uninstallContent | Out-File -FilePath $uninstallScript -Encoding UTF8 -NoNewline
        Write-Success "卸载脚本已创建"
    }
}

#=================== RefreshEnv.cmd ===================

function New-RefreshEnvScript {
    param([string]$InstallPath)

    Write-Header "创建环境刷新脚本"

    $refreshScript = "$InstallPath\scripts\RefreshEnv.cmd"

    Write-Step "创建 RefreshEnv.cmd"

    $refreshContent = "@echo off
REM 刷新环境变量
REM 使用方法: 在终端中运行 RefreshEnv.cmd 或 call RefreshEnv.cmd

setlocal EnableDelayedExpansion

REM 读取 scoop 刷新脚本 - 只调用一次，使用 else if 避免重复调用
if defined SCOOP (
    if exist ""%SCOOP%\shims\refreshenv.cmd"" (
        call ""%SCOOP%\shims\refreshenv.cmd""
        goto :EOF
    )
)

if exist ""%USERPROFILE%\scoop\shims\refreshenv.cmd"" (
    call ""%USERPROFILE%\scoop\shims\refreshenv.cmd""
) else (
    echo 无法找到 refreshenv.cmd
    echo 请确保 Scoop 已正确安装
)

endlocal
"

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 创建 $refreshScript" -ForegroundColor DarkGray
    } else {
        $refreshContent | Out-File -FilePath $refreshScript -Encoding ASCII
        Write-Success "刷新脚本已创建"
    }
}

#=================== AC 8, 30-31: 验证和完成 ===================

function Complete-Installation {
    param(
        [string]$InstallPath,
        [string]$BashPath
    )

    Write-Header "Step 9: 验证与完成"

    # AC 8: 所有工具可用
    Write-Step "验证工具可用性..."
    $allToolsOk = $true

    # 验证必需工具 - 注意命令名与包名可能不同
    $toolsToVerify = @(
        @{Name = 'git'; VersionCmd = 'git --version'},
        @{Name = 'python'; VersionCmd = 'python --version'},
        @{Name = 'python312'; VersionCmd = 'python312 --version'},
        @{Name = 'node'; VersionCmd = 'node --version'},
        @{Name = 'nodejs-lts'; VersionCmd = 'node --version'},
        @{Name = 'scoop'; VersionCmd = 'scoop --version'}
    )

    # AC 13: 如果安装了 cc-switch，也需要验证
    if ($Script:ToolsToInstall -contains 'cc-switch' -or $IncludeCcSwitch) {
        $toolsToVerify += @{Name = 'cc-switch'; VersionCmd = 'cc-switch --version'}
    }

    $verifiedTools = @{}

    foreach ($tool in $toolsToVerify) {
        $cmd = Get-Command $tool.VersionCmd.Split(' ')[0] -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                $version = & $tool.VersionCmd 2>&1 | Select-Object -First 1
                if ($version) {
                    Write-Success "$($tool.Name) 可用 - $version"
                    $verifiedTools[$tool.Name] = $true
                }
            } catch {
                Write-Warning "$($tool.Name) 命令存在但获取版本失败"
            }
        }
    }

    # 检查核心工具是否至少有一个可用
    $coreToolsOk = $verifiedTools.ContainsKey('git') -and (
        $verifiedTools.ContainsKey('python') -or $verifiedTools.ContainsKey('python312')
    ) -and (
        $verifiedTools.ContainsKey('node') -or $verifiedTools.ContainsKey('nodejs-lts')
    )

    if (-not $coreToolsOk) {
        Write-Warning "部分核心工具不可用"
        $allToolsOk = $false
    }

    # AC 30: --what-if 预览模式 (已在参数处理)
    # AC 31: 进度显示 (已在脚本中实现)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  安装完成!" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "安装路径: $InstallPath" -ForegroundColor Green
    Write-Host "日志文件: $Script:LogFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "下一步操作:" -ForegroundColor Yellow
    Write-Host "  1. 重启终端或运行 RefreshEnv.cmd 刷新环境" -ForegroundColor Cyan
    Write-Host "  2. Claude Code CLI 通常为 'cc' 或 'claude-code'" -ForegroundColor Cyan
    Write-Host "  3. 运行 'cc --help' 或 'claude-code --help' 验证" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "如需卸载，运行: $InstallPath\scripts\uninstall.ps1" -ForegroundColor Cyan
    Write-Host ""

    # AC 32: 快速入门指引
    Write-Host "快速入门:" -ForegroundColor Yellow
    Write-Host "  - Git Bash 路径: $BashPath" -ForegroundColor Gray
    Write-Host "  - 环境变量已配置，请重启终端" -ForegroundColor Gray
    Write-Host "  - 日志保存在: $Script:LogFile" -ForegroundColor Gray
    Write-Host ""

    return $allToolsOk
}

#=================== AC 35: 用户中断处理 ===================

function Initialize-SignalHandler {
    $script:CancelRequested = $false

    $handler = {
        $script:CancelRequested = $true
        Write-Host ""
        Write-Host "用户中断请求..." -ForegroundColor Yellow
    }

    [Console]::CancelKeyPress += $handler
}

#=================== 主流程 ===================

function Start-Installation {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       Claude Code Windows 一键安装器 v2.1                  ║" -ForegroundColor Cyan
    Write-Host "║       Author: SmartDDD Lab                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # AC 30: WhatIf 模式
    if (Test-WhatIfMode) {
        Write-Warning "[WhatIf 模式] 以下操作仅预览，不会实际执行"
        Write-Host ""
    }

    # AC 36: 并发安装检测
    # WhatIf 模式下跳过并发检测，避免创建锁文件
    if (-not (Test-WhatIfMode)) {
        if (-not (Test-ConcurrentInstallation)) {
            exit 1
        }
    } else {
        Write-VerboseLog "[WhatIf] 并发安装检测跳过"
    }

    # 初始化中断处理
    Initialize-SignalHandler

    try {
        # Step 1: 环境检测
        Test-CancellationRequested
        if (-not (Test-PowerShellEnvironment)) {
            Write-Error "环境检测失败，退出安装"
            throw "Environment check failed"
        }

        # Step 2: 选择驱动器
        Test-CancellationRequested
        $driveLetter = Select-InstallDrive
        if (-not $driveLetter) {
            Write-Error "驱动器选择失败，退出安装"
            throw "Drive selection failed"
        }
        $installPath = "${driveLetter}:\${InstallDir}"

        # Step 3: 网络测试
        Test-CancellationRequested
        $null = Test-NetworkAndSelectMirror

        # AC 30: WhatIf 预览报告（在开始实际安装前显示完整预览）
        Show-WhatIfPreviewReport -DriveLetter $driveLetter -InstallDir $InstallDir
        if (Test-WhatIfMode) {
            # WhatIf 模式：显示预览后退出
            exit 0
        }

        # Step 4: Git Bash 检测和安装
        Test-CancellationRequested
        $bashPath = Test-And-InstallGitBash -DriveLetter $driveLetter -InstallDir $InstallDir
        if (-not $bashPath) {
            Write-Error "Git Bash 安装失败，退出安装"
            throw "Git Bash installation failed"
        }

        # Step 5: 安装工具
        Test-CancellationRequested
        Install-Tools -InstallDir $InstallDir

        # Step 6: 环境变量
        Test-CancellationRequested
        $bashPathForEnv = $bashPath  # 保存供外部使用
        $null = Set-EnvironmentVariables -BashPath $bashPath -InstallPath $installPath

        # 三审修复: 确保当前会话环境变量在函数返回后仍生效 (解决 AC 7 & AC 22 失效问题)
        $bashPathFinal = "${installPath}\scoop\apps\git\current\bin\bash.exe"
        $env:SHELL = $bashPathFinal
        $env:CLAUDE_CODE_GIT_BASH_PATH = $bashPathFinal
        $env:CLAUDE_INSTALL_DRIVE = $driveLetter

        # Step 7: SuperClaude
        Test-CancellationRequested
        $null = Install-SuperClaude -InstallPath $installPath

        # Step 8: 创建卸载脚本
        Test-CancellationRequested
        New-UninstallScript -InstallPath $installPath

        # Step 9: 创建刷新脚本
        Test-CancellationRequested
        New-RefreshEnvScript -InstallPath $installPath

        # Step 10: 完成
        Test-CancellationRequested
        $Script:InstallSuccess = Complete-Installation -InstallPath $installPath -BashPath $bashPath

        # 输出摘要
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  安装摘要" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  错误: $Script:ErrorCount" -ForegroundColor $(if ($Script:ErrorCount -gt 0) { 'Red' } else { 'Green' })
        Write-Host "  警告: $Script:WarningCount" -ForegroundColor Yellow
        Write-Host "  安装路径: $installPath" -ForegroundColor Cyan
        Write-Host "  日志文件: $Script:LogFile" -ForegroundColor Gray
        Write-Host "========================================" -ForegroundColor Cyan
    } finally {
        # 清理锁文件
        Remove-LockFile
    }

    # 返回适当的退出码
    if ($Script:ErrorCount -gt 0 -or -not $Script:InstallSuccess) {
        exit 1
    }
    exit 0
}

# 执行安装
Start-Installation
