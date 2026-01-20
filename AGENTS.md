# Agent Instructions

## Test Commands

### Windows (PowerShell)
```powershell
# Syntax check
pwsh -Command "$null = Invoke-Expression (Get-Content -Path '.\install.ps1' -Raw)"

# Dry run (preview mode)
.\install.ps1 -WhatIf -Verbose

# Full test with WhatIf
./install.ps1 -WhatIf
```

### Linux/macOS (Bash)
```bash
# Syntax check
bash -n install.sh

# Dry run (preview mode)
DRY_RUN=1 bash install.sh
```

## Code Style Guidelines

### PowerShell (install.ps1)
- **Version**: Requires PowerShell 5.1+ (#requires -Version 5.1)
- **Parameter naming**: PascalCase (`[switch]$WhatIf`, `[string]$InstallDir`)
- **Function naming**: Verb-Noun pattern (`Install-Tools`, `Test-PowerShellEnvironment`)
- **Required functions**: Write-Header, Write-Step, Write-Success, Write-Warning, Write-Error, Test-PowerShellEnvironment, Select-InstallDrive, Test-NetworkAndSelectMirror, Test-And-InstallGitBash, Install-Tools, Set-EnvironmentVariables, Complete-Installation
- **Output**: Use `Write-Host` for info, `Write-Error` for errors
- **Strings**: Single quotes for static strings, double quotes for variable expansion
- **Error handling**: Check command existence before execution, use try-catch blocks
- **Encoding**: UTF-8 (lines 88-98: set chcp 65001, PSDefaultParameterValues)
- **Commenting**: Include SYNOPSIS/DESCRIPTION for function help
- **Remote execution**: [CmdletBinding()] must be first statement, read env vars for parameters

### Bash (install.sh)
- **Strict mode**: Always use `set -euo pipefail` at top of script
- **Function naming**: snake_case (`command_exists`, `detect_shell`, `install_node_lts`)
- **Required functions**: command_exists, detect_shell, check_existing_tools, check_dependencies, load_nvm, install_nvm, install_uv, install_node_lts, install_python, configure_npm_mirror, install_claude_code, install_superclaude, install_opencode, configure_shell, main, check_mirror_connectivity, install_or_update_brew, install_uv_macos (macOS)
- **Required variables**: SCRIPT_VERSION, NVM_VERSION, RED, GREEN, YELLOW, BLUE, NC, SKIP_SUPERCLAUDE, USE_CHINA_MIRROR, DRY_RUN, NVM_DIR
- **Log functions**: log_info, log_warn, log_error, log_step, log_debug (use colors: \033[0;31m, \033[0;32m, etc.)
- **Conditions**: Use `[[ ]]` for string comparisons, not `[ ]`
- **Variables**: Always use `${}` syntax when expanding: `echo "Installing ${SCRIPT_VERSION}..."`
- **Command checks**: Use `command -v` for existence checks: `command_exists npm && npm install`
- **Error output**: Redirect errors to stderr: `log_error "Failed: $msg" >&2`
- **Comments**: Use `#` for comments, include phase sections with `# ========================================`

### Error Handling
- **PowerShell**: Check `$LASTEXITCODE` after external commands, use try-catch for blocks
- **Bash**: Fail fast with `set -e`, check command existence before running, capture exit codes
- **Log errors**: Use specific log functions with color codes and proper stderr redirection
- **Validation**: Add pre-checks for required tools (Git, curl, Node.js, npm, uv)

### Commit Message Format
Follow Conventional Commits:
- `feat:` - 新功能
- `fix:` - Bug 修复
- `docs:` - 文档更新
- `style:` - 代码格式
- `refactor:` - 重构
- `perf:` - 性能优化
- `test:` - 测试相关
- `chore:` - 构建/工具

Include descriptive message, root cause analysis, and Co-Authored-By tag for Claude Code contributions.

### Testing Requirements
- All PRs must pass syntax checks
- Windows: PowerShell syntax + WhatIf mode must complete successfully
- Unix: Bash syntax + DRY_RUN=1 must complete successfully
- Verify all required functions/variables exist before merging
- No sensitive information (API keys, passwords) in code or logs
