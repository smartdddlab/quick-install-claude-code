# Claude Code Windows 一键安装器

[![Windows](https://img.shields.io/badge/Windows-0078D4?style=flat-square&logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat-square&logo=powershell&logoColor=white)](https://docs.microsoft.com/zh-cn/powershell/)
[![License](https://img.shields.io/badge/License-MIT-yellowgreen?style=flat-square)]()

在 Windows 环境下快速安装和配置 Claude Code 开发环境，自动安装所有依赖工具。

## 简介

本安装器自动化以下工作：

- ✅ 通过 Scoop 包管理器安装开发工具（Git、Python、Node.js 等）
- ✅ 自动检测并安装 Git Bash（如不存在）
- ✅ 智能工具检测，跳过已安装项（节省时间和资源）
- ✅ 智能选择最佳安装驱动器（D/E/F 优先，C 盘兜底）
- ✅ 自动检测网络环境（GitHub 可访问性测试）
- ✅ 配置环境变量（SHELL、CLAUDE_CODE_GIT_BASH_PATH）
- ✅ 可选安装 SuperClaude 框架

## 快速开始（3 步）

### 第 1 步：一键安装（推荐）

直接在 PowerShell 中运行以下命令：

```powershell
# 从 GitHub 一键安装（推荐）
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex
```

或者指定安装选项：

```powershell
# 安装到 D 盘
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex -InstallDrive D

# 跳过 SuperClaude
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex -SkipSuperClaude
```

### 第 2 步：下载脚本本地运行（备选）

如果一键安装失败，可手动下载脚本到本地运行：

```powershell
# 下载脚本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1" -OutFile install.ps1

# 运行安装
.\install.ps1
```

### 第 3 步：开始使用

安装完成后：
1. 重启终端使环境变量生效
2. 运行 `claude` 启动 Claude Code

## 安装前检查

### PowerShell 版本要求

- 版本：5.1 或更高
- 检查方法：在 PowerShell 中运行 `$PSVersionTable.PSVersion`

### 执行策略设置

如果遇到执行策略限制，按以下流程操作：

```
┌─────────────────────────────────────────────────────────────┐
│  执行策略检查流程                                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 运行安装脚本                                            │
│     ↓                                                       │
│  2. 检测到执行策略限制 (Restricted/Undefined)               │
│     ↓                                                       │
│  3. 脚本显示解决方案并退出                                  │
│     ↓                                                       │
│  4. 用户选择解决方案:                                       │
│     ├─ 方案A: 临时绕过（推荐用于首次安装）                  │
│ │    powershell -ExecutionPolicy Bypass -File install.ps1  │
│ │    ↓                                                      │
│ │    直接开始安装 ✓                                         │
│ │                                                           │
│     └─ 方案B: 永久修改（推荐用于长期使用）                  │
│        Set-ExecutionPolicy -Scope CurrentUser `            │
│          -ExecutionPolicy RemoteSigned                     │
│        ↓                                                    │
│        重新运行: .\install.ps1                             │
│        ↓                                                    │
│        开始安装 ✓                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**解决方法：**

```powershell
# 方案 1：临时绕过（首次安装推荐）
# 无需修改策略，直接绕过限制运行
powershell -ExecutionPolicy Bypass -File install.ps1

# 方案 2：永久修改（长期使用推荐）
# 修改后可正常运行 .\install.ps1
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# 修改后，重新运行安装脚本
.\install.ps1
```

**重要提示：**
- 方案 1 不会修改系统设置，仅本次会话有效
- 方案 2 会永久修改当前用户的执行策略，之后可直接运行脚本
- 修改策略后，**必须重新运行 `.\install.ps1`** 才能继续安装

### Git Bash

安装器会自动检测 Git Bash：
- 如果不存在，通过 Scoop 自动安装
- 无需手动预装

## 安装后做什么

### 1. 验证安装

```powershell
# 检查环境变量
echo $env:SHELL
echo $env:CLAUDE_CODE_GIT_BASH_PATH

# 检查工具版本
git --version
python --version
node --version
scoop --version
```

### 2. 配置 Claude Code

首次运行 `claude`，按照提示完成配置。

### 3. 启动开发

在配置了 SHELL 环境变量的终端中使用 Claude Code。

## 命令行参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-WhatIf` | 预览安装过程，不实际执行 | `.\install.ps1 -WhatIf` |
| `-Verbose` | 显示详细日志 | `.\install.ps1 -Verbose` |
| `-SkipSuperClaude` | 跳过 SuperClaude 安装 | `.\install.ps1 -SkipSuperClaude` |
| `-SkipToolCheck` | v1.0: 跳过工具存在性检测 | `.\install.ps1 -SkipToolCheck` |
| `-InstallDrive <盘符>` | 指定安装驱动器 | `.\install.ps1 -InstallDrive D` |
| `-InstallDir <目录名>` | 指定安装目录名（默认：smartddd-claude-tools） | `.\install.ps1 -InstallDir mytools` |

## 目录结构

```
{Drive}:\smartddd-claude-tools\
├── scoop\                       # Scoop 包管理器
│   ├── shims\                  # 命令 shims
│   ├── apps\                   # 安装的应用
│   │   └── git\current\
│   │       └── bin\bash.exe    # Git Bash
│   └── persist\                # 持久化数据
├── SuperClaude_Framework\      # SuperClaude 框架（可选）
└── README.md                   # 本文档
```

## 常见问题（FAQ）

### Q: 提示 "No suitable shell found" 怎么办？

确保 Git Bash 已正确安装：

```powershell
# 检查 bash.exe 是否存在
if ($env:SCOOP) {
    Test-Path "$env:SCOOP\apps\git\current\bin\bash.exe"
}

# 如不存在，重新运行安装脚本
.\install.ps1
```

### Q: 执行策略限制怎么解决？

```powershell
# 查看当前策略
Get-ExecutionPolicy -Scope CurrentUser

# 修改策略
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Q: 安装速度慢怎么办？

请确保网络连接正常，可以访问 GitHub。如网络较慢，可能需要配置代理或 VPN。

如仍有问题，请查看详细日志：`.\install.ps1 -Verbose`

### Q: 如何指定安装位置？

```powershell
# 安装到 D 盘
.\install.ps1 -InstallDrive "D"

# 安装到 E 盘自定义目录
.\install.ps1 -InstallDrive "E" -InstallDir "my-claude-tools"
```

### Q: SuperClaude 是什么？要安装吗？

SuperClaude 是一个增强 Claude Code 体验的框架，包含：
- 高级工作流
- 专家 Agent 模式
- 更好的代码审查功能

可选安装，如不需要加 `-SkipSuperClaude` 参数。

### Q: 卸载后环境变量还在？

请**重启终端**使环境变量更改生效。

## 故障排除

### 安装失败

1. 检查 PowerShell 版本：`$PSVersionTable.PSVersion`
2. 检查执行策略：`Get-ExecutionPolicy -Scope CurrentUser`
3. 以管理员身份运行 PowerShell 重新安装
4. 查看详细日志：`.\install.ps1 -Verbose`

### 环境变量不生效

1. 重启终端
2. 检查用户级环境变量：
   ```powershell
   [Environment]::GetEnvironmentVariable('SHELL', 'User')
   [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')
   ```

### Git Bash 找不到

```powershell
# 查找 bash.exe 位置
Get-ChildItem -Path "C:\", "D:\", "E:\", "F:\" -Filter "bash.exe" -Recurse -ErrorAction SilentlyContinue -Force
```

### Scoop 安装失败

1. 检查网络连接
2. 尝试手动安装 Scoop：
   ```powershell
   Invoke-WebRequest -UseBypass get.scoop.sh | Invoke-Expression
   ```

## 卸载

手动卸载：

1. 删除安装目录
2. 删除环境变量：SHELL、CLAUDE_CODE_GIT_BASH_PATH
3. （可选）删除 Scoop 目录

## 系统要求

| 要求 | 详情 |
|------|------|
| 操作系统 | Windows 10 / Windows 11 |
| PowerShell | 5.1 或更高 |
| 磁盘空间 | 至少 5GB 可用空间 |
| 网络 | 需要互联网连接（下载工具） |

## 依赖工具

安装器会自动安装以下工具：

| 工具 | 版本 | 用途 |
|------|------|------|
| Git | Latest | 版本控制、Git Bash |
| Python | 3.12+ | Claude Code 依赖 |
| Node.js | 20.x LTS | npm 包管理 |
| cc-switch | Latest | 镜像切换工具 |

## 技术支持

如遇到问题：

1. 查看详细日志：`.\install.ps1 -Verbose`
2. 尝试预览模式：`.\install.ps1 -WhatIf`
3. 检查常见问题

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2025-12-27 | 稳定版本发布，合并所有历史版本功能 |

## 参考资料

- [Scoop 包管理器](https://scoop.sh/)
- [Git for Windows](https://git-scm.com/download/win)
- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework)
- [Claude Code 官方文档](https://docs.claude.com/)

---

**Happy Coding! 🚀**
