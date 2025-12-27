# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Claude Code Windows 一键安装器** - a PowerShell script that automates installation and configuration of Claude Code development environment on Windows.

## Commands

```powershell
# Test script with WhatIf mode (preview only, no actual installation)
.\install.ps1 -WhatIf -Verbose

# Install to specific drive
.\install.ps1 -InstallDrive D

# Skip SuperClaude installation
.\install.ps1 -SkipSuperClaude

# Skip China mirror (use default scoop repos)
.\install.ps1 -UseChinaMirror:$false

# Remote installation from GitHub
irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex

# Remote installation with parameters (use environment variables)
$env:CLAUDE_INSTALL_DRIVE="D"; $env:CLAUDE_SKIP_SUPERCLAUDE="1"; irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex

# Skip China mirror via environment variable
$env:CLAUDE_USE_CHINA_MIRROR="0"; irm https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.ps1 | iex
```

## Remote Installation Environment Variables

For `irm | iex` scenarios, parameters must be passed via environment variables:

| Environment Variable | Purpose | Example |
|---------------------|---------|---------|
| `CLAUDE_INSTALL_DRIVE` | Installation drive | `$env:CLAUDE_INSTALL_DRIVE="D"` |
| `CLAUDE_SKIP_SUPERCLAUDE` | Skip SuperClaude | `$env:CLAUDE_SKIP_SUPERCLAUDE="1"` |
| `CLAUDE_INCLUDE_CC_SWITCH` | Include cc-switch | `$env:CLAUDE_INCLUDE_CC_SWITCH="1"` |
| `CLAUDE_USE_CHINA_MIRROR` | Use China mirror (1=enable, 0=disable) | `$env:CLAUDE_USE_CHINA_MIRROR="0"` |

## Execution Policy Handling

The script handles PowerShell execution policy automatically:

- **Restricted**: Script execution blocked → Manual intervention required
- **Undefined**: Script attempts to auto-set `RemoteSigned` policy → Auto-recovery
- **RemoteSigned** or **Bypass**: Runs normally

If auto-setting fails, the script provides solutions:
1. `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
2. `powershell -ExecutionPolicy Bypass -File install.ps1`

## Architecture

The `install.ps1` script is organized into functional steps:
1. **Environment Detection** - PowerShell version >= 5.1, execution policy check
2. **Drive Selection** - Selects installation drive and sets log file path to InstallDir
3. **Tool Existence Detection** - Priority: scoop which > Get-Command > path detection
4. **Git Bash Detection/Installation** - Auto-install via Scoop if missing
5. **Network Testing** - GitHub accessibility check
6. **Scoop Installation** - Package manager setup
7. **Tool Installation** - Git, uv, Node.js LTS (skips if already installed)
8. **Environment Variables** - Sets SHELL, CLAUDE_CODE_GIT_BASH_PATH
9. **Claude Code Installation** - Installs via npm with Taobao mirror (China mode)
10. **SuperClaude Installation** - Installs via npm (`@bifrost_inc/superclaude`), then runs `superclaude install` for initialization
11. **Verification** - Confirms all tools are available

### Log File Location
Log file is saved to `<InstallDrive>:\smartddd-claude-tools\install-<timestamp>.log`

## Key Features

### npm Taobao Mirror (China Mode)
When `-UseChinaMirror` is enabled (default), npm uses `https://registry.npmmirror.com` for faster downloads of Claude Code package.

### SuperClaude Version Verification
After SuperClaude installation, the script runs `superclaude --version` to verify the installation was successful.

## Key Script Parameters

| Parameter | Purpose |
|-----------|---------|
| `-WhatIf` | Preview mode, no actual installation |
| `-Verbose` | Detailed logging output |
| `-InstallDrive` | Specify installation drive (D/E/F/C) |
| `-SkipSuperClaude` | Skip SuperClaude framework |
| `-UseChinaMirror` | Use China Gitee mirror (default: enabled) |
| `-IncludeCcSwitch` | Include cc-switch tool |

## GitHub Actions

The `.github/workflows/test-windows.yml` validates script execution on Windows runners:
- PowerShell syntax validation
- WhatIf mode execution test
- Function and parameter verification

## Dependencies Installed

- Git (with Git Bash)
- uv (Python package manager)
- Node.js 20.x LTS
- Claude Code CLI (via npm with Taobao mirror)
- SuperClaude Framework (optional, via npm `@bifrost_inc/superclaude`, with version verification)
- cc-switch (optional, via `-IncludeCcSwitch`)

## Version

Uses Semantic Versioning (SemVer) - current version: **v1.0.0**
