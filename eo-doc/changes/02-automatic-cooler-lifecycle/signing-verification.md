# 固定本机签名及更新复验

- 已安装：`/Applications/TVVT 散热器.app`，版本 0.2.1 (3)。
- 同一证书签署不同内容：CDHash 改变，designated requirement 一致；临时签名对照的 requirement 不同。
- 固定身份：`4709437CBFE3A0270C03E8D4D7F3CB1EB7F7567B`（公开证书 SHA1，非密钥）。
- 从固定签名 0.2.0 更新至 0.2.1 后重新启动，无再次授权，实际自动重连并收到 ACK。
- `python3 scripts/setup-signing.py`：固定身份已就绪，无需重新创建。
- 不可用身份覆盖构建：退出码 1，编译前失败，无临时签名回退。
- 首次配置 OpenSSL 配置生成检查：成功生成含 Code Signing EKU、CA:FALSE 的证书，临时文件已清理。
- `./test.sh`：协议12组、温控/命令门、连接协调器三组 PASS。
- 安装包严格签名校验成功，登录项保存路径为上述 Applications 路径。实际注销/登录、睡眠恢复未执行。

```text
2026-10-31T09:53:49Z Controller started, restored mode=fullSpeed, rememberedDevice=true
2026-10-31T09:53:49Z Bluetooth initialized, authorization=3
2026-10-31T09:53:49Z CoreBluetooth state=5 authorization=3
2026-10-31T09:53:49Z 正在连接 T23SS…
2026-10-31T09:53:49Z 已连接，正在读取服务…
2026-10-31T09:53:50Z Notify 00010203-0405-0607-0809-0A0B0C0D2B10: true, OK
2026-10-31T09:53:50Z Valid A0: cold=18.0, hot=37.0, rpm=7995
2026-10-31T09:53:51Z TX B0 05 04 03 0A 0A 28 9A
2026-10-31T09:53:51Z 设备已确认请求（实际以设备报告为准）
```
