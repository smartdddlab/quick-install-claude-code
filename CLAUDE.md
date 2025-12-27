# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Claude Code 多平台一键安装器** - Scripts that automate installation and configuration of Claude Code development environment on Windows, Linux, and macOS.

## Commands

### Windows (PowerShell)
```powershell
# Test script with WhatIf mode (preview only, no actual installation)
.\install.ps1 -WhatIf -Verbose

# Install to specific drive
.\install.ps1 -InstallDrive D

# Skip SuperClaude installation
.\install.ps1 -SkipSuperClaude

# Remote installation from GitHub
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex

# Remote installation with parameters
$env:CLAUDE_INSTALL_DRIVE="D"; $env:CLAUDE_SKIP_SUPERCLAUDE="1"; irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex
```

### Linux/macOS (Bash)
```bash
# Standard installation (China mirror enabled by default)
curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# Preview mode (dry run)
DRY_RUN=1 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# Skip SuperClaude
CLAUDE_SKIP_SUPERCLAUDE=1 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# Use official npm registry
CLAUDE_USE_CHINA_MIRROR=0 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash
```

## Environment Variables

For remote installation scenarios, parameters must be passed via environment variables:

| Variable | Platform | Purpose | Example |
|----------|----------|---------|---------|
| `CLAUDE_INSTALL_DRIVE` | Windows | Installation drive | `$env:CLAUDE_INSTALL_DRIVE="D"` |
| `CLAUDE_SKIP_SUPERCLAUDE` | All | Skip SuperClaude | `CLAUDE_SKIP_SUPERCLAUDE=1` |
| `CLAUDE_INCLUDE_CC_SWITCH` | Windows | Include cc-switch | `$env:CLAUDE_INCLUDE_CC_SWITCH="1"` |
| `CLAUDE_USE_CHINA_MIRROR` | All | China mirror (1=enable, 0=disable) | `CLAUDE_USE_CHINA_MIRROR=0` |
| `DRY_RUN` | Linux/macOS | Preview mode | `DRY_RUN=1` |

## Execution Policy Handling

The script handles PowerShell execution policy automatically:

- **Restricted**: Script execution blocked → Manual intervention required
- **Undefined**: Script attempts to auto-set `RemoteSigned` policy → Auto-recovery
- **RemoteSigned** or **Bypass**: Runs normally

If auto-setting fails, the script provides solutions:
1. `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
2. `powershell -ExecutionPolicy Bypass -File install.ps1`

## Architecture

### install.ps1 (Windows)
The PowerShell script is organized into functional steps:
1. **Environment Detection** - PowerShell version >= 5.1, execution policy check
2. **Drive Selection** - Selects installation drive and sets log file path to InstallDir
3. **Tool Existence Detection** - Priority: scoop which > Get-Command > path detection
4. **Git Bash Detection/Installation** - Auto-install via Scoop if missing
5. **Network Testing** - GitHub accessibility check
6. **Scoop Installation** - Package manager setup
7. **Tool Installation** - Git, uv, Node.js LTS (skips if already installed)
8. **Environment Variables** - Sets SHELL, CLAUDE_CODE_GIT_BASH_PATH
9. **Claude Code Installation** - Installs via npm with Taobao mirror (China mode)
10. **SuperClaude Installation** - Installs via npm (`@bifrost_inc/superclaude`), then runs `superclaude install`
11. **Verification** - Confirms all tools are available

### install.sh (Linux/macOS)
The Bash script is organized into functional steps:
1. **Environment Detection** - Shell type (bash/zsh), dependency check (curl, git)
2. **Dependency Check** - Auto-installs missing base packages via system package manager
3. **Tool Existence Detection** - Checks nvm, uv, node, npm, claude availability
4. **nvm Installation** - Installs Node Version Manager v0.40.3
5. **uv Installation** - Installs uv Python package manager
6. **Node.js Installation** - Installs LTS version via nvm
7. **Python Installation** - Installs Python 3.12 via uv
8. **npm Mirror Configuration** - Sets registry to npmmirror.com (China mode)
9. **Claude Code Installation** - Installs via npm global
10. **SuperClaude Installation** - Installs via npm (`@bifrost_inc/superclaude`)
11. **Shell Configuration** - Writes nvm/uv settings to ~/.bashrc or ~/.zshrc

### Log File Location
- **Windows**: `<InstallDrive>:\smartddd-claude-tools\install-<timestamp>.log`
- **Linux/macOS**: No persistent log file; real-time console output only

## Key Features

### npm Taobao Mirror (China Mode)
When `-UseChinaMirror` is enabled (default), npm uses `https://registry.npmmirror.com` for faster downloads of Claude Code package.

### SuperClaude Version Verification
After SuperClaude installation, the script runs `superclaude --version` to verify the installation was successful.

### Dry Run Mode (Linux/macOS)
The `install.sh` script supports `DRY_RUN=1` mode that shows all commands without executing them.

## Dependencies Installed

| Tool | Windows | Linux/macOS |
|------|---------|-------------|
| Git | Scoop | System package manager |
| uv | Scoop | `astral.sh/uv/install.sh` |
| Node.js LTS | Scoop | nvm |
| Python | - | uv |
| Claude Code | npm (Taobao mirror) | npm (npmmirror.com) |
| SuperClaude | npm | npm |
| nvm | - | v0.40.3 |
| cc-switch | Scoop (optional) | - |

## Version

Uses Semantic Versioning (SemVer) - current version: **v1.0.0**
