# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.2.0] - 2025-01-21

### Added
- 镜像连通性自动检测与切换（npm/nvm 镜像）
- macOS Homebrew 自动安装与配置（使用中科大镜像）
- macOS 通过 Homebrew 安装 uv（避免 Rust 依赖）
- OpenCode 自动安装（Windows/Linux/macOS）
- install_or_update_brew 和 install_uv_macos 函数
- check_mirror_connectivity 和 install_opencode 函数

### Changed
- install_uv 函数对 macOS 优先使用 brew 路径
- configure_npm_mirror 函数增加镜像连通性检测
- install_nvm 函数增加镜像自动切换逻辑
- PowerShell 添加 Test-MirrorConnectivity 和 Get-NpmRegistry 函数

### Fixed
- 解决 macOS 上 uv 安装导致 Rust 依赖问题
- 修复国内镜像不可用时安装失败问题（自动切换官方源）
- 更新 Shell 配置支持 Homebrew 环境变量

### Removed
- 无

## [v1.1.0] - 2025-12-28

### Added
- Claude Code onboarding 配置，安装后自动跳过首次设置
- MIT License 许可证
- Shell 环境检测和自动配置

### Changed
- nvm 安装改用 Gitee 镜像源（国内网络加速）
- npm 镜像默认使用 npmmirror.com
- 统一使用 `--lts` 安装 Node.js

### Fixed
- Python PATH 问题，确保 SuperClaude 能检测到 Python
- uv 虚拟环境 pip 安装问题
- nvm 安装检测逻辑，清理不完整的安装目录
- npm 子进程 PATH 继承问题

### Removed
- GitHub Actions 中的跳过选项，进行完整真实验证

## [v1.0.0] - 2025-12-27

### Added
- 初始版本发布
- 支持 Ubuntu/Debian/Fedora/macOS
- nvm + Node.js LTS 安装
- uv + Python 3.12 安装
- Claude Code 安装
- SuperClaude 安装
- Shell 配置文件自动配置

[v1.2.0]: https://github.com/smartdddlab/quick-install-claude-code/compare/v1.1.0...v1.2.0
[v1.1.0]: https://github.com/smartdddlab/quick-install-claude-code/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/smartdddlab/quick-install-claude-code/releases/tag/v1.0.0
