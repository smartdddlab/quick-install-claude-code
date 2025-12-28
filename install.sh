#!/bin/bash
set -euo pipefail  # 错误即停、变量未定义警告、管道错误捕获

# ================================================
# Claude Code Linux/macOS 一键安装器
# ================================================
# Version: v1.0.0
# Based on: implementation-plan.md

# 脚本元信息
SCRIPT_VERSION="v1.0.0"
NVM_VERSION="v0.40.3"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
SKIP_SUPERCLAUDE="${CLAUDE_SKIP_SUPERCLAUDE:-0}"
SKIP_CLAUDE_CODE="${SKIP_CLAUDE_CODE:-0}"
USE_CHINA_MIRROR="${CLAUDE_USE_CHINA_MIRROR:-1}"
DRY_RUN="${DRY_RUN:-0}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# 确保 PATH 包含 uv 安装的工具（Python 等）
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_debug() { [ "$DRY_RUN" == "1" ] && echo -e "${GREEN}[DEBUG]${NC} $1"; }

# ================================================
# Phase 2: 环境检测
# ================================================

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检测 Shell 类型
detect_shell() {
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo "zsh"
    elif [[ "$SHELL" == *"bash"* ]]; then
        echo "bash"
    else
        echo "bash"  # 默认
    fi
}

# 检查已安装的工具
check_existing_tools() {
    log_step "检查已安装的工具..."
    local missing=()
    local found=()

    if command_exists nvm; then
        found+=("nvm")
    else
        missing+=("nvm")
    fi

    if command_exists uv; then
        found+=("uv: $(uv --version | cut -d' ' -f1)")
    else
        missing+=("uv")
    fi

    if command_exists node; then
        found+=("node: $(node --version)")
    else
        missing+=("node")
    fi

    if command_exists npm; then
        found+=("npm: $(npm --version)")
    else
        missing+=("npm")
    fi

    if command_exists claude; then
        found+=("claude: $(claude --version 2>/dev/null | head -1 || echo 'installed')")
    else
        missing+=("claude")
    fi

    if [ ${#found[@]} -gt 0 ]; then
        log_info "已安装: ${found[*]}"
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        log_info "所有工具已安装，跳过安装步骤"
        return 1  # 返回 1 表示无需安装
    else
        log_warn "需要安装: ${missing[*]}"
        return 0  # 返回 0 表示需要安装
    fi
}

# 检查并安装必要的依赖
check_dependencies() {
    log_step "检查系统依赖..."

    local missing_deps=()

    if ! command_exists curl; then
        missing_deps+=("curl")
    fi

    if ! command_exists git; then
        missing_deps+=("git")
    fi

    # 检查 CA 证书文件（不同系统位置不同）
    local ca_cert_found=false
    for cert_file in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-certificates.pem /etc/pki/tls/cacert.pem; do
        if [ -f "$cert_file" ]; then
            ca_cert_found=true
            break
        fi
    done

    # macOS 系统通常不需要单独安装 ca-certificates
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ca_cert_found=true
    fi

    if [ "$ca_cert_found" = false ]; then
        # Debian/Ubuntu/Fedora 等
        missing_deps+=("ca-certificates")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "缺少基础依赖: ${missing_deps[*]}"

        # 检测包管理器并安装
        if command_exists apt-get; then
            log_step "安装基础依赖 (apt)..."
            if [ "$DRY_RUN" != "1" ]; then
                sudo apt-get update
                sudo apt-get install -y "${missing_deps[@]}"
            fi
        elif command_exists yum; then
            log_step "安装基础依赖 (yum)..."
            if [ "$DRY_RUN" != "1" ]; then
                sudo yum install -y "${missing_deps[@]}"
            fi
        elif command_exists dnf; then
            log_step "安装基础依赖 (dnf)..."
            if [ "$DRY_RUN" != "1" ]; then
                sudo dnf install -y "${missing_deps[@]}"
            fi
        elif command_exists pacman; then
            log_step "安装基础依赖 (pacman)..."
            if [ "$DRY_RUN" != "1" ]; then
                sudo pacman -Sy --noconfirm "${missing_deps[@]}"
            fi
        elif command_exists apk; then
            log_step "安装基础依赖 (apk)..."
            if [ "$DRY_RUN" != "1" ]; then
                apk add --no-cache "${missing_deps[@]}"
            fi
        else
            log_error "无法自动安装依赖，请手动安装: ${missing_deps[*]}"
            return 1
        fi
    else
        log_info "基础依赖已满足"
    fi
}

# ================================================
# Phase 3: 安装函数
# ================================================

# 加载 nvm
load_nvm() {
    if [ -z "${NVM_DIR:-}" ]; then
        NVM_DIR="$HOME/.nvm"
    fi

    if [ -s "$NVM_DIR/nvm.sh" ]; then
        export NVM_DIR
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh" nvm
        # 验证 nvm 命令是否可用
        if command -v nvm >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 安装 nvm
install_nvm() {
    log_step "安装 nvm $NVM_VERSION..."
    if [ "$DRY_RUN" == "1" ]; then
        log_debug "git clone https://gitee.com/mirrors/nvm.git \$NVM_DIR"
        return 0
    fi

    # 确保 NVM_DIR 变量设置正确
    export NVM_DIR="$HOME/.nvm"

    # 检查 nvm 是否已正确安装（检查 nvm.sh 文件）
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        log_info "nvm 已安装于 $NVM_DIR"
    else
        # nvm.sh 不存在，需要安装
        log_info "正在安装 nvm..."

        # 清理可能的不完整安装
        rm -rf "$NVM_DIR" 2>/dev/null || true

        # 首先使用 Gitee 镜像（国内网络加速）
        log_info "从 Gitee 镜像下载 nvm..."
        if git clone --depth 1 https://gitee.com/mirrors/nvm.git "$NVM_DIR"; then
            log_info "nvm 下载完成，版本: $(git -C "$NVM_DIR" describe --tags 2>/dev/null || echo 'unknown')"
        else
            # 如果 Gitee 失败，使用 nvm 官方的 install.sh 脚本
            log_warn "Gitee 下载失败，尝试使用官方源..."
            log_info "从 GitHub 下载 nvm..."
            if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash; then
                log_info "nvm 安装完成"
            else
                log_error "nvm 安装失败，请检查网络连接或手动安装"
                return 1
            fi
        fi
    fi

    # 加载 nvm (必须在全局 scope 加载，因为 nvm 是通过函数定义的)
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh" nvm
    fi

    # 验证 nvm 可用
    if command_exists nvm; then
        log_info "nvm 加载成功: $(nvm --version)"
    else
        log_warn "nvm 加载验证失败，Node.js 安装可能受影响"
    fi
}

# 安装 uv
install_uv() {
    if command_exists uv; then
        log_info "uv 已安装: $(uv --version)"
        return 0
    fi

    log_step "安装 uv..."
    if [ "$DRY_RUN" == "1" ]; then
        log_debug "curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 0
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh

    # uv 安装脚本可能安装到 ~/.cargo/bin 或 ~/.local/bin
    # 确保 PATH 包含两者
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

    # 验证安装
    if command_exists uv; then
        log_info "uv 安装完成: $(uv --version)"
    else
        log_warn "uv 安装后验证失败，请手动确认 PATH 设置"
    fi
}

# 安装 Node.js LTS
install_node_lts() {
    log_step "安装 Node.js LTS..."

    # 加载 nvm
    if ! load_nvm; then
        log_error "nvm 未安装或加载失败，无法安装 Node.js"
        return 1
    fi

    if [ "$DRY_RUN" == "1" ]; then
        log_debug "nvm install --lts"
        return 0
    fi

    # 检查 Node.js 是否已安装
    if command_exists node; then
        log_info "Node.js 已安装: $(node --version)"
        return 0
    fi

    # 记录已存在的版本
    local existing_versions=""
    if [ -d "$NVM_DIR/versions/node" ]; then
        existing_versions=$(ls -1 "$NVM_DIR/versions/node" 2>/dev/null || echo "")
    fi

    # nvm install --lts 可能在严格模式下失败 (PROVIDED_VERSION unbound)
    # 使用子 shell 执行，避免影响主脚本
    log_info "安装 Node.js LTS..."
    (
        set +euo pipefail
        export NVM_DIR="$HOME/.nvm"
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh" nvm
        nvm install --lts 2>&1 | grep -v "unbound variable" || true
    )

    # 查找新安装的版本
    local new_version=""
    if [ -d "$NVM_DIR/versions/node" ]; then
        for v in $(ls -1 "$NVM_DIR/versions/node" 2>/dev/null); do
            if ! echo "$existing_versions" | grep -q "$v"; then
                new_version="$v"
                break
            fi
        done
    fi

    # 如果没找到新版本，尝试查找任何已安装的版本
    if [ -z "$new_version" ] && [ -d "$NVM_DIR/versions/node" ]; then
        new_version=$(ls -1 "$NVM_DIR/versions/node" | tail -1)
    fi

    # 手动设置 PATH
    if [ -n "$new_version" ] && [ -d "$NVM_DIR/versions/node/$new_version/bin" ]; then
        export PATH="$NVM_DIR/versions/node/$new_version/bin:$PATH"
        log_info "Node.js 安装完成: v$new_version (npm 已包含)"
    elif command_exists node; then
        log_info "Node.js 安装完成: $(node --version)"
    else
        log_warn "Node.js 安装验证失败"
        return 1
    fi

    return 0
}

# 安装 Python
install_python() {
    log_step "安装 Python 3.12..."

    if ! command_exists uv; then
        log_error "uv 未安装，无法安装 Python"
        return 1
    fi

    if [ "$DRY_RUN" == "1" ]; then
        log_debug "uv python install 3.12"
        return 0
    fi

    # 检查是否已安装 Python 3.12
    if uv python list | grep -q "3.12"; then
        log_info "Python 3.12 已安装"
    else
        uv python install 3.12
    fi

    # 验证 Python 安装（python3 或 python）
    local python_version
    python_version=$(python3 --version 2>/dev/null || python --version 2>/dev/null || echo "unknown")
    log_info "Python 安装完成: $python_version"
}

# 配置 npm 镜像
configure_npm_mirror() {
    if [ "$USE_CHINA_MIRROR" != "1" ]; then
        log_info "使用官方 npm 镜像 (registry.npmjs.org)"
        npm config set registry https://registry.npmjs.org
        return 0
    fi

    log_step "配置 npm 国内镜像..."
    npm config set registry https://registry.npmmirror.com
    log_info "npm 镜像已配置为 registry.npmmirror.com"
}

# 安装 Claude Code
install_claude_code() {
    # 检查是否跳过 Claude Code 安装
    if [ "$SKIP_CLAUDE_CODE" == "1" ]; then
        log_warn "跳过 Claude Code 安装（SKIP_CLAUDE_CODE=1）"
        return 0
    fi

    if command_exists claude; then
        local version
        version=$(claude --version 2>/dev/null | head -1 || echo "installed")
        log_info "Claude Code 已安装: $version"
        return 0
    fi

    log_step "安装 Claude Code..."
    if [ "$DRY_RUN" == "1" ]; then
        log_debug "npm install -g @anthropic-ai/claude-code"
        return 0
    fi

    npm install -g @anthropic-ai/claude-code

    # 验证安装
    if command_exists claude; then
        log_info "Claude Code 安装完成: $(claude --version)"
    else
        log_error "Claude Code 安装验证失败"
        return 1
    fi
}

# 安装 SuperClaude
install_superclaude() {
    if [ "$SKIP_SUPERCLAUDE" == "1" ]; then
        log_warn "跳过 SuperClaude 安装"
        return 0
    fi

    if command_exists superclaude; then
        local version
        version=$(superclaude --version 2>/dev/null | head -1 || echo "installed")
        log_info "SuperClaude 已安装: $version"
        return 0
    fi

    log_step "安装 SuperClaude..."
    if [ "$DRY_RUN" == "1" ]; then
        log_debug "npm install -g @bifrost_inc/superclaude && superclaude install"
        return 0
    fi

    # 确保 uv 可用
    if ! command_exists uv; then
        log_error "uv 未安装，无法安装 SuperClaude"
        return 1
    fi

    # 创建虚拟环境并安装 pip
    local venv_dir="$HOME/.cache/superclaude-venv"
    if [ ! -d "$venv_dir" ]; then
        uv venv "$venv_dir" --python python3.12
    fi
    # 确保 pip 可用（使用 uv pip 安装到虚拟环境）
    uv pip install pip --python "$venv_dir/bin/python" 2>/dev/null || true

    # 在虚拟环境 bin 目录中创建 symlink 到系统 PATH 目录
    # 这样 command -v python3 就能找到虚拟环境中的 Python
    local venv_bin="$venv_dir/bin"
    local symlink_dir="$HOME/.local/bin"

    # 确保 symlink 目录存在
    mkdir -p "$symlink_dir"

    # 创建 python3 和 pip3 的 symlink（如果不存在）
    if [ ! -e "$symlink_dir/python3" ]; then
        ln -sf "$venv_bin/python3" "$symlink_dir/python3"
        log_info "创建 python3 symlink: $symlink_dir/python3 -> $venv_bin/python3"
    fi

    if [ ! -e "$symlink_dir/pip3" ]; then
        ln -sf "$venv_bin/pip3" "$symlink_dir/pip3"
        log_info "创建 pip3 symlink: $symlink_dir/pip3 -> $venv_bin/pip3"
    fi

    # 将 symlink 目录添加到 PATH 前置
    export PATH="$symlink_dir:$PATH"
    log_info "PATH 已包含: $symlink_dir"

    # 现在 npm install 时，SuperClaude 的 install.js 应该能找到正确的 python3 和 pip3
    npm install -g @bifrost_inc/superclaude

    # 初始化 SuperClaude
    if command_exists superclaude; then
        superclaude install || log_warn "SuperClaude 初始化可能需要手动运行 'superclaude install'"
    fi

    # 验证安装
    if command_exists superclaude; then
        log_info "SuperClaude 安装完成: $(superclaude --version)"
    else
        log_warn "SuperClaude 安装验证失败，请手动运行 'superclaude install'"
    fi
}

# ================================================
# Phase 4: 环境配置
# ================================================

# 写入 Shell 配置文件
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

    # nvm 配置
    if ! grep -q "NVM_DIR" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# nvm configuration - Claude Code Installer" >> "$rc_file"
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$rc_file"
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$rc_file"
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> "$rc_file"
    fi

    # uv 配置 (添加到 PATH)
    local uv_path='$HOME/.cargo/bin'
    if ! grep -qF "$uv_path" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# uv configuration - Claude Code Installer" >> "$rc_file"
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc_file"
    fi

    log_info "环境配置已写入 $rc_file"
}

# ================================================
# Phase 5: 主流程
# ================================================

main() {
    echo "=============================================="
    echo "  Claude Code Linux/macOS 一键安装器"
    echo "  Version: $SCRIPT_VERSION"
    echo "=============================================="
    echo ""

    # Dry Run 模式提示
    if [ "$DRY_RUN" == "1" ]; then
        echo -e "${YELLOW}[DRY RUN MODE]${NC} - 仅预览，不执行实际安装"
        echo ""
    fi

    # 1. 检查系统依赖
    if ! check_dependencies; then
        log_error "依赖检查失败"
        exit 1
    fi

    # 2. 检查已安装的工具
    if ! check_existing_tools; then
        log_info "所有工具已就绪，跳过安装"
        echo ""
        echo "=============================================="
        echo "  安装检查完成!"
        echo "=============================================="
        echo "请重启终端或运行: source ~/.bashrc"
        echo ""
        exit 0
    fi

    # 3. 安装 nvm
    install_nvm

    # 4. 安装 uv
    install_uv

    # 5. 安装 Node.js
    install_node_lts

    # 6. 安装 Python
    install_python

    # 7. 配置 npm 镜像
    configure_npm_mirror

    # 8. 安装 Claude Code
    install_claude_code

    # 9. 安装 SuperClaude (可选)
    install_superclaude

    # 10. 环境配置
    configure_shell

    echo ""
    echo "=============================================="
    echo "  安装完成!"
    echo "=============================================="
    echo ""
    echo "请重启终端或运行以下命令加载环境:"
    echo "  source ~/.bashrc  # bash"
    echo "  source ~/.zshrc   # zsh"
    echo ""
    echo "然后运行 'claude' 开始使用!"
    echo ""
}

# 启动主流程
main "$@"
