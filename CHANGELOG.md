# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[v1.1.0]: https://github.com/smartdddlab/quick-install-claude-code/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/smartdddlab/quick-install-claude-code/releases/tag/v1.0.0
