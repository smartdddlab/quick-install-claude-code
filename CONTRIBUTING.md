# Contributing to quick-install-claude-code

感谢您对 Claude Code 多平台一键安装器的关注！欢迎提交 Pull Request 或 Report Bug。

## 快速开始

### Fork 仓库
点击 GitHub 页面右上角的 **Fork** 按钮，将仓库复制到您的账户。

### 克隆仓库
```bash
git clone https://github.com/YOUR_USERNAME/quick-install-claude-code.git
cd quick-install-claude-code
```

### 创建分支
```bash
git checkout -b fix/your-fix-description
```

## 提交类型指南

| 类型 | 描述 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat: 添加 xxx 平台支持` |
| `fix` | Bug 修复 | `fix: 修复 xxx 场景下的 xxx 问题` |
| `docs` | 文档更新 | `docs: 更新 README 安装说明` |
| `style` | 代码格式 | `style: 格式化 PowerShell 脚本` |
| `refactor` | 重构 | `refactor: 重构安装函数结构` |
| `perf` | 性能优化 | `perf: 优化镜像检测逻辑` |
| `test` | 测试相关 | `test: 添加 xxx 场景测试` |
| `chore` | 构建/工具 | `chore: 更新 GitHub Actions 版本` |

---

## Fix 修复指南

### 提交格式

```bash
fix: 修复 xxx 问题

- 问题描述
- 根本原因
- 解决方案
- 测试验证

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Your Name <your-email@example.com>
```

### Fix 要求

- [ ] **问题可复现**：提供复现步骤
- [ ] **根因分析**：说明问题产生的原因
- [ ] **最小修改**：只修改必要的代码
- [ ] **测试覆盖**：添加或更新测试用例
- [ ] **不引入回归**：确保不影响其他功能

### 常见 Fix 类型

#### 1. 脚本语法错误
```powershell
# 错误示例
if ($var -eq $null { ... }  # 缺少括号

# 正确示例
if ($var -eq $null) { ... }
```

#### 2. 变量未定义
```bash
# 错误示例
echo $var_undefined

# 正确示例
echo "${var_undefined:-}"
```

#### 3. 条件判断问题
```powershell
# 错误示例
if ($true -eq "True") { ... }  # 字符串比较

# 正确示例
if ($true -eq $true) { ... }
```

#### 4. 命令执行失败
```bash
# 错误示例
npm install -g claude

# 正确示例（检查命令是否存在）
command_exists npm && npm install -g claude
```

#### 5. 路径问题
```powershell
# 错误示例
$logPath = "install.log"

# 正确示例（使用绝对路径）
$logPath = Join-Path -Path $installDir -ChildPath "install.log"
```

### Fix 验证步骤

1. **语法检查**
   ```powershell
   # PowerShell
   pwsh -Command "$null = Invoke-Expression (Get-Content -Path 'install.ps1' -Raw)"

   # Bash
   bash -n install.sh
   ```

2. **Dry Run 测试**
   ```powershell
   # PowerShell
   .\install.ps1 -WhatIf -Verbose
   ```
   ```bash
   # Bash
   DRY_RUN=1 bash install.sh
   ```

3. **功能验证**
   - 在干净的测试环境中运行
   - 验证所有日志输出正确
   - 确认没有意外的文件变更

---

## Pull Request 要求

### 必须满足
- [ ] 代码通过现有测试（如果有）
- [ ] PowerShell 脚本通过 `install.ps1 -WhatIf` 测试
- [ ] Bash 脚本通过 `DRY_RUN=1 bash install.sh` 测试
- [ ] 提交信息符合规范
- [ ] 无敏感信息泄露（API Key、密码等）
- [ ] 分支名称符合规范（`fix/`、`feat/`、`docs/`）

### 建议包含
- [ ] 清晰的 PR 描述
- [ ] 修复前后的对比（截图/日志）
- [ ] 相关 Issue 链接
- [ ] 测试用例

### PR 描述模板

```markdown
## 修复内容

描述本次 PR 解决的问题或添加的功能。

## 修复类型
- [ ] Bug 修复
- [ ] 功能增强
- [ ] 文档更新
- [ ] 其他

## 测试验证

- [ ] 已运行语法检查
- [ ] 已运行 dry run 测试
- [ ] 已在目标平台测试

## 影响范围
- 影响平台：[Windows/Linux/macOS]
- 影响脚本：[install.ps1/install.sh]
- 是否破坏兼容性：[是/否]
```

---

## 脚本修改规范

### PowerShell 脚本 (`install.ps1`)

```powershell
# 1. 函数命名：Verb-Noun 模式
function Install-Tools { ... }

# 2. 参数命名：PascalCase
param(
    [switch]$WhatIf,
    [string]$InstallDrive,
    [switch]$SkipSuperClaude
)

# 3. 输出：使用 Write-Host/Write-Error
Write-Host "[INFO] 正在安装..."
Write-Error "安装失败：$ErrorMessage"

# 4. 字符串：单引号（静态）/ 双引号（需要展开）
$staticPath = 'C:\Program Files'
$dynamicPath = "$installDir\log.txt"
```

### Bash 脚本 (`install.sh`)

```bash
# 1. 严格模式
set -euo pipefail

# 2. 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 3. 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 4. 条件判断：使用 [[ ]]
if [[ "$USE_CHINA_MIRROR" == "1" ]]; then
    npm config set registry https://registry.npmmirror.com
fi

# 5. 变量：使用 ${}
echo "Installing ${SCRIPT_VERSION}..."
```

---

## 本地测试

### Windows (PowerShell)
```powershell
# 1. 语法检查
pwsh -Command "$null = Invoke-Expression (Get-Content -Path '.\install.ps1' -Raw)"

# 2. 干运行测试
.\install.ps1 -WhatIf -Verbose

# 3. 检查函数
$content = Get-Content -Path '.\install.ps1' -Raw
$content -match "function\s+Test-PowerShellEnvironment"
```

### Linux/macOS (Bash)
```bash
# 1. 语法检查
bash -n install.sh

# 2. 干运行测试
DRY_RUN=1 bash install.sh

# 3. 检查函数
grep -E "^command_exists|^detect_shell|^check_" install.sh
```

---

## GitHub Actions 测试

项目包含以下 CI 测试：

| 工作流 | 平台 | 说明 |
|--------|------|------|
| `test-windows.yml` | Windows | PowerShell 语法和功能测试 |
| `test-unix.yml` | Linux/macOS | Bash 语法和功能测试 |

提交 PR 前请确保 CI 通过。

---

## 建议的 PR 类型

| 类型 | 示例 |
|------|------|
| **Bug Fix** | `fix: 修复 GitHub Actions 中正则表达式转义问题` |
| 功能增强 | `feat: 添加 Linux/macOS 一键安装脚本` |
| 文档改进 | `docs: 完善 CONTRIBUTING.md` |
| 工作流改进 | `chore: 更新 GitHub Actions 版本` |

---

## 获取帮助

- 查看 [README](README.md) 了解项目结构
- 查看 [CLAUDE.md](CLAUDE.md) 了解技术细节
- 提交 [Issue](https://github.com/smartdddlab/quick-install-claude-code/issues) 讨论重大变更
