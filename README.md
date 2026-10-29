# WXY REAPER Scripts

futurewy 的 REAPER Lua 脚本仓库。

## 安装

需要先安装 [ReaPack](https://reapack.com/)。仓库首次发布且自动索引工作流成功后，在 REAPER 中打开：

**Extensions → ReaPack → Import repositories…**

添加以下订阅地址：

```text
https://raw.githubusercontent.com/futurewy/WXY-REAPER-Scripts/main/index.xml
```

再打开 **Browse packages…** 搜索脚本、标记安装并 Apply。
日后通过 **Synchronize packages** 检查更新。首次发布前地址不可用。

## 脚本与依赖

| 脚本 | 版本 | 功能与限制 |
| --- | --- | --- |
| futurewy_BPM Calculator | 1.0 | 独立 BPM 计算器，拍数/时长换算与点击打拍；原生 gfx，无 FX、SWS 或 ReaImGui 依赖，不自动改变工程速度。 |
| futurewy_Toggle instrument windows | 1.0 | 切换选中轨道对应乐器的浮动窗口；查找本轨、父轨和发送目标，共享乐器去重，路由循环安全；无 SWS 依赖。 |
| hide offlinefx track | 1.1 | 选中且有 FX 的轨道恢复在线并显示；隐藏未选中且全部 FX 离线的轨道。 |
| Move arrangement | 2.5 | 从时间选区起点移动 Items、Markers、Regions；一小节固定按 4 个四分音符换算，不移动自动化或速度标记。 |
| ChordProgressionGenerator | 0.7 | 生成和试听经过和弦；需要 ReaImGui，打开和弦网页可选 SWS。试听需轨道监听和虚拟 MIDI 键盘输入。 |
| MIDI Notation Sanitizer | 2.2.1 | MIDI 记谱清理；会归一化力度、移除部分控制事件，请先备份。原生 gfx 界面，无扩展依赖。 |
| RevoiceSelectedChord | 4.0.1 | MIDI 编辑器内选中音符的和弦替换；原生 gfx 界面，无扩展依赖。 |
| URL Bookmarks Manager | 2.1 | 网址书签菜单；安全打开链接需要 SWS 的 CF_ShellExecute。不再使用拼接 shell 命令的回退方式。 |

和声生成器保留原有音乐算法：斜杠低音目前未强制应用到试听配器；部分变化和弦五音处理、无可行配音时的回退仍需音乐性复核。

## 安全试用

这批版本经过 Lua 5.3 语法检查及模拟 REAPER API 回归测试，**不等于已在真实 REAPER 中完成兼容性认证**。请在工程副本中逐项验证，参见 [人工测试清单](TESTING.md)。
未分发或改动两个含第三方版权署名的原始脚本。新增的 futurewy_BPM Calculator 和 futurewy_Toggle instrument windows 是按功能需求独立实现的新脚本，非原文件的改名版本。BPM 新版不再调用原来的同名 FX；两个新版不会自动替换原脚本快捷键或工具栏绑定，请安装后重新绑定。

## 发布更新

1. 修改本仓库中的对应脚本，而不是只修改原始工作文件夹。
2. 增加脚本顶部的 `@version`，并更新 `@changelog`。
3. 提交并推送到 `main`。
4. GitHub Actions 先运行测试和官方 `reapack-index --check`，再从 Git 历史生成索引并提交。
5. 确认 Actions 成功，并在 ReaPack 中同步测试。

版本索引指向提交中的脚本内容，保留 Git 历史，不要强制改写已发布历史或复用相同版本号。
默认 GitHub Actions 令牌提交索引不会再次触发 push 工作流。仓库必须允许工作流写入内容；受保护分支可能需要相应配置。

## 本地测试

使用 Python 3.12：

```text
python -m pip install lupa==2.8
python tools/run_tests.py
```

索引工具需要 Ruby，见 [官方说明](https://github.com/cfillion/reapack-index)：

```text
gem install reapack-index
reapack-index --check
reapack-index --no-commit
```

## 权利说明

公开可下载不自动等于授予任意再分发或商业使用许可。正式开源许可证由维护者另行选择；本仓库未擅自附加 MIT 等许可。
