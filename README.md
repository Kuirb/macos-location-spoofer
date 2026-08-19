# macOS Location Spoofer for Shadowrocket

**中文** · [English](README.en.md)

通过 Shadowrocket 在 macOS 上定向改写 Apple Wi‑Fi/基站定位响应，无需 macOS App、Xcode 或关闭 SIP。目标坐标保存在本地纯文本配置中，修改后即可重新生成 Shadowrocket 模块。这是研究与测试用途的概念验证，不是系统级 GPS 驱动，也不保证影响所有 App。

> [!WARNING]
> HTTPS 解密需要让 macOS 全局信任你自己生成的 CA；仓库不附带 CA 或私钥。仅在你拥有或获授权的设备和网络上使用，勿用于紧急定位、导航、安全控制、欺诈或绕过平台规则。解析失败时脚本会放行原响应，真实位置仍可能出现，因此它不是位置隐私防火墙；使用完毕后应关闭 MITM 并移除该 CA。

**已验证：** macOS 27.0（26A5378j）、Apple Silicon、Shadowrocket for Mac 2.2.90；已确认 `locationd` 请求被 MITM、AppleWLoc 响应被改写、地图位置随之变化。其他版本可能表现不同。

## 要求

- 由你控制的 Mac，以及可正常连接的 Shadowrocket for Mac
- 有权限把自己的 CA 安装到 macOS **系统（System）钥匙串**并设为信任
- macOS 定位服务及目标 App 的定位权限已开启
- Git；运行测试还需要 Node.js 22+，生成模块本身不需要 Node.js

## 快速开始

### 1. 下载并创建本地配置

```bash
git clone https://github.com/Kuirb/macos-location-spoofer.git
cd macos-location-spoofer
cp macos-shadowrocket/location.example.conf macos-shadowrocket/location.conf
open -e macos-shadowrocket/location.conf
```

配置必须包含以下六个键：

```ini
latitude=37.3349
longitude=-122.00902
altitude=56
horizontal_accuracy=15
vertical_accuracy=25
debug=false
```

- `latitude`：`-90` 到 `90`；`longitude`：`-180` 到 `180`
- `altitude`：`-1000` 到 `20000` 米
- `horizontal_accuracy`：`1...1000000` 米
- `vertical_accuracy`：`1...1000000` 米
- `debug`：`true` 或 `false`

不要加引号或单位；海拔在运行时会被截断为整数，精度必须是整数。`location.conf` 和 `macos-shadowrocket/generated/` 已被 Git 忽略；诊断默认会脱敏，但分享截图、日志或压缩包前仍应检查坐标和其他元数据。

### 2. 测试并生成模块

```bash
./macos-shadowrocket/verify.sh
./macos-shadowrocket/update-location.sh
```

生成文件为 `macos-shadowrocket/generated/macos-location-spoofer.sgmodule`。

### 3. 配置 Shadowrocket

1. 将仓库根目录的 `location-spoofer.js` 导入 Shadowrocket 本地 `Documents/Script`，保持文件名不变。
2. 导入并启用生成的 `.sgmodule`，确认 Prepare 和 Response 两条规则都存在。
3. 开启 HTTPS 解密 / MITM；若当前版本有 HTTP/2 解密选项，也将其开启。
4. 在 Shadowrocket 中生成自己的 CA，将证书安装到 macOS **系统钥匙串**并设为“始终信任”。
5. 将 MITM 范围严格限制为 `gs-loc.apple.com`、`gs-loc-cn.apple.com`、`bluedot.is.autonavi.com`、`bluedot.is.autonavi.com.gds.alibabadns.com`。
6. 开启 TUN/VPN；若系统流量绕过隧道，再尝试“包括所有网络”等 TUN 选项。断开并重连 Shadowrocket，开启系统定位服务和地图权限，然后重新打开地图请求“我的位置”。

菜单名称可能随 Shadowrocket 版本变化；系统服务通常不会采用仅放在“登录”钥匙串中的信任证书。

## 如何确认生效

临时将 `debug=true`，重新生成、导入并重连，然后确认以下三项**同时满足**：

1. Shadowrocket 中精确路径 `/clls/wloc` 的请求显示为 **MITM**。
2. 日志出现 `patched N wifi devices, M cell towers`，且 **`N + M > 0`**。
3. 地图的“我的位置”移动到目标坐标。

排障结束后改回 `debug=false`，再次生成、导入并重连；诊断默认会脱敏，但分享前仍请复查日志。

## 工作原理

- Shadowrocket TUN 接管 `locationd` 发往 Apple `/clls/wloc` 的流量。
- Prepare 规则请求未压缩响应，Response 规则解析 AppleWLoc / ARPC / protobuf 数据。
- 脚本改写 Wi‑Fi 热点和基站的坐标、海拔与精度。
- 合法格式的响应随后交还 Core Location，地图可能采用目标位置。

## 更换位置

1. 编辑 `macos-shadowrocket/location.conf` 中的六个值。
2. 运行 `./macos-shadowrocket/update-location.sh`，重新导入或刷新生成的模块。
3. 断开并重连 Shadowrocket，再重新打开地图请求当前位置。

仅保存配置不会更新已导入的模块；更换坐标不需要重新生成 CA。

## 故障排查

- **地图仍在真实位置：** 刷新模块、重连 Shadowrocket、检查定位权限，并等待 Core Location 缓存更新。
- **请求不是 MITM / TLS 报错：** 检查 HTTPS 解密、HTTP/2、四个主机，以及系统钥匙串中的 CA 信任。
- **没有 `/clls/wloc`：** `locationd` 可能在使用缓存或其他定位来源；重新打开地图、切换 Wi‑Fi 或定位服务后再试。
- **改写数为 0 或找不到脚本：** 等待新扫描，检查基站条目，并确认脚本文件名、Prepare 与 Response 规则。

诊断：`./macos-shadowrocket/diagnose.sh`；实时日志：`./macos-shadowrocket/observe-locationd.sh`。

仍无法解决时，请提交已脱敏的 [Issue](https://github.com/Kuirb/macos-location-spoofer/issues)，不要附带 CA、私钥或敏感坐标。

## 恢复与卸载

禁用或删除模块并重连即可临时恢复。完整卸载时，再删除 Shadowrocket 中的 `location-spoofer.js`、本地配置和生成文件，关闭 MITM，并从 Shadowrocket 与系统钥匙串中删除你为本项目生成且能明确识别的 CA；若其他解密规则共用该 CA，删除前先确认。不要删除系统证书或 `/var/db/locationd`。

## 已知限制

- AppleWLoc 是未公开协议，系统更新可能改变字段、封装或主机。
- TUN 旁路、证书固定或系统策略可能阻止 HTTPS 解密。
- Core Location 可能融合缓存、GNSS、IP、蓝牙和传感器数据，结果不保证立即或稳定。
- 使用自有后端、账号/IP 定位的 App 可能不受影响；本项目也不修改出口 IP、时区、账号地区或位置历史，并不提供“不可检测”保证。

## 测试

运行 `./macos-shadowrocket/verify.sh` 可执行离线协议、Shadowrocket 运行时、模块生成、参数校验及配置注入防护测试。

测试通过不代表真实网络、CA 信任或端到端 MITM 已生效。

## 致谢与许可证

本仓库修改自 [mekos2772/ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer)，其工作基于 [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer) 对 Apple 定位协议的研究。当前衍生版本聚焦 macOS `locationd`、Shadowrocket for Mac、纯文本配置、限定域名 MITM 和自动化验证。

项目按 [GNU AGPL-3.0](LICENSE) 发布；再发布或修改时请保留许可证与醒目的修改说明，详见 [NOTICE](NOTICE)。本项目与 Apple、Shadowrocket 或上游作者均无官方隶属关系，也不提供担保。
