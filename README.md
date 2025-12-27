# Claude Code Windows 一键安装器

在 Windows 环境下快速安装和配置 Claude Code 开发环境。

## 安装的工具

| 工具 | 安装方式 | 说明 |
|------|----------|------|
| Git | Scoop | 版本控制 |
| **uv** | Scoop | Python 包管理 |
| Node.js | Scoop | npm 包管理 |
| **Claude Code** | **npm 全局安装** | **核心工具** |
| SuperClaude | git + uv | 可选，增强框架 |

## 快速开始

```powershell
# 一键安装（推荐）
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex

# 指定安装到 D 盘
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex -InstallDrive D

# 跳过 SuperClaude
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex -SkipSuperClaude
```

## 安装顺序

1. Git → uv → Node.js (Scoop)
2. **Claude Code (npm install -g @anthropic-ai/claude)** ⭐ 重点
3. SuperClaude (git clone + uv pip install)

## 安装后

1. **重启终端**使环境变量生效
2. 运行 `claude` 启动 Claude Code
3. 验证安装：
```powershell
claude --version
uv --version
node --version
git --version
```

## 命令行参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-WhatIf` | 预览安装 | `.\install.ps1 -WhatIf` |
| `-Verbose` | 详细日志 | `.\install.ps1 -Verbose` |
| `-SkipSuperClaude` | 跳过 SuperClaude | `.\install.ps1 -SkipSuperClaude` |
| `-InstallDrive <盘符>` | 指定安装盘 | `.\install.ps1 -InstallDrive D` |

## 系统要求

- Windows 10/11
- PowerShell 5.1+
- 至少 5GB 磁盘空间
- 需要互联网连接

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
npm install -g @anthropic-ai/claude
```

## 参考

- [Scoop 包管理器](https://scoop.sh/)
- [uv 文档](https://docs.astral.sh/uv/)
- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework)
- [Claude Code 文档](https://docs.claude.com/)
