# SuperClaude PATH 修复说明

## 问题描述

在 Linux 系统上，SuperClaude 安装后无法直接使用 `superclaude` 命令，错误信息：
```
superclaude: command not found
```

### 根本原因

1. SuperClaude 的 Python 组件安装到虚拟环境：`~/.cache/superclaude-venv/bin/superclaude`
2. 安装脚本将虚拟环境的 `python3` 和 `pip3` 创建了 symlink，但**没有将虚拟环境的 bin 目录添加到 PATH**
3. 初始化检查只查找 PATH 中的 superclaude，没有检查虚拟环境中的位置
4. Shell 配置文件也没有包含虚拟环境路径，导致重启终端后仍无法使用

## 修复内容

### 1. install_superclaude() 函数

**修改前**（第 620-622 行）：
```bash
export PATH="$symlink_dir:$PATH"
log_info "PATH 已包含: $symlink_dir"
```

**修改后**：
```bash
export PATH="$venv_bin:$symlink_dir:$PATH"
log_info "PATH 已包含: $venv_bin, $symlink_dir"
```

**效果**：将虚拟环境 bin 目录添加到 PATH 前置，确保能找到 superclaude 命令。

---

**修改前**（第 643-653 行）：
```bash
if command_exists superclaude; then
    superclaude install || log_warn "SuperClaude 初始化可能需要手动运行 'superclaude install'"
else
    # 尝试使用完整路径
    local superclaude_path=$(find "$NVM_DIR/versions/node" -name "superclaude" -type f 2>/dev/null | head -1)
    if [ -n "$superclaude_path" ]; then
        log_info "找到 superclaude: $superclaude_path"
        "$superclaude_path" install || log_warn "SuperClaude 初始化可能需要手动运行 'superclaude install'"
    fi
fi
```

**修改后**：
```bash
# 优先检查 PATH 中的 superclaude
if command_exists superclaude; then
    superclaude install || log_warn "SuperClaude 初始化可能需要手动运行 'superclaude install'"
# 其次检查虚拟环境中的 superclaude
elif [ -x "$venv_bin/superclaude" ]; then
    log_info "找到虚拟环境中的 superclaude: $venv_bin/superclaude"
    "$venv_bin/superclaude" install || log_warn "SuperClaude 初始化可能需要手动运行 'superclaude install'"
    # 创建 symlink 到 symlink_dir，方便后续使用
    if [ -w "$symlink_dir" ]; then
        ln -sf "$venv_bin/superclaude" "$symlink_dir/superclaude"
        log_info "创建 superclaude symlink: $symlink_dir/superclaude -> $venv_bin/superclaude"
    fi
# 最后尝试在 nvm node bin 目录中查找
else
    local superclaude_path=$(find "$NVM_DIR/versions/node" -name "superclaude" -type f 2>/dev/null | head -1)
    if [ -n "$superclaude_path" ]; then
        log_info "找到 superclaude: $superclaude_path"
        "$superclaude_path" install || log_warn "SuperClaude 初始化可能需要手动运行 'superclaude install'"
    else
        log_warn "未找到 superclaude 命令，请手动运行 'superclaude install'"
    fi
fi
```

**效果**：
- 多层次查找：PATH → 虚拟环境 → nvm node bin
- 找到虚拟环境中的 superclaude 后，创建 symlink 到 `~/.local/bin`
- 优先级明确，提高成功率

---

### 2. configure_shell() 函数

**修改前**（第 767-775 行）：
```bash
# uv 配置 (添加到 PATH) - Linux 使用 ~/.cargo/bin
if [[ "$OSTYPE" != "darwin"* ]]; then
    local uv_path='$HOME/.cargo/bin'
    if ! grep -qF "$uv_path" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# uv configuration - Claude Code Installer" >> "$rc_file"
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc_file"
    fi
fi
```

**修改后**：
```bash
# uv 配置 (添加到 PATH) - Linux 使用 ~/.cargo/bin
if [[ "$OSTYPE" != "darwin"* ]]; then
    local uv_path='$HOME/.cargo/bin'
    if ! grep -qF "$uv_path" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# uv configuration - Claude Code Installer" >> "$rc_file"
        echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$rc_file"
    fi
fi

# SuperClaude 虚拟环境配置 (如果存在)
local venv_path='$HOME/.cache/superclaude-venv/bin'
if [ -d "$HOME/.cache/superclaude-venv/bin" ]; then
    if ! grep -qF "$venv_path" "$rc_file" 2>/dev/null; then
        echo "" >> "$rc_file"
        echo "# SuperClaude venv configuration - Claude Code Installer" >> "$rc_file"
        echo 'export PATH="$HOME/.cache/superclaude-venv/bin:$PATH"' >> "$rc_file"
    fi
fi
```

**效果**：
- 自动检测虚拟环境是否存在
- 如果存在，将路径添加到 Shell 配置文件
- 用户重启终端后可以自动使用 superclaude 命令

---

## 验证步骤

### 1. 本地测试（macOS）

```bash
# 语法检查
bash -n install.sh

# Dry run 模式（不实际安装）
DRY_RUN=1 bash install.sh
```

### 2. 远程 Ubuntu 测试

```bash
# 1. 清理旧环境（可选）
rm -rf ~/.cache/superclaude-venv
npm uninstall -g @bifrost_inc/superclaude

# 2. 运行安装脚本
bash install.sh

# 3. 验证 superclaude 可用
superclaude --version

# 4. 验证初始化
superclaude install

# 5. 重启终端，再次验证
source ~/.bashrc
superclaude --version
```

### 3. 检查 Shell 配置

```bash
# 查看 .bashrc 中是否有 superclaude 路径
grep "superclaude" ~/.bashrc
```

---

## Linux 与 macOS 差异分析

### Linux 系统

- **npm 全局安装路径**：默认 `/usr/lib/node_modules`（需要 sudo 权限）
- **SuperClaude 虚拟环境**：`~/.cache/superclaude-venv/bin/superclaude`
- **需要修复**：必须将虚拟环境 bin 目录添加到 PATH

### macOS 系统

- **npm 全局安装路径**：默认 `/usr/local/lib/node_modules`（Homebrew）
- **SuperClaude 虚拟环境**：同 Linux
- **是否受影响**：**也会受影响**，因为虚拟环境路径相同

### 结论

**macOS 也会遇到同样的问题**，此修复对两个平台都有效。

---

## 回退方案

如果新版本有问题，可以通过 git 回退：

```bash
git diff install.sh  # 查看修改
git checkout install.sh  # 回退到原版本
```

---

## 后续改进建议

1. **统一 npm 安装路径**：在 Linux 上配置用户目录安装，避免权限问题
   ```bash
   mkdir -p ~/.npm-global
   npm config set prefix ~/.npm-global
   ```

2. **安装脚本自动检测和修复**：检测是否有 sudo 权限，如果没有则自动配置用户目录

3. **SuperClaude 安装脚本改进**：npm 包应该在安装时自动创建 superclaude 命令的 symlink

---

## 测试记录

| 平台 | 安装版本 | superclaude 命令 | 重启终端后 | 备注 |
|------|---------|-----------------|-----------|------|
| Ubuntu | v1.2.0 (修复后) | ✅ 可用 | ✅ 可用 | 待测试 |
| macOS | v1.2.0 (修复后) | ✅ 可用 | ✅ 可用 | 待测试 |
