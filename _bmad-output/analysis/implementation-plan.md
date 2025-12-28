---
title: Ubuntu Claude Code 一键安装脚本实现计划
version: v1.0.0
created: 2025-12-28
based_on: brainstorming-session-2025-12-27.md
status: draft
---

# Ubuntu Claude Code 一键安装脚本实现计划

## 项目概述

根据头脑风暴成果，创建 `install.sh` 脚本实现与 `install.ps1` 等效的功能。

### 目标
- 跨平台 Bash 脚本 (Linux/macOS)
- 支持国内镜像加速
- 支持本地和容器场景

---

## 实现步骤

### Phase 1: 基础架构

#### 1.1 脚本头部和错误处理
```bash
#!/bin/bash
set -euo pipefail  # 错误即停、变量未定义警告、管道错误捕获

# 脚本元信息
SCRIPT_VERSION="v1.0.0"
NVM_VERSION="v0.40.3"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
```

#### 1.2 环境变量解析
```bash
# 默认配置
SKIP_SUPERCLAUDE="${CLAUDE_SKIP_SUPERCLAUDE:-0}"
USE_CHINA_MIRROR="${CLAUDE_USE_CHINA_MIRROR:-1}"
DRY_RUN="${DRY_RUN:-0}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
```

#### 1.3 日志函数
```bash
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "[STEP] $1"; }
```

---

### Phase 2: 环境检测

#### 2.1 Shell 类型检测
```bash
detect_shell() {
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "zsh"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "bash"
    else
        echo "bash"  # 默认
    fi
}
```

#### 2.2 工具存在性检测
```bash
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_existing_tools() {
    log_step "检查已安装的工具..."
    local missing=()

    command_exists nvm || missing+=("nvm")
    command_exists uv || missing+=("uv")
    command_exists node || missing+=("node")
    command_exists npm || missing+=("npm")
    command_exists claude || missing+=("claude")

    if [ ${#missing[@]} -eq 0 ]; then
        log_info "所有工具已安装"
    else
        log_warn "需要安装: ${missing[*]}"
    fi
}
```

---

### Phase 3: 安装函数

#### 3.1 安装 nvm
```bash
install_nvm() {
    if [ -d "$NVM_DIR" ]; then
        log_info "nvm 已安装"
        return 0
    fi

    log_step "安装 nvm $NVM_VERSION..."
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY RUN] curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"
        return 0
    fi

    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash

    # 加载 nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    log_info "nvm 安装完成"
}
```

#### 3.2 安装 uv
```bash
install_uv() {
    if command_exists uv; then
        log_info "uv 已安装: $(uv --version)"
        return 0
    fi

    log_step "安装 uv..."
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY RUN] curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 0
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh

    # 添加到 PATH (根据安装位置)
    export PATH="$HOME/.cargo/bin:$PATH"

    log_info "uv 安装完成: $(uv --version)"
}
```

#### 3.3 安装 Node.js LTS
```bash
install_node_lts() {
    log_step "安装 Node.js LTS..."
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY RUN] nvm install --lts && nvm use --lts"
        return 0
    fi

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    nvm install --lts
    nvm use --lts

    log_info "Node.js 安装完成: $(node --version)"
}
```

#### 3.4 安装 Python
```bash
install_python() {
    log_step "安装 Python..."
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY RUN] uv python install 3.12"
        return 0
    fi

    uv python install 3.12
    log_info "Python 安装完成: $(python --version)"
}
```

#### 3.5 配置 npm 镜像
```bash
configure_npm_mirror() {
    if [ "$USE_CHINA_MIRROR" != "1" ]; then
        log_info "使用官方 npm 镜像"
        return 0
    fi

    log_step "配置 npm 国内镜像..."
    npm config set registry https://registry.npmmirror.com
    log_info "npm 镜像已配置为 registry.npmmirror.com"
}
```

#### 3.6 安装 Claude Code
```bash
install_claude_code() {
    if command_exists claude; then
        log_info "Claude Code 已安装: $(claude --version)"
        return 0
    fi

    log_step "安装 Claude Code..."
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY RUN] npm install -g @anthropic-ai/claude"
        return 0
    fi

    npm install -g @anthropic-ai/claude
    log_info "Claude Code 安装完成"
}
```

#### 3.7 安装 SuperClaude
```bash
install_superclaude() {
    if [ "$SKIP_SUPERCLAUDE" == "1" ]; then
        log_warn "跳过 SuperClaude 安装"
        return 0
    fi

    if command_exists superclaude; then
        log_info "SuperClaude 已安装: $(superclaude --version)"
        return 0
    fi

    log_step "安装 SuperClaude..."
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY RUN] npm install -g @bifrost_inc/superclaude && superclaude install"
        return 0
    fi

    npm install -g @bifrost_inc/superclaude
    superclaude install

    log_info "SuperClaude 安装完成"
}
```

---

### Phase 4: 环境配置

#### 4.1 写入 Shell 配置文件
```bash
configure_shell() {
    local shell_type
    shell_type=$(detect_shell)

    local rc_file
    if [ "$shell_type" == "zsh" ]; then
        rc_file="$HOME/.zshrc"
    else
        rc_file="$HOME/.bashrc"
    fi

    log_step "配置 $shell_type 环境..."

    # 添加 nvm 配置
    if ! grep -q "NVM_DIR" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# nvm configuration" >> "$rc_file"
        echo "export NVM_DIR=\"\$HOME/.nvm\"" >> "$rc_file"
        echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"" >> "$rc_file"
    fi

    # 添加 uv 配置
    if ! grep -q "uv" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# uv configuration" >> "$rc_file"
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc_file"
    fi

    log_info "环境配置已写入 $rc_file"
}
```

---

### Phase 5: 主流程

```bash
main() {
    echo "=============================================="
    echo "  Claude Code Linux 一键安装器 $SCRIPT_VERSION"
    echo "=============================================="
    echo ""

    # 1. 环境检测
    check_existing_tools

    # 2. 安装 nvm
    install_nvm

    # 3. 安装 uv
    install_uv

    # 4. 安装 Node.js
    install_node_lts

    # 5. 安装 Python
    install_python

    # 6. 配置 npm 镜像
    configure_npm_mirror

    # 7. 安装 Claude Code
    install_claude_code

    # 8. 安装 SuperClaude (可选)
    install_superclaude

    # 9. 环境配置
    configure_shell

    echo ""
    echo "=============================================="
    echo "  安装完成!"
    echo "=============================================="
    echo "请重启终端或运行: source ~/.bashrc"
    echo ""
}

main "$@"
```

---

## 文件结构

```
quick-install-claude-code/
├── install.ps1          # Windows 版本 (已存在)
├── install.sh           # Linux/macOS 版本 (待创建)
└── README.md            # 文档
```

---

## 测试计划

### 本地测试
```bash
# 测试 WhatIf 模式
DRY_RUN=1 bash install.sh

# 实际安装测试 (在测试容器中)
docker run -it ubuntu:22.04 bash
# 然后运行安装脚本
```

### CI/CD 测试
```yaml
# GitHub Actions
- name: Test install.sh
  run: |
    curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash -s -- --dry-run
```

---

## 使用示例

```bash
# 标准安装 (国内镜像)
curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# 跳过 SuperClaude
CLAUDE_SKIP_SUPERCLAUDE=1 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# 使用官方镜像
CLAUDE_USE_CHINA_MIRROR=0 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# 预览模式
DRY_RUN=1 curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash

# Dockerfile 中使用
RUN curl -LsSf https://raw.githubusercontent.com/smartdddlab/quick-install-claude-code/main/install.sh | bash
```

---

## 后续任务

| 优先级 | 任务 | 状态 |
|--------|------|------|
| P0 | 创建 install.sh 基础框架 | 待处理 |
| P0 | 实现 nvm 安装函数 | 待处理 |
| P0 | 实现 uv 安装函数 | 待处理 |
| P0 | 实现 Node.js/Python 安装 | 待处理 |
| P0 | 实现 Claude/SuperClaude 安装 | 待处理 |
| P1 | 添加环境变量解析 | 待处理 |
| P1 | 添加镜像配置逻辑 | 待处理 |
| P1 | 添加 .bashrc/.zshrc 写入 | 待处理 |
| P2 | 本地测试验证 | 待处理 |
| P2 | Dockerfile 场景测试 | 待处理 |

---

## 风险与缓解

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| curl \| bash 安全性 | 低 | 高 | 脚本可审查，提供 SHA256 校验 |
| 网络下载失败 | 中 | 高 | 添加重试机制 |
| 脚本源被篡改 | 低 | 高 | 使用 HTTPS，提供校验 |
