---
tags: [M2, SMC, 温度采集]
date: 2026-10-31
summary: 本机无需提权可读 SMC 浮点温度，但传感器部位和长期稳定性待验证。
---

# M2 温度采集可行性

## 命题与影响

命题：此 Mac 可在无需管理员权限的情况下读取摄氏温度信号。影响自动温控及菜单栏温度显示能否保持原生、无提权体验。

## 来源与结果（2026-10-31）

- 本机 sysctl / sw_vers：Apple M2，macOS 26.5.2。
- powermetrics --help：列出 thermal 压力通知，不提供直接摄氏温度采样的明确证据。
- ioreg：存在 AppleSMC 与温度传感器服务，存在性不等于可读性。
- 本机会话普通权限只读探针 tmp/eo/temperature-probe.c：IOServiceOpen 成功，SMC 结构 80 字节，读取 Tp09=50.68、Tp01=49.79、Tp05=47.71、Tg0f=40.84，类型 flt；Tp0T、TC0P 不存在。仅执行 key info / read bytes，没有写设备状态。
- 外部 Stats 源码获取未成功（路径 404 / GitHub API 403），没有据此产生传感器映射结论。

## 结论与边界

已验证：本机会话下无需提权可读取上述键的有限浮点值。置信度高，范围仅限本机单次探测。
推断：可为原生温控提供采集路径。置信度中。
未知：各键实际部位、CPU/GPU 覆盖、负载相关性、重启及睡眠后稳定性、其他机型兼容。实施前/实施中以有界采样验证；失败则回用户裁决替代信号或权限，不能把热压力换算为虚构摄氏温度。
若路径后续不可用，自动温控方案保留暂定，不宣告可交付。

本记录是决策依据，不是产品实现或制冷效果的交付证据。

## 实施期补证

后续成功通过 git 获取 exelban/stats，版本 4addbcd3f7057781aa63e813d91b7f2af7859c58。Modules/Sensors/values.swift 的 M2 表（410–426 行）将 Tp01/Tp05/Tp09/Tp0D 等映射到 CPU 性能核心、Tp1h 等映射到能效核心、Tg0f/Tg0j 映射到 GPU。参考链接：https://github.com/exelban/stats/blob/4addbcd3f7057781aa63e813d91b7f2af7859c58/Modules/Sensors/values.swift#L410 。仅查阅映射，没有拷贝第三方实现。

本项目独立 Swift 只读采集器连续六次、间隔两秒采样成功；有效键包括 Tp01/Tp05/Tp09/Tp0D/Tp0b/Tp0f/Tp0j/Tg0f。CPU 读数从编译后约 57℃回落至约 46℃，GPU 从约 45℃回落至约 42℃。这支持来源映射及动态变化，不证明外置散热器实际效果。读取路径只支持 M2 系列映射，其他机型显示不可用，不猜测传感器。
