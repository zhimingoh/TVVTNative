# 交付证据 — 菜单栏双模式与本机温控

## 入口与环境

当前 M2 Mac / macOS 26.5.2，T23SS；应用 `build/TVVT 散热器.app`，使用 `./build.sh` 构建、`./test.sh` 验证。开发分支 codex/automatic-cooling。

## 过程证据

- 协议12组原始向量和帧解析回归通过。
- 温控测试覆盖55/70℃边界、5℃回差、20秒持续回落、失效/过期/未来读数、指令去重和失败重试。
- 本机连续温度采样成功，T23SS 全速36W和自动18W/36W均收到成功ACK，详见 [实机记录](hardware-trace.md)。
- [全速面板](shots/batch-2-full-speed.png)、[自动面板](shots/batch-2-automatic.png)。这两张是最终授权提示增加前的实机截图，核心双模式与设备状态界面相同；最终权限提示见[最终版本授权状态](shots/batch-2-authorization.png)。
- `codesign --verify --deep --strict` 和 `git diff --check` 通过。构建显式最低目标 macOS14。

## 怎么验

顶部风扇入口打开两个模式按钮；选全速观察请求36W/10和设备确认，选自动观察温度分档、回差与报告档位。授权设置入口用于系统等待授权时打开蓝牙隐私设置。

未完成的证据：最终重新签名后系统TCC请求卡住，刷新权限要求用户解锁，未绕过；最终签名下设备恢复和完整失败UI矩阵保持未验证。没有宣告所有AC通过或归档。
