# Tech-Spec: Claude Code Windows 一键安装器 - v1.0

**创建日期:** 2025-12-23
**更新日期:** 2025-12-27
**版本:** v1.0 (稳定版本)
**状态:** done (已发布)

---

## 概述

### 问题陈述

在 Windows 环境下安装和配置 Claude Code 极其繁琐：
- 需要手动安装大量依赖工具（git、bash、python3.12、nodejs）
- 需要配置多个环境变量（SHELL、CLAUDE_CODE_GIT_BASH_PATH）
- PowerShell 执行策略限制可能导致脚本无法运行
- 安装过程容易出错，难以卸载
- 已安装工具重复安装浪费时间和资源

### 解决方案

Claude Code Windows 环境一键安装器

- 单个 PowerShell 脚本，零配置安装
- Scoop 包管理（Windows 版 brew）
- 自动检测并安装 Git Bash（解决 shell 不存在的问题）
- 智能驱动器选择（D→E→F→C）
- 自动网络测试
- 完整的卸载支持
- 改进的工具存在性检测 - scoop which 优先，命令检测次之，路径检测兜底

### 核心约束

1. 驱动器策略 - D/E/F 优先，C 盘兜底
2. Scoop 优先 - 第一个安装的工具（包含 Git Bash）
3. 用户级权限 - 无需管理员权限
4. 自动化决策 - 最小化用户交互
5. Shell 自动配置 - 自动安装并配置 Git Bash
6. 检测优先级 - scoop which > 命令检测 > 路径检测
7. cc-switch 特殊处理 - 不适用 scoop which

---

## 安装流程

Step 1: 环境检测
  - PowerShell 版本检查
  - 执行策略检测
  - 驱动器选择 (D→E→F→C)

Step 2: 工具存在性检测（优先级：scoop which > 命令检测 > 路径检测）
  - 检测 Scoop 是否已安装
  - Scoop 已安装时：使用 `scoop which <tool>` 检测（cc-switch 除外）
  - Scoop 未安装或 scoop which 失败时：使用 `Get-Command` + 执行版本命令
  - 最后兜底：检查已知安装路径
  - cc-switch 特殊处理：直接命令检测，不尝试 scoop which

Step 3: 安装 Git Bash（如不存在）
  - 检测 Git Bash 是否存在
  - 不存在则通过 Scoop 安装
  - 验证 Git Bash 可用

Step 4: 网络测试
  - 测试 GitHub 连通性
  - 提示网络配置建议

Step 5: 安装 Scoop
  - 检测现有安装
  - 配置镜像源
  - 添加 buckets

Step 6: 安装缺失工具
  - Git（包含 Git Bash）- 如不存在
  - Python 3.12 - 如不存在
  - Node.js LTS - 如不存在
  - cc-switch - 如不存在且指定
  - 其他工具 - 如不存在

Step 7: 配置环境变量
  - SHELL（指向 bash.exe）
  - CLAUDE_CODE_GIT_BASH_PATH
  - pip、npm 镜像源
  - 当前会话临时设置

Step 8: 安装 SuperClaude（可跳过）

Step 9: 验证与完成
  - 显示快速入门指引
  - 显示安装摘要

---

## 验收标准（48 条）

### 核心功能 (AC 1-16)

- [x] AC 1: 检测 PowerShell 版本 >= 5.1
- [x] AC 2: 检测执行策略，Restricted/Undefined 时提供解决指引
- [x] AC 3: 检测 Git Bash 是否存在
- [x] AC 4: Git Bash 不存在时自动通过 Scoop 安装
- [x] AC 5: 验证 Git Bash 安装后可用
- [x] AC 6: Scoop 首先安装
- [x] AC 7: 环境变量正确设置（SHELL、CLAUDE_CODE_GIT_BASH_PATH）
- [x] AC 8: 所有工具可用
- [x] AC 9: D/E/F 优先，C 盘兜底
- [x] AC 10: 只有 C 盘时使用 C 盘
- [x] AC 11: 目录名 smartddd-claude-tools
- [x] AC 12: pip、npm 使用镜像源
- [x] AC 13: cc-switch 通过 Scoop 安装
- [x] AC 14: 卸载完整清理
- [x] AC 15: SuperClaude 自动安装
- [x] AC 16: 支持 CLAUDE_INSTALL_DRIVE

### 执行策略与 Shell (AC 17-22)

- [x] AC 17: Given 执行策略为 Restricted，When 运行脚本，Then 显示解决指引
- [x] AC 18: Given 用户按建议修改策略，When 重新运行，Then 脚本正常执行
- [x] AC 19: Given Git Bash 不存在，When 安装，Then Scoop 自动安装 Git
- [x] AC 20: Given Git Bash 已存在，When 安装，Then 跳过 Git 安装
- [x] AC 21: Given Git Bash 安装完成，When 验证，Then bash.exe 可正常执行
- [x] AC 22: Given SHELL 环境变量未设置，When 安装完成，Then 自动设置并提示重启终端

### 网络与镜像 (AC 23-29)

- [x] AC 23: GitHub 可访问用官方源
- [x] AC 24: GitHub 不可访问用镜像源
- [x] AC 25: 下载失败自动重试 3 次
- [x] AC 26: SuperClaude 失败可继续
- [x] AC 27: C 盘安装显示警告
- [x] AC 28: C 盘空间不足拒绝安装
- [x] AC 29: 错误消息清晰，包含修复建议

### 用户体验 (AC 30-38)

- [x] AC 30: --what-if 预览模式
- [x] AC 31: 进度显示
- [x] AC 32: 快速入门指引
- [x] AC 33: --verbose 详细日志
- [x] AC 34: 当前会话环境变量即时生效
- [x] AC 35: 用户中断处理
- [x] AC 36: 并发安装检测
- [x] AC 37: 镜像源失败自动切换
- [x] AC 38: -SkipSuperClaude 正常工作

### 工具存在性检测 v2.2 (AC 39-42)

- [x] AC 39: Given 所有目标工具，When 执行安装，Then 先检测每个工具的存在性
- [x] AC 40: Given 工具已存在，When 跳过安装，Then 记录到检测报告并显示"已跳过"
- [x] AC 41: Given 工具不存在，When 执行安装，Then 正常安装并标记为"已安装"
- [x] AC 42: Given 工具检测完成，When 显示摘要，Then 显示"已安装: N, 已跳过: M"

### v2.3 检测逻辑改进 (AC 43-48)

- [x] AC 43: Given Scoop 已安装，When 检测工具，Then 首先尝试 `scoop which <tool>`
- [x] AC 44: Given scoop which 返回工具路径，When 继续检测，Then 确认工具已安装
- [x] AC 45: Given scoop which 失败或 Scoop 未安装，When 检测工具，Then 使用 Get-Command + 执行版本命令
- [x] AC 46: Given 命令检测失败，When 最后兜底，Then 检查已知安装路径 (Test-Path)
- [x] AC 47: Given cc-switch 工具，When 检测存在性，Then 不使用 scoop which，直接命令检测
- [x] AC 48: Given 所有检测方法都失败，When 判定工具不存在，Then 标记为"需安装"

---

## 命令行参数

```powershell
.\install.ps1 [
    [-WhatIf]              # 安装预览
    [-Verbose]             # 详细日志
    [-SkipSuperClaude]     # 跳过 SuperClaude
    [-SkipToolCheck]       # 跳过工具存在性检测
    [-InstallDrive <D>]    # 指定驱动器
    [-InstallDir <name>]   # 指定目录名
]
```

---

## 工具存在性检测实现

### 检测优先级策略

```
优先级 1: scoop which <tool>    (Scoop 已安装时优先，cc-switch 除外)
    ↓ 失败
优先级 2: Get-Command + 执行版本命令
    ↓ 失败
优先级 3: Test-Path 已知路径 (兜底)
```

### 检测工具列表

```powershell
$ToolChecks = @(
    @{ Name = "Git";       Command = "git";       VersionCmd = "git --version";       SkipScoopWhich = $false },
    @{ Name = "Python";    Command = "python";    VersionCmd = "python --version";    SkipScoopWhich = $false },
    @{ Name = "Node.js";   Command = "node";      VersionCmd = "node --version";      SkipScoopWhich = $false },
    @{ Name = "Scoop";     Command = "scoop";     VersionCmd = "scoop --version";     SkipScoopWhich = $false },
    @{ Name = "cc-switch"; Command = "cc-switch"; VersionCmd = "cc-switch version";   SkipScoopWhich = $true }
)
```

### 检测函数

```powershell
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
            "$env:SCOOP\apps\git\current\bin\git.exe",
            "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe",
            "C:\Program Files\Git\cmd\git.exe",
            "C:\Program Files (x86)\Git\cmd\git.exe"
        )
        "Python" = @(
            "$env:SCOOP\apps\python312\current\python.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
            "C:\Python312\python.exe"
        )
        "Node.js" = @(
            "$env:SCOOP\apps\nodejs-lts\current\node.exe",
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

# 综合工具检测函数
function Test-ToolExists {
    param(
        [string]$Name,
        [string]$Command,
        [string]$VersionCmd,
        [bool]$SkipScoopWhich = $false
    )

    Write-VerboseLog "检测工具: $Name"

    # 优先级 1: scoop which (cc-switch 除外)
    if (-not $SkipScoopWhich -and (Test-ScoopAvailable)) {
        $scoopResult = Test-ToolWithScoopWhich -ToolName $Command
        if ($scoopResult.Exists) {
            Write-VerboseLog "  → scoop which 检测成功"
            return $scoopResult
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
    Write-Host "检测策略: scoop which > 命令检测 > 路径检测" -ForegroundColor Gray
    Write-Host ""

    $script:ToolStatus = @{}
    $installedCount = 0
    $skippedCount = 0

    foreach ($tool in $ToolChecks) {
        $result = Test-ToolExists `
            -Name $tool.Name `
            -Command $tool.Command `
            -VersionCmd $tool.VersionCmd `
            -SkipScoopWhich $tool.SkipScoopWhich

        $script:ToolStatus[$tool.Name] = $result

        if ($result.Exists) {
            $installedCount++
            $method = $result.Method ?? "unknown"
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
```

---

## 目录结构

{Drive}:\smartddd-claude-tools\
├── scoop\
│   ├── shims\
│   ├── apps\
│   │   └── git\current\
│   │       └── bin\bash.exe
│   └── persist\
├── SuperClaude_Framework\
├── scripts\
│   ├── install.ps1          # 主安装脚本
│   ├── uninstall.ps1        # 卸载脚本（安装时自动生成）
│   └── RefreshEnv.cmd       # 环境刷新脚本（安装时自动生成）
├── logs\
└── README.md

### Dev Agent Record → File List

| 文件 | 说明 | 状态 |
|------|------|------|
| install.ps1 | 主安装脚本，PowerShell 5.1+ | 已实现 |
| uninstall.ps1 | 卸载脚本，嵌入 install.ps1 自动生成 | 已实现 |
| RefreshEnv.cmd | 环境刷新脚本，嵌入 install.ps1 自动生成 | 已实现 |
| tech-spec-*.md | 技术规格文档 | 已完成 |

---

## 网络配置

```powershell
# GitHub 可访问性测试
$githubAccessible = Test-Connection github.com -Count 1 -Quiet -ErrorAction SilentlyContinue
```

---

## 实现要点

### 1. 执行策略检测

```powershell
function Test-ExecutionPolicy {
    $policy = Get-ExecutionPolicy -Scope CurrentUser

    if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
        Write-Host "检测到执行策略限制: $policy" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "解决方案："
        Write-Host "  1. 运行：Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned"
        Write-Host "  或者：powershell -ExecutionPolicy Bypass -File install.ps1"
        Write-Host ""
        Write-Host "修改后请重新运行此脚本" -ForegroundColor Cyan
        exit 1
    }

    Write-Host "执行策略检查通过: $policy" -ForegroundColor Green
}
```

### 2. Git Bash 检测与安装

```powershell
function Test-And-InstallGitBash {
    $bashPaths = @(
        "$env:SCOOP\shims\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "C:\Program Files\Git\bin\bash.exe"
    )

    $bashFound = $false
    foreach ($path in $bashPaths) {
        if (Test-Path $path) {
            $bashFound = $true
            Write-Host "检测到 Git Bash: $path" -ForegroundColor Green
            break
        }
    }

    if (-not $bashFound) {
        Write-Host "未检测到 Git Bash，将通过 Scoop 安装..." -ForegroundColor Yellow

        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
            Install-Scoop
        }

        Write-Host "正在安装 Git..." -ForegroundColor Cyan
        scoop install git -g

        $gitBashPath = "$env:SCOOP\apps\git\current\bin\bash.exe"
        if (Test-Path $gitBashPath) {
            Write-Host "Git Bash 安装成功" -ForegroundColor Green
        } else {
            throw "Git Bash 安装失败"
        }
    }
}
```

### 3. 环境变量配置

```powershell
function Set-EnvironmentVariables {
    $bashPath = "$env:SCOOP\apps\git\current\bin\bash.exe"

    [Environment]::SetEnvironmentVariable('SHELL', $bashPath, 'User')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $bashPath, 'User')

    $env:SHELL = $bashPath
    $env:CLAUDE_CODE_GIT_BASH_PATH = $bashPath

    Write-Host "环境变量已配置" -ForegroundColor Green
    Write-Host "SHELL=$bashPath"
    Write-Host ""
    Write-Host "提示：重启终端后环境变量永久生效" -ForegroundColor Yellow
}
```

### 4. 驱动器选择

```powershell
function Select-InstallDrive {
    foreach ($letter in @('D', 'E', 'F')) {
        if (Test-Path "${letter}:\") {
            $drive = Get-PSDrive $letter
            if ($drive.Free -gt 5GB) { return $letter }
        }
    }
    Write-Warning "只检测到 C 盘，将安装到 C 盘"
    return 'C'
}
```

### 5. 网络测试

```powershell
function Select-MirrorMode {
    if (Test-Connection github.com -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "网络连通，使用官方源" -ForegroundColor Green
        return 'official'
    } else {
        Write-Host "GitHub 不可达，使用国内镜像源" -ForegroundColor Green
        return 'mirror'
    }
}
```

---

## 测试策略

### 单元测试

- 执行策略检测逻辑
- Git Bash 路径检测逻辑
- 驱动器选择逻辑
- 网络测试逻辑
- 工具存在性检测逻辑

### 集成测试

- 完整安装流程
- Git Bash 安装验证
- 环境变量设置
- 卸载流程
- 工具检测跳过已安装项
- 混合场景（部分工具已存在）

### 系统测试

- Windows 10 测试
- Windows 11 测试
- 无 Git 环境测试
- 执行策略受限环境测试
- 部分工具已存在时的混合场景

---

## 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| PowerShell 执行策略限制 | 检测并提供解决指引 |
| Git Bash 不存在 | 自动通过 Scoop 安装 |
| Scoop 安装失败 | 执行策略检测、错误提示 |
| 网络下载失败 | 自动重试 |
| 空间不足 | 安装前检测、警告 |
| 权限问题 | 用户级安装 |
| 重复安装 | 工具存在性检测，跳过已安装项 |

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0.0 | 2025-12-27 | 稳定版本发布，合并所有历史版本功能 |

---

## 附录

### 工具版本

- Scoop: Latest
- Git (含 Git Bash): Latest
- Python: 3.12+
- Node.js: 20.x LTS
- cc-switch: Latest

### 依赖项

- PowerShell 5.1+
- Windows 10/11
- 网络连接

### 关键文件路径

| 路径 | 说明 |
|------|------|
| {InstallDir}\scoop\apps\git\current\bin\bash.exe | Git Bash 主文件 |
| $env:SHELL | 环境变量指向 bash.exe |
| $env:CLAUDE_CODE_GIT_BASH_PATH | Claude Code 需要的变量 |

### 参考资料

- Scoop: https://scoop.sh/
- Git for Windows: https://git-scm.com/download/win
- SuperClaude: https://github.com/SuperClaude-Org/SuperClaude_Framework
