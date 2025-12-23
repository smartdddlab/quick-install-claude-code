 1. Setting the SHELL environment variable - Try running: export SHELL=/bin/bash in your terminal before invoking this command
  2. Sharing the agent file contents - If you can paste the contents of _bmad/bmm/agents/quick-flow-solo-dev.md, I can activate it properly

  Alternatively, if you can resolve the shell issue, the agent will load and present its full menu of solo development workflow options.



2. 使用scoop 安装git 提示找不到git


scoop install msys2

3. 提示找不到git ，提示或设置CLAUDE_CODE_GIT_BASH_PATH ， 需要查找scoop which git  后设置git 为系统环境变量



5.● Bash(cat "_bmad/bmm/agents/pm.md")
  ⎿  Error: No suitable shell found. Claude CLI requires a Posix shell environment. Please ensure you have a valid shell installed and the SHELL environment
     variable set.
