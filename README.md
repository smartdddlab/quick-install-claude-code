# Claude Code 多平台一键安装器

支持 Windows、Linux、macOS 快速安装和配置 Claude Code 开发环境。

## 快速开始

### Windows
```powershell
# 一键安装（推荐）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex
```

```PowerShell
# 其他安装示例
# 跳过 SuperClaude
$env:CLAUDE_SKIP_SUPERCLAUDE="1"; irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex

# 组合参数(设置D盘)
$env:CLAUDE_INSTALL_DRIVE="D"; $env:CLAUDE_SKIP_SUPERCLAUDE="1"; irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex
```

### Linux / macOS
```bash
# 一键安装（国内镜像，自动切换）
curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash
```
```Bash
# 跳过 SuperClaude
CLAUDE_SKIP_SUPERCLAUDE=1 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# 预览模式（不执行安装）
DRY_RUN=1 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash
```

**注意**: 安装完成后请重启终端或运行 `source ~/.bashrc` / `source ~/.zshrc`

## scoop 国内镜像源
[https://gitee.com/scoop-installer-mirrors](https://gitee.com/scoop-installer-mirrors)

## 安装顺序

### Windows
1. Git → uv → Node.js (Scoop)
2. **Claude Code (npm)** ⭐
3. SuperClaude
4. **OpenCode** 🆕

### Linux
1. nvm → Node.js LTS
2. uv → Python 3.12
3. **Claude Code (npm)** ⭐
4. SuperClaude
5. **OpenCode** 🆕

### macOS
1. Homebrew → uv (避免 Rust 依赖) 🆕
2. nvm → Node.js LTS
3. Python 3.12
4. **Claude Code (npm)** ⭐
5. SuperClaude
6. **OpenCode** 🆕

## 安装后

1. **重启终端**使环境变量生效
2. 运行 `claude` 启动 Claude Code
3. 验证安装：
```bash
claude --version
uv --version
node --version
opencode --version  # 新增
```

## 命令行参数

### Windows (install.ps1)
| 参数 | 说明 | 示例 |
|------|------|------|
| `-WhatIf` | 预览安装 | `.\install.ps1 -WhatIf` |
| `-SkipSuperClaude` | 跳过 SuperClaude | `.\install.ps1 -SkipSuperClaude` |
| `-InstallDrive <盘符>` | 指定安装盘 | `.\install.ps1 -InstallDrive D` |

### Linux/macOS (install.sh)
| 环境变量 | 说明 | 示例 |
|----------|------|------|
| `DRY_RUN=1` | 预览模式 | `DRY_RUN=1 bash install.sh` |
| `CLAUDE_SKIP_SUPERCLAUDE=1` | 跳过 SuperClaude | `CLAUDE_SKIP_SUPERCLAUDE=1 bash install.sh` |
| `CLAUDE_USE_CHINA_MIRROR=0` | 使用官方镜像 | `CLAUDE_USE_CHINA_MIRROR=0 bash install.sh` |

## 系统要求

- **Windows**: 10/11, PowerShell 5.1+
- **Linux/macOS**: Bash shell, curl
- 至少 5GB 磁盘空间
- 需要互联网连接

## 新增功能 ✨

### 镜像自动切换 🆕
- 自动检测国内镜像连通性
- 不可用时自动切换到官方源
- 支持 VPN 环境，智能选择最佳源

### macOS Homebrew 支持 🆕
- 自动安装 Homebrew（使用中科大镜像）
- 通过 Homebrew 安装 uv（避免 Rust 依赖）
- 兼容 Apple Silicon 和 Intel 芯片

### OpenCode 安装 🆕
- 自动安装 OpenCode 工具
- 支持 Windows/Linux/macOS 三平台
- 使用 npm 全局安装

## 故障排除

### 执行策略限制
```powershell
# 临时绕过
powershell -ExecutionPolicy Bypass -File install.ps1

# 永久修改
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 验证 Claude Code 安装
```powershell
claude --version
```

如果未安装，手动安装：
```powershell
npm install -g @anthropic-ai/claude-code
```

### macOS 镜像问题
```bash
# 如果 Homebrew 安装失败，手动切换镜像
export HOMEBREW_BREW_GIT_REMOTE="https://github.com/Homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://github.com/Homebrew/homebrew-core.git"
```

## 参考

- [Scoop 包管理器](https://scoop.sh/)
- [uv 文档](https://docs.astral.sh/uv/)
- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework)
- [Claude Code 文档](https://docs.claude.com/)
- [OpenCode](https://github.com/anomalyco/opencode)

