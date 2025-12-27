# PowerShell 5.1+ required (works with both Windows PowerShell and PowerShell Core)
#requires -Version 5.1

# IMPORTANT: [CmdletBinding()] must be the first statement for remote execution (irm | iex)
# For remote installation with parameters, use environment variables:
#   $env:CLAUDE_INSTALL_DRIVE="D"; irm https://.../install.ps1 | iex
#   $env:CLAUDE_SKIP_SUPERCLAUDE="1"; irm https://.../install.ps1 | iex
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$SkipSuperClaude,
    [switch]$IncludeCcSwitch,
    [string]$InstallDrive,
    [string]$InstallDir = "smartddd-claude-tools"
)

# 从环境变量读取远程参数（irm | iex 场景）
if (-not $InstallDrive -and $env:CLAUDE_INSTALL_DRIVE) {
    $InstallDrive = $env:CLAUDE_INSTALL_DRIVE
    Write-VerboseLog "使用环境变量 CLAUDE_INSTALL_DRIVE: $InstallDrive"
}
if (-not $SkipSuperClaude -and $env:CLAUDE_SKIP_SUPERCLAUDE) {
    $SkipSuperClaude = $true
    Write-VerboseLog "使用环境变量 CLAUDE_SKIP_SUPERCLAUDE: true"
}
if (-not $IncludeCcSwitch -and $env:CLAUDE_INCLUDE_CC_SWITCH) {
    $IncludeCcSwitch = $true
    Write-VerboseLog "使用环境变量 CLAUDE_INCLUDE_CC_SWITCH: true"
}

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

    # 执行策略限制时，使用 Bypass 绕过
    powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex"
#>

#=================== 设置 UTF-8 编码 - 修复中文乱码问题 ===================
# 注意：此代码必须在 param() 之后，因为 PowerShell 5.1 要求 [CmdletBinding()] 是脚本的第一个语句
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$OutputEncoding = [System.Text.Encoding]::UTF8
try {
    if ([System.Console]::OutputEncoding.CodePage -ne 65001) {
        chcp 65001 | Out-Null
    }
} catch {
    # 某些环境可能不支持 chcp，忽略错误
}

#=================== 变量初始化 ===================
# 处理 $PSScriptRoot 在 irm | iex 场景下未定义的问题
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { $env:TEMP }

$Script:InstallSuccess = $false
$Script:LogFile = "$scriptRoot\install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

#=================== 辅助函数 ===================

# 并发锁文件 - 包含安装目录标识以支持多实例
# MEDIUM 修复: 统一转换为大写，避免大小写不一致导致的锁失效
$lockId = if ($InstallDrive) { $InstallDrive.ToUpper().TrimEnd(':') } else { 'AUTO' }
$Script:LockFilePath = "$env:TEMP\claude-install-${lockId}.lock"

# 安装工具列表（cc-switch 可能在非默认 bucket）
# 支持 -IncludeCcSwitch 参数将 cc-switch 加入必需工具
# 使用 uv 替代 python312，添加 Claude Code npm 安装
$Script:ToolsToInstall = @('git', 'uv', 'nodejs-lts')
# Claude Code 通过 npm 全局安装，不在 scoop 工具列表中
$Script:NpmGlobalTools = @('@anthropic-ai/claude')
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

    $scoopPath = "$env:USERPROFILE\scoop"

    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           安装预览报告 (WhatIf 模式)                          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "【安装配置】" -ForegroundColor Yellow
    Write-Host "  Scoop 安装目录: $scoopPath (用户级，无需管理员权限)" -ForegroundColor White
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
    $bashPath = "$scoopPath\apps\git\current\bin\bash.exe"
    Write-Host "  SHELL                             → $bashPath" -ForegroundColor White
    Write-Host "  CLAUDE_CODE_GIT_BASH_PATH          → $bashPath" -ForegroundColor White
    Write-Host "  CLAUDE_INSTALL_DRIVE               → 用户目录" -ForegroundColor White
    Write-Host ""

    $superClaudeStatus = if ($SkipSuperClaude) { "跳过" } else { "安装" }
    Write-Host "【其他选项】" -ForegroundColor Yellow
    Write-Host "  SuperClaude:    $superClaudeStatus" -ForegroundColor White
    Write-Host "  脚本目录:       $env:USERPROFILE\scripts\" -ForegroundColor Gray
    Write-Host ""

    # 空间估算（用户目录所在磁盘）
    $userDrive = $env:USERPROFILE.Substring(0, 1)
    $drive = Get-PSDrive -Name $userDrive -ErrorAction SilentlyContinue
    if ($drive) {
        $freeSpace = $drive.Free
        $estimatedSpace = 3GB  # 预估需要约 3GB
        $remainingSpace = $freeSpace - $estimatedSpace

        Write-Host "【磁盘空间】(用户目录所在磁盘)" -ForegroundColor Yellow
        Write-Host "  当前可用:      $([math]::Round($freeSpace / 1GB, 2)) GB" -ForegroundColor White
        Write-Host "  预估需要:      ~3 GB" -ForegroundColor Gray
        Write-Host "  安装后剩余:    $([math]::Round($remainingSpace / 1GB, 2)) GB" -ForegroundColor $(if ($remainingSpace -lt 1GB) { "Red" } elseif ($remainingSpace -lt 5GB) { "Yellow" } else { "Green" })
    } else {
        Write-Host "【磁盘空间】" -ForegroundColor Yellow
        Write-Host "  预估需要:      ~3 GB (用户目录)" -ForegroundColor Gray
    }
    Write-Host ""

    Write-Host "=" * 60 -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "如需实际执行安装，请移除 -WhatIf 参数后重新运行" -ForegroundColor Cyan
    Write-Host ""
}

#=================== 工具存在性检测 ===================

# 检测工具列表（包含 SkipScoopWhich 标记）
$Script:ToolChecks = @(
    @{ Name = "Git";       Command = "git";       VersionCmd = "git --version";       SkipScoopWhich = $false },
    @{ Name = "uv";        Command = "uv";        VersionCmd = "uv --version";        SkipScoopWhich = $false },
    @{ Name = "Node.js";   Command = "node";      VersionCmd = "node --version";      SkipScoopWhich = $false },
    @{ Name = "Scoop";     Command = "scoop";     VersionCmd = "scoop --version";     SkipScoopWhich = $false },
    @{ Name = "cc-switch"; Command = "cc-switch"; VersionCmd = "cc-switch version";   SkipScoopWhich = $true }
)

# 检测 Scoop 是否可用
function Test-ScoopAvailable {
    $scoopCmd = Get-Command "scoop" -ErrorAction SilentlyContinue
    return $null -ne $scoopCmd
}

# 使用 scoop which 检测工具
function Test-ToolWithScoopWhich {
    param([string]$ToolName)

    try {
        $result = scoop which $ToolName 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $result -match $ToolName) {
            return @{
                Exists = $true
                Method = "scoop which"
                Path = $result.Trim()
                Message = "通过 Scoop 安装"
            }
        }
    } catch {
        Write-VerboseLog "scoop which $ToolName 失败: $_"
    }

    return @{ Exists = $false }
}

# 使用 scoop list 检测工具是否安装（scoop which 失败的备选方案）
function Test-ToolWithScoopList {
    param([string]$ToolName)

    try {
        $listResult = scoop list 2>&1 | Out-String
        if ($listResult -match $ToolName) {
            return @{
                Exists = $true
                Method = "scoop list"
                Message = "在 Scoop 中安装，但 scoop which 失败（可能是非标准 shim）"
            }
        }
    } catch {
        Write-VerboseLog "scoop list $ToolName 失败: $_"
    }

    return @{ Exists = $false }
}

# 检查 Scoop shim 文件是否存在
function Test-ToolWithScoopShim {
    param([string]$ToolName)

    $scoopPath = $env:SCOOP
    if (-not $scoopPath) {
        $scoopPath = "$env:USERPROFILE\scoop"
    }

    $shimPaths = @(
        "$scoopPath\shims\$ToolName.exe",
        "$scoopPath\shims\$ToolName.ps1",
        "$scoopPath\shims\$ToolName.cmd",
        "$scoopPath\shims\$ToolName.bat"
    )

    foreach ($shimPath in $shimPaths) {
        if (Test-Path $shimPath) {
            return @{
                Exists = $true
                Method = "shim"
                Path = $shimPath
                Message = "Scoop shim 文件存在"
            }
        }
    }

    return @{ Exists = $false }
}

# 命令检测（Get-Command + 执行版本）
function Test-ToolWithCommand {
    param(
        [string]$Command,
        [string]$VersionCmd
    )

    # 1. Get-Command 检测
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return @{ Exists = $false; Method = "Get-Command" }
    }

    # 2. 执行版本命令验证
    try {
        $output = & $VersionCmd 2>&1 | Out-String
        if ($output) {
            return @{
                Exists = $true
                Method = "command"
                Version = $output.Trim()
                Command = $Command
                Message = "命令可用"
            }
        }
    } catch {
        Write-VerboseLog "版本检查失败 ($VersionCmd): $_"
    }

    return @{
        Exists = $true
        Method = "Get-Command"
        Command = $Command
        Message = "命令存在，版本检查失败"
    }
}

# 路径检测（兜底）
function Test-ToolWithPath {
    param([string]$ToolName)

    $knownPaths = @{
        "Git" = @(
            "$env:USERPROFILE\scoop\apps\git\current\bin\git.exe",
            "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe",
            "C:\Program Files\Git\cmd\git.exe",
            "C:\Program Files (x86)\Git\cmd\git.exe"
        )
        "uv" = @(
            "$env:USERPROFILE\scoop\apps\uv\current\uv.exe",
            "$env:LOCALAPPDATA\Programs\uv\uv.exe",
            "$env:USERPROFILE\.local\bin\uv.exe"
        )
        "Node.js" = @(
            "$env:USERPROFILE\scoop\apps\nodejs-lts\current\node.exe",
            "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
            "C:\Program Files\nodejs\node.exe"
        )
    }

    $paths = $knownPaths[$ToolName]
    if (-not $paths) {
        return @{ Exists = $false }
    }

    foreach ($path in $paths) {
        if (Test-Path $path) {
            return @{
                Exists = $true
                Method = "path"
                Path = $path
                Message = "通过路径检测"
            }
        }
    }

    return @{ Exists = $false }
}

# 综合工具检测函数（优先级增强版：scoop which > scoop list > shim > 命令检测 > 路径检测）
function Test-ToolExists {
    param(
        [string]$Name,
        [string]$Command,
        [string]$VersionCmd,
        [bool]$SkipScoopWhich = $false
    )

    Write-VerboseLog "检测工具: $Name"

    # 优先级 1: scoop which (cc-switch 等跳过)
    if (-not $SkipScoopWhich -and (Test-ScoopAvailable)) {
        $scoopWhichResult = Test-ToolWithScoopWhich -ToolName $Command
        if ($scoopWhichResult.Exists) {
            Write-VerboseLog "  → scoop which 检测成功"
            return $scoopWhichResult
        }

        # scoop which 失败时，尝试 scoop list 作为备选
        Write-VerboseLog "  → scoop which 失败，尝试 scoop list..."
        $scoopListResult = Test-ToolWithScoopList -ToolName $Command
        if ($scoopListResult.Exists) {
            Write-VerboseLog "  → scoop list 检测成功（兼容模式）"
            return $scoopListResult
        }

        # 尝试 shim 文件检测
        Write-VerboseLog "  → scoop list 失败，尝试 shim 文件检测..."
        $shimResult = Test-ToolWithScoopShim -ToolName $Command
        if ($shimResult.Exists) {
            Write-VerboseLog "  → shim 文件检测成功"
            return $shimResult
        }
    }

    # 优先级 2: 命令检测
    $cmdResult = Test-ToolWithCommand -Command $Command -VersionCmd $VersionCmd
    if ($cmdResult.Exists) {
        Write-VerboseLog "  → 命令检测成功"
        return $cmdResult
    }

    # 优先级 3: 路径检测（兜底）
    $pathResult = Test-ToolWithPath -ToolName $Name
    if ($pathResult.Exists) {
        Write-VerboseLog "  → 路径检测成功"
        return $pathResult
    }

    # 最后尝试 - 检查 Scoop 应用目录是否存在
    if (Test-ScoopAvailable) {
        $scoopPath = $env:SCOOP
        if (-not $scoopPath) { $scoopPath = "$env:USERPROFILE\scoop" }

        $appPath = "$scoopPath\apps\$Command"
        if (Test-Path $appPath) {
            Write-VerboseLog "  → Scoop 应用目录检测成功"
            return @{
                Exists = $true
                Method = "scoop app"
                Path = $appPath
                Message = "Scoop 应用目录存在"
            }
        }
    }

    # 未找到
    Write-VerboseLog "  → 未找到"
    return @{
        Exists = $false
        Method = "none"
        Message = "未安装"
    }
}

# 批量工具检测
function Test-AllTools {
    Write-Host "`n=== 工具存在性检测 ===" -ForegroundColor Cyan
    Write-Host "检测策略: scoop which > scoop list > shim > 命令检测 > 路径检测" -ForegroundColor Gray
    Write-Host ""

    $script:ToolStatus = @{}
    $installedCount = 0
    $skippedCount = 0

    foreach ($tool in $Script:ToolChecks) {
        $result = Test-ToolExists `
            -Name $tool.Name `
            -Command $tool.Command `
            -VersionCmd $tool.VersionCmd `
            -SkipScoopWhich $tool.SkipScoopWhich

        $script:ToolStatus[$tool.Name] = $result

        if ($result.Exists) {
            $installedCount++
            # PowerShell 5.1 兼容语法（?? 是 PS7+ 语法）
            $method = if ($result.Method) { $result.Method } else { "unknown" }
            Write-Host "[已安装] $($tool.Name) [$method]" -ForegroundColor Green
            if ($result.Version) {
                Write-Host "         $($result.Version)" -ForegroundColor Gray
            }
        } else {
            $skippedCount++
            Write-Host "[需安装] $($tool.Name)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "检测完成: 已安装 $installedCount, 需安装 $skippedCount" -ForegroundColor Cyan
    Write-Host "使用策略: scoop which 优先，命令检测次之，路径检测兜底" -ForegroundColor Gray

    return $script:ToolStatus
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

    # Restricted: 必须阻止
    if ($policy -eq 'Restricted') {
        Write-Error "检测到执行策略限制: $policy"
        Write-Host ""
        Write-Host "解决方案：" -ForegroundColor Yellow
        Write-Host "  1. 运行: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned" -ForegroundColor Cyan
        Write-Host "  2. 或者: powershell -ExecutionPolicy Bypass -File install.ps1" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "修改后请重新运行此脚本" -ForegroundColor Cyan
        return $false
    }

    # Undefined: 尝试自动设置为 RemoteSigned（用户友好）
    if ($policy -eq 'Undefined') {
        Write-Warning "检测到执行策略为 Undefined，尝试自动设置..."
        try {
            # 尝试自动设置执行策略
            $null = Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            $newPolicy = Get-ExecutionPolicy -Scope CurrentUser
            Write-Success "执行策略已自动设置为: $newPolicy"
        } catch {
            Write-Error "自动设置执行策略失败: $_"
            Write-Host ""
            Write-Host "解决方案：" -ForegroundColor Yellow
            Write-Host "  1. 运行: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned" -ForegroundColor Cyan
            Write-Host "  2. 或者: powershell -ExecutionPolicy Bypass -File install.ps1" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "修改后请重新运行此脚本" -ForegroundColor Cyan
            return $false
        }
    } else {
        Write-Success "执行策略检查通过: $policy"
    }

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

#=================== AC 23-26: 网络测试 ===================

function Test-NetworkAndSelectMirror {
    Write-Header "Step 3: 网络测试"

    # AC 23-24: GitHub 连通性测试
    # WhatIf 模式: 跳过实际网络测试
    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 测试 GitHub 连通性..." -ForegroundColor DarkGray
        Write-Success "[WhatIf] GitHub 连通性测试跳过"
        return $true
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

    if ($githubAccessible) {
        Write-Success "GitHub 可达"
    } else {
        Write-Warning "GitHub 不可达，请检查网络连接"
        Write-Host "  提示: 如无法访问 GitHub，可能需要配置代理或 VPN" -ForegroundColor Cyan
    }

    return $githubAccessible
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
        $mockBashPath = "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
        Write-Success "[WhatIf] Git Bash 检测/安装跳过"
        return $mockBashPath
    }

    # AC 3: 检测 Git Bash 是否存在
    Write-Step "检测 Git Bash..."

    $bashPaths = @(
        "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe",
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

        # 验证 Scoop 是否安装成功
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Write-Error "Scoop 安装失败，无法继续安装 Git"
            Write-Host "  请手动运行以下命令后重试:" -ForegroundColor Cyan
            Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
            Write-Host "  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression" -ForegroundColor Cyan
            return $null
        }
    } else {
        Write-Success "Scoop 已安装"
    }

    # 确保 Scoop 环境变量正确配置
    Write-Step "配置 Scoop 环境..."
    $null = Initialize-ScoopEnvironment -DriveLetter $DriveLetter -InstallDir $InstallDir

    # 安装 Git
    Write-Step "正在安装 Git (包含 Git Bash)..."

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] scoop install git --skip-update" -ForegroundColor DarkGray
        $bashPath = "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
    } else {
        $installGitScript = {
            # 使用 --skip-update 参数跳过 Scoop 更新
            $ErrorActionPreference = 'Continue'
            scoop install --skip-update git 2>&1 | Tee-Object -Variable installOutput
            return $LASTEXITCODE
        }.GetNewClosure()

        $result = Invoke-RetryCommand -ScriptBlock $installGitScript -Description "Git 安装" -MaxRetries 3
        $bashPath = "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"

        if ($null -eq $result) {
            # 额外诊断：检查 Git 是否实际上已安装
            if (Test-Path $bashPath) {
                Write-Warning "Git 安装命令返回失败，但 Git Bash 文件已存在，尝试验证..."
                try {
                    $testResult = & "$bashPath" --version 2>&1
                    if ($testResult) {
                        Write-Success "Git Bash 验证成功: $testResult"
                        return $bashPath
                    }
                } catch {
                    Write-VerboseLog "Git Bash 验证失败: $_"
                }
            }

            Write-Error "Git 安装失败"
            Write-Host "  可能原因: 网络问题或权限不足" -ForegroundColor Cyan
            Write-Host "  请手动运行: scoop install git" -ForegroundColor Cyan
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

# 确保 Scoop 环境正确配置
function Initialize-ScoopEnvironment {
    param([string]$DriveLetter, [string]$InstallDir)

    # 如果 SCOOP 环境变量已设置且有效，直接返回
    if ($env:SCOOP -and (Test-Path "$env:SCOOP\apps")) {
        Write-VerboseLog "SCOOP 环境变量已配置: $env:SCOOP"
        return $true
    }

    # 尝试从已知路径检测 Scoop（用户级优先）
    $possibleScoopPaths = @(
        "$env:USERPROFILE\scoop",
        "$env:LOCALAPPDATA\scoop"
    )

    foreach ($path in $possibleScoopPaths) {
        if (Test-Path "$path\apps") {
            $env:SCOOP = $path
            Write-VerboseLog "检测到 Scoop 路径: $path"
            return $true
        }
    }

    Write-Warning "未能检测到有效的 Scoop 安装路径"
    return $false
}

function Install-Scoop {
    param(
        [string]$DriveLetter,
        [string]$InstallDir
    )

    Write-Step "安装 Scoop 包管理器..."

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 安装 Scoop 到用户目录 ~\scoop" -ForegroundColor DarkGray
        return
    }

    # 用户级安装使用默认目录
    $scoopDir = "$env:USERPROFILE\scoop"

    # 如果已存在 Scoop，跳过（先检查变量是否为空）
    if ($env:SCOOP -and (Test-Path $env:SCOOP)) {
        Write-Success "Scoop 已存在"
        return
    }

    # 配置 Scoop 安装路径（用户级）
    $env:SCOOP = $scoopDir

    # AC 25: 使用重试逻辑，按照官方 Scoop 安装命令
    $installScript = {
        $ErrorActionPreference = 'Continue'

        # 官方 Scoop 安装命令
        # 第一步：设置执行策略（如果尚未设置）
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
        if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'Undefined') {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
        }

        # 第二步：执行 Scoop 安装脚本
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

        return $LASTEXITCODE
    }.GetNewClosure()

    $result = Invoke-RetryCommand -ScriptBlock $installScript -Description "Scoop 安装" -MaxRetries 3

    # 验证 Scoop 是否安装成功
    $scoopInstalled = $false
    if ($null -ne $result) {
        # 检查 scoop 命令是否可用
        $scoopCheck = Get-Command scoop -ErrorAction SilentlyContinue
        if ($scoopCheck) {
            $scoopInstalled = $true
        }
    }

    # 如果命令检测失败，尝试直接检测 scoop 目录
    if (-not $scoopInstalled -and (Test-Path "$scoopDir\apps\scoop")) {
        $scoopInstalled = $true
    }

    if ($scoopInstalled) {
        Write-Success "Scoop 安装完成"
    } else {
        Write-Error "Scoop 安装失败"
        Write-Host "  请手动运行以下命令后重试:" -ForegroundColor Cyan
        Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
        Write-Host "  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression" -ForegroundColor Cyan
    }
}

#=================== AC 7, 11-12: 工具安装和环境变量 ===================

function Install-Tools {
    param([string]$InstallDir)

    Write-Header "Step 5: 安装开发工具"

    # AC 11: 目录名 smartddd-claude-tools

    # 安装必需工具
    foreach ($tool in $Script:ToolsToInstall) {
        Write-Step "安装 $tool..."

        if (Test-WhatIfMode) {
            Write-Host "    [WHATIF] scoop install $tool" -ForegroundColor DarkGray
            continue
        }

        # 检查工具是否已安装
        $toolCommand = $tool
        # 特殊处理：uv 和 nodejs-lts 的命令名
        if ($tool -eq 'uv') { $toolCommand = 'uv' }
        if ($tool -eq 'nodejs-lts') { $toolCommand = 'node' }

        if (Get-Command $toolCommand -ErrorAction SilentlyContinue) {
            $version = & $toolCommand --version 2>&1 | Select-Object -First 1
            Write-Success "$tool 已安装 - $version"
            continue
        }

        Test-CancellationRequested

        # 跳过 Scoop 更新，直接安装（更新失败不影响安装）
        $installToolScript = {
            # 使用 --skip-update 参数跳过 Scoop 更新
            $ErrorActionPreference = 'Continue'
            scoop install --skip-update $tool 2>&1
            return $LASTEXITCODE
        }.GetNewClosure()

        $result = Invoke-RetryCommand -ScriptBlock $installToolScript -Description "$tool 安装" -MaxRetries 3

        if ($null -ne $result) {
            # 获取安装的版本信息
            $version = & $toolCommand --version 2>&1 | Select-Object -First 1
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

        # 检查工具是否已安装
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            $version = & $tool --version 2>&1 | Select-Object -First 1
            Write-Success "$tool 已安装 - $version"
            continue
        }

        # 检查工具是否在可用 bucket 中
        $searchResult = scoop search $tool 2>&1
        if ($searchResult -match $tool) {
            try {
                # cc-switch 在 extras bucket，需要先添加
                if ($tool -eq 'cc-switch') {
                    $bucketAdded = $false
                    $buckets = scoop bucket list 2>&1 | Out-String
                    if ($buckets -notmatch 'extras') {
                        Write-VerboseLog "添加 extras bucket..."
                        scoop bucket add extras 2>&1 | Out-Null
                        $bucketAdded = $true
                    }
                }

                scoop install --skip-update $tool 2>&1 | Out-Null
                Write-Success "$tool 安装完成"
            } catch {
                Write-Warning "$tool 安装失败，跳过"
            }
        } else {
            Write-Warning "$tool 在默认 bucket 中未找到，跳过安装"
            Write-Host "  如需安装，可能需要添加额外 bucket: scoop bucket add <bucket-name>" -ForegroundColor Gray
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

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] SHELL = $BashPath" -ForegroundColor DarkGray
        Write-Host "    [WHATIF] CLAUDE_CODE_GIT_BASH_PATH = $BashPath" -ForegroundColor DarkGray
        Write-Host "    [WHATIF] CLAUDE_INSTALL_DIR = $env:USERPROFILE\scoop" -ForegroundColor DarkGray
    } else {
        # 设置用户级环境变量
        [Environment]::SetEnvironmentVariable('SHELL', $BashPath, 'User')
        [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $BashPath, 'User')
        [Environment]::SetEnvironmentVariable('CLAUDE_INSTALL_DIR', "$env:USERPROFILE\scoop", 'User')

        # 当前会话临时设置
        $env:SHELL = $BashPath
        $env:CLAUDE_CODE_GIT_BASH_PATH = $BashPath
        $env:CLAUDE_INSTALL_DIR = "$env:USERPROFILE\scoop"

        Write-Success "环境变量已配置"
    }

    # 显示配置信息
    Write-Host ""
    Write-Host "配置信息:" -ForegroundColor Cyan
    Write-Host "  SHELL=$BashPath"
    Write-Host "  CLAUDE_CODE_GIT_BASH_PATH=$BashPath"
    Write-Host "  CLAUDE_INSTALL_DIR=$env:USERPROFILE\scoop"
    Write-Host ""

    # AC 34: 当前会话环境变量即时生效
    Write-Success "当前会话环境变量已生效"

    return $true
}

#=================== Claude Code npm 安装 ===================

function Install-ClaudeCode {
    param([string]$InstallPath)

    Write-Header "Step 6.5: 安装 Claude Code"

    Write-Step "检查 Claude Code 是否已安装..."

    # 检查是否已安装
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        try {
            $version = claude --version 2>&1 | Out-String
            if ($version) {
                Write-Success "Claude Code 已安装 - $version"
                return $true
            }
        } catch {
            Write-Success "Claude Code 已安装"
            return $true
        }
    }

    # 检查 npm 是否可用
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Error "npm 不可用，无法安装 Claude Code"
        Write-Host "  请确保 Node.js 已正确安装" -ForegroundColor Cyan
        return $false
    }

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] npm install -g @anthropic-ai/claude" -ForegroundColor DarkGray
        return $true
    }

    try {
        Write-Step "通过 npm 全局安装 Claude Code..."

        # 使用 npm 全局安装
        $npmInstallScript = {
            $ErrorActionPreference = 'Continue'
            npm install -g @anthropic-ai/claude 2>&1
            return $LASTEXITCODE
        }.GetNewClosure()

        $result = Invoke-RetryCommand -ScriptBlock $npmInstallScript -Description "Claude Code 安装" -MaxRetries 3

        if ($result -ne $null -or (Get-Command claude -ErrorAction SilentlyContinue)) {
            try {
                $version = claude --version 2>&1 | Out-String
                if ($version) {
                    Write-Success "Claude Code 安装完成 - $version"
                } else {
                    Write-Success "Claude Code 安装完成"
                }
                return $true
            } catch {
                Write-Success "Claude Code 安装完成"
                return $true
            }
        } else {
            Write-Warning "Claude Code 安装失败，但可继续"
            Write-Host "  可手动运行: npm install -g @anthropic-ai/claude" -ForegroundColor Cyan
            return $true  # 不阻断安装流程
        }
    } catch {
        Write-Warning "Claude Code 安装失败: $_"
        Write-Host "可手动安装或稍后重试" -ForegroundColor Cyan
        return $true  # 失败可继续
    }
}

#=================== Claude Code 跳过 onboarding 配置 ===================

function Set-ClaudeOnboardingConfig {
    Write-Header "Step 6.6: 配置 Claude Code 跳过 onboarding"

    Write-Step "配置 Claude Code 跳过 onboarding..."

    # 检查 Node.js 是否可用
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Node.js 不可用，跳过 onboarding 配置"
        return $true
    }

    $claudeJsonPath = "$env:USERPROFILE\.claude.json"

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] 配置 $claudeJsonPath 设置 hasCompletedOnboarding: true" -ForegroundColor DarkGray
        return $true
    }

    try {
        # 使用 Node.js 脚本创建/修改 .claude.json
        $nodeScript = @"
const fs = require('fs');
const path = require('path');
const os = require('os');

const filePath = path.join(os.homedir(), '.claude.json');
let content = {};

if (fs.existsSync(filePath)) {
    try {
        const existing = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
        content = existing;
    } catch (e) {
        // 解析失败则使用空对象
    }
}

content.hasCompletedOnboarding = true;
fs.writeFileSync(filePath, JSON.stringify(content, null, 2), 'utf-8');
console.log('Configuration saved to: ' + filePath);
"@

        $result = node --eval $nodeScript 2>&1 | Out-String

        # 验证文件是否成功创建
        if (Test-Path $claudeJsonPath) {
            $claudeConfig = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeConfig -match 'hasCompletedOnboarding') {
                Write-Success "Claude Code onboarding 配置完成"
                Write-VerboseLog "配置文件: $claudeJsonPath"
                return $true
            } else {
                Write-Warning "Claude Code 配置文件可能未正确配置"
                return $true  # 不阻断安装流程
            }
        } else {
            Write-Warning "Claude Code 配置文件创建失败"
            return $true  # 不阻断安装流程
        }
    } catch {
        Write-Warning "Claude Code onboarding 配置失败: $_"
        return $true  # 失败可继续
    }
}

#=================== SuperClaude 安装 ===================
# 使用 uv 进行环境初始化

function Install-SuperClaude {
    param([string]$InstallPath)

    # 自动安装
    # 失败可继续

    if ($SkipSuperClaude) {
        Write-Warning "跳过 SuperClaude 安装 (用户指定)"
        return $true
    }

    Write-Header "Step 7: 安装 SuperClaude (可选)"

    # 安装到用户目录
    $superClaudePath = "$env:USERPROFILE\SuperClaude_Framework"

    if (Test-Path $superClaudePath) {
        Write-Success "SuperClaude 已存在"
        return $true
    }

    if (Test-WhatIfMode) {
        Write-Host "    [WHATIF] git clone SuperClaude 到 $superClaudePath" -ForegroundColor DarkGray
        Write-Host "    [WHATIF] uv pip install -e $superClaudePath" -ForegroundColor DarkGray
        return $true
    }

    try {
        # 确保 git 可用后再克隆
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Error "Git 命令不可用，SuperClaude 安装失败"
            Write-Host "  请确保 Git 已正确安装后再尝试安装 SuperClaude" -ForegroundColor Cyan
            return $false
        }

        # 确保 uv 可用
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Write-Warning "uv 不可用，无法完成 SuperClaude 环境初始化"
            Write-Host "  请确保 uv 已正确安装" -ForegroundColor Cyan
            return $false
        }

        # 克隆仓库
        Write-Step "克隆 SuperClaude 框架..."
        $repoUrl = "https://github.com/SuperClaude-Org/SuperClaude_Framework.git"
        git clone $repoUrl $superClaudePath 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "SuperClaude 克隆失败，但可继续"
            Write-Host "  可手动运行: git clone $repoUrl $superClaudePath" -ForegroundColor Cyan
            return $true
        }

        # 使用 uv 进行环境初始化
        Write-Step "使用 uv 初始化 SuperClaude 环境..."

        # 检查是否有 pyproject.toml 或 requirements
        $pyprojectPath = Join-Path $superClaudePath "pyproject.toml"
        $requirementsPath = Join-Path $superClaudePath "requirements.txt"

        if (Test-Path $pyprojectPath) {
            # 使用 uv pip install -e 安装
            Write-VerboseLog "检测到 pyproject.toml，使用 uv pip install -e"
            $uvInstallResult = uv pip install -e $superClaudePath --system 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "SuperClaude 环境初始化完成"
            } else {
                Write-Warning "SuperClaude uv 安装部分失败: $uvInstallResult"
            }
        } elseif (Test-Path $requirementsPath) {
            # 使用 requirements.txt 安装
            Write-VerboseLog "检测到 requirements.txt，使用 uv pip install -r"
            $uvInstallResult = uv pip install -r $requirementsPath --system 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "SuperClaude 环境初始化完成"
            } else {
                Write-Warning "SuperClaude uv 安装部分失败: $uvInstallResult"
            }
        } else {
            Write-VerboseLog "未检测到依赖文件，跳过 uv 安装"
        }

        Write-Success "SuperClaude 安装完成"
        return $true

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

    # CancelKeyPress 仅在 .NET Core/PowerShell 7+ 中可用
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            [Console]::CancelKeyPress += $handler
        }
    } catch {
        Write-VerboseLog "CancelKeyPress 不可用，跳过中断处理"
    }
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
    Write-Host "║       Claude Code 开发环境卸载程序                        ║" -ForegroundColor Red
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
    Write-Host "║       Claude Code 开发环境卸载程序                        ║" -ForegroundColor Red
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

    # 使用 scoop list 验证 scoop 安装的工具
    # 获取 scoop list 输出用于查找版本信息
    $scoopListOutput = $null
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        $scoopListOutput = scoop list 2>&1 | Out-String
    }

    # 验证工具列表 - 使用 scoop 包名
    # PowerShell 5.1 兼容，键名必须用引号包裹
    $toolsToVerifyMap = @{}
    $toolsToVerifyMap['git'] = @{Name = 'git';       Package = 'git';       Command = 'git';       InstalledByScoop = $true }
    $toolsToVerifyMap['uv'] = @{Name = 'uv';         Package = 'uv';         Command = 'uv';         InstalledByScoop = $true }
    $toolsToVerifyMap['nodejs-lts'] = @{Name = 'node'; Package = 'nodejs-lts'; Command = 'node'; InstalledByScoop = $true }
    $toolsToVerifyMap['scoop'] = @{Name = 'scoop';   Package = 'scoop';    Command = 'scoop';    InstalledByScoop = $false }

    # AC 13: 如果安装了 cc-switch，也需要验证
    if ($Script:ToolsToInstall -contains 'cc-switch' -or $IncludeCcSwitch) {
        $toolsToVerifyMap['cc-switch'] = @{Name = 'cc-switch'; Package = 'cc-switch'; Command = 'cc-switch'; InstalledByScoop = $true}
    }

    $verifiedTools = @{}
    $verifiedCount = 0
    $totalCount = $toolsToVerifyMap.Count

    foreach ($tool in $toolsToVerifyMap.Values) {
        $packageName = $tool.Package
        $displayName = $tool.Name
        $commandName = $tool.Command

        # 先尝试 scoop list 验证 scoop 安装的工具
        $foundViaScoopList = $false
        if ($tool.InstalledByScoop -and $scoopListOutput) {
            $lines = $scoopListOutput -split "`n"
            foreach ($line in $lines) {
                # 跳过表头、分隔线、空行和 bucket 区域
                if ($line -match '^(Package|------|\s*$)') { continue }
                if ($line -match "Current Scoop version:|'main' bucket:|'extras' bucket:|Installed apps:") { continue }

                # 匹配包名
                if ($line -match [regex]::Escape($packageName)) {
                    # 提取版本号 - 查找包名后面以数字开头的版本
                    $version = $null
                    $idx = $line.IndexOf($packageName)
                    if ($idx -ge 0) {
                        $rest = $line.Substring($idx + $packageName.Length).Trim()
                        # 提取版本号（数字开头）
                        if ($rest -match '^([0-9][^\s\[]*)') {
                            $version = $matches[1]
                        }
                    }

                    if ($version) {
                        Write-Success "$displayName 可用 (Scoop) - $version"
                    } else {
                        Write-Success "$displayName 可用 (Scoop)"
                    }
                    $verifiedTools[$displayName] = $true
                    $verifiedCount++
                    $foundViaScoopList = $true
                    break
                }
            }
        }

        if ($foundViaScoopList) { continue }

        # scoop list 验证失败，使用命令检测作为兜底
        $cmd = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                $ErrorActionPreference = 'Continue'
                $output = & $commandName --version 2>&1 | Out-String
                $ErrorActionPreference = 'Stop'
                $versionOutput = $output.Trim()

                # 过滤 scoop 版本输出中的 bucket 信息
                if ($commandName -eq 'scoop') {
                    $versionLines = $versionOutput -split "`n" | Where-Object { $_ -match '\S' }
                    $versionOutput = $versionLines[0]
                }

                if ($versionOutput) {
                    Write-Success "$displayName 可用 - $versionOutput"
                    $verifiedTools[$displayName] = $true
                    $verifiedCount++
                } else {
                    Write-Warning "$displayName 命令存在但获取版本失败"
                }
            } catch {
                Write-Warning "$displayName 命令存在但获取版本失败"
            }
        } else {
            Write-Warning "$displayName 未安装"
        }
    }

    # 显示验证统计（scoop list + 命令兜底）
    Write-Host ""
    Write-Host "验证统计: $verifiedCount/$totalCount 个工具可用" -ForegroundColor $(if ($verifiedCount -eq $totalCount) { 'Green' } else { 'Yellow' })

    # 验证 Claude Code
    Write-Step "验证 Claude Code..."
    $claudeVerified = $false
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        try {
            $claudeVersion = claude --version 2>&1 | Out-String
            if ($claudeVersion) {
                Write-Success "Claude Code 可用 - $claudeVersion"
                $claudeVerified = $true
                $verifiedTools['claude'] = $true
            }
        } catch {
            Write-Success "Claude Code 可用"
            $claudeVerified = $true
            $verifiedTools['claude'] = $true
        }
    } else {
        Write-Warning "Claude Code 未安装或不可用"
        Write-Host "  可运行: npm install -g @anthropic-ai/claude" -ForegroundColor Cyan
    }

    # 检查核心工具是否至少有一个可用
    $coreToolsOk = $verifiedTools.ContainsKey('git') -and $verifiedTools.ContainsKey('uv') -and (
        $verifiedTools.ContainsKey('node') -or $verifiedTools.ContainsKey('nodejs-lts')
    ) -and $claudeVerified

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
    Write-Host "日志文件: $Script:LogFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "下一步操作:" -ForegroundColor Yellow
    Write-Host "  1. 重启终端或运行 RefreshEnv.cmd 刷新环境" -ForegroundColor Cyan
    Write-Host "  2. Claude Code CLI 命令为 'claude'" -ForegroundColor Cyan
    Write-Host "  3. 运行 'claude --help' 验证" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "如需卸载，运行: $env:USERPROFILE\scripts\uninstall.ps1" -ForegroundColor Cyan
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

    # CancelKeyPress 仅在 .NET Core/PowerShell 7+ 中可用
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            [Console]::CancelKeyPress += $handler
        }
    } catch {
        Write-VerboseLog "CancelKeyPress 不可用，跳过中断处理"
    }
}

#=================== 主流程 ===================

function Start-Installation {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       Claude Code Windows 一键安装器 v1.0.0                      ║" -ForegroundColor Cyan
    Write-Host "║       Author: SmartDDD Lab                                      ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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

        # 确保当前会话环境变量在函数返回后仍生效
        $bashPathFinal = "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
        $env:SHELL = $bashPathFinal
        $env:CLAUDE_CODE_GIT_BASH_PATH = $bashPathFinal
        $env:CLAUDE_INSTALL_DIR = "$env:USERPROFILE\scoop"

        # Step 6.5: Claude Code (通过 npm 全局安装，必须在 SuperClaude 之前)
        Test-CancellationRequested
        $null = Install-ClaudeCode -InstallPath ""

        # Step 6.6: 配置 Claude Code 跳过 onboarding
        Test-CancellationRequested
        $null = Set-ClaudeOnboardingConfig

        # Step 7: SuperClaude (安装到用户目录)
        Test-CancellationRequested
        $superClaudePath = "$env:USERPROFILE\SuperClaude_Framework"
        $null = Install-SuperClaude -InstallPath $superClaudePath

        # Step 8: 完成（卸载脚本和刷新脚本功能已移除）
        Test-CancellationRequested
        $Script:InstallSuccess = Complete-Installation -InstallPath "$env:USERPROFILE\scoop" -BashPath $bashPath

        # 输出摘要
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  安装摘要" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  错误: $Script:ErrorCount" -ForegroundColor $(if ($Script:ErrorCount -gt 0) { 'Red' } else { 'Green' })
        Write-Host "  警告: $Script:WarningCount" -ForegroundColor Yellow
        Write-Host "  Scoop 目录: $env:USERPROFILE\scoop" -ForegroundColor Cyan
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
