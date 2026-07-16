# macOS Location Spoofer for Shadowrocket

[English](README.en.md) · **中文**

通过 Shadowrocket 在 macOS 上定向改写 Apple Wi‑Fi 定位服务的返回结果。无需制作 macOS App、无需 Xcode，也无需关闭 SIP；目标位置直接写在本地纯文本配置里。

> [!IMPORTANT]
> 这是面向研究与测试的概念验证，不是系统级 GPS 驱动，也不是“所有 App 都能生效”的通用定位器。它只影响经指定 Apple `/clls/wloc` 接口返回、并由 Core Location 采用的 Wi‑Fi/基站定位数据。

> [!WARNING]
> 本方案需要 HTTPS 解密和一个由本机信任的 CA。即使模块只限定四个主机，CA 的系统信任本身仍是全局的。只在你拥有或获授权的 Mac 与网络上使用，必须在自己的 Shadowrocket 中生成 CA，绝不安装仓库或他人提供的 CA，并让私钥始终留在本机。请勿用于紧急定位、导航、安全追踪、访问控制、欺诈或未经授权的测试；使用完毕后关闭 HTTPS 解密并移除 CA。

## 工作原理

macOS 的 `locationd` 会把附近 Wi‑Fi/基站信息发给 Apple 定位服务，并根据返回的坐标估算当前位置。本项目让 Shadowrocket 通过 TUN 接管这段流量，只对以下形式的请求执行 HTTPS 解密：

```text
https://<指定主机>/clls/wloc
```

处理流程如下：

```text
locationd
  → Shadowrocket TUN + 限定域名的 MITM
  → Prepare 规则要求服务器返回未压缩内容
  → 解析 AppleWLoc / ARPC / protobuf 二进制响应
  → 改写 Wi‑Fi 热点与基站的位置、海拔和精度
  → 把合法格式的响应交还给 locationd
  → Core Location / 地图可能采用目标位置
```

模块仅包含这四个 MITM 主机：

- `gs-loc.apple.com`
- `gs-loc-cn.apple.com`
- `bluedot.is.autonavi.com`
- `bluedot.is.autonavi.com.gds.alibabadns.com`

请勿为了“省事”改成 `*.apple.com` 或其他大范围通配符。

## 特点

- **纯文本改位置**：编辑本地 `location.conf`，无需手改压缩在 `argument=` 中的模块参数。
- **完整位置参数**：同时配置经纬度、海拔、水平精度和垂直精度。
- **本地脚本**：模块默认引用 Shadowrocket 本地的 `location-spoofer.js`，不会在运行时静默拉取远程脚本。
- **范围受控**：规则只匹配四个定位主机上的精确 `/clls/wloc` 路径。
- **安全解析配置**：配置内容不会被 shell 执行；未知、重复、缺失或非法字段会直接报错。
- **参数优先级明确**：生成模块中的参数不会继承 Shadowrocket 共享持久化存储里的通用旧键值。
- **失败放行**：二进制解析失败时保留原响应，减少系统定位被完全阻断的风险。
- **可验证**：包含协议、Shadowrocket 运行时和模块生成器测试，以及只读诊断脚本。

> [!CAUTION]
> “失败放行”也意味着改写失败时真实定位结果可能继续交给系统。不要把本项目当作位置隐私防火墙，也不要假设它能阻止真实位置泄露。

## 已验证环境

当前概念验证在以下组合中完成：

| 项目 | 实测版本 |
| --- | --- |
| macOS | 27.0（Build 26A5378j） |
| 处理器 | Apple Silicon，`arm64` |
| Shadowrocket for Mac | 2.2.90 |
| Node.js（仅测试使用） | 24.18.0 |

在该环境中已确认：`locationd` 发出精确的 `/clls/wloc` 请求、Shadowrocket 能完成 MITM、脚本能改写带 Wi‑Fi 条目的 AppleWLoc 响应，并且地图的当前位置随之变化。其他 macOS 或 Shadowrocket 版本可能表现不同，尤其是预览版系统。

## 准备工作

你需要：

- 一台由你控制的 Mac；
- 已安装并可正常连接的 Shadowrocket for Mac；
- 有权限在 macOS **系统钥匙串**中安装并信任自己的 CA；
- 已开启 macOS“定位服务”以及目标 App 的定位权限；
- Node.js 18 或更高版本（仅运行测试时需要；生成模块本身只依赖 macOS 自带的 shell 工具）；
- Git（用于克隆仓库，也可以直接下载源码压缩包）。

本项目不包含 CA 证书或私钥。不要安装来自本仓库、网盘或陌生人的“现成证书”；请在自己的 Shadowrocket 中生成一套新的 CA，私钥只保留在本机。

## 快速开始

### 1. 下载项目

```bash
git clone https://github.com/Kuirb/macos-location-spoofer.git
cd macos-location-spoofer
```

### 2. 创建本地纯文本配置

```bash
cp macos-shadowrocket/location.example.conf macos-shadowrocket/location.conf
open -e macos-shadowrocket/location.conf
```

也可以用 VS Code、Vim 或任意纯文本编辑器打开它。`location.conf` 已被 Git 忽略，不会随正常提交公开；仍请在分享日志、终端截图或压缩包前检查其中是否包含敏感目标位置。

示例配置默认指向 Apple Park：

```ini
latitude=37.3349
longitude=-122.00902
altitude=56
horizontal_accuracy=15
vertical_accuracy=25
debug=false
```

改成所需参数后保存。不要加引号，也不要在数字后写 `m`、`米` 或其他单位。

### 3. 运行本地测试并生成模块

```bash
./macos-shadowrocket/verify.sh
./macos-shadowrocket/update-location.sh
```

生成结果位于：

```text
macos-shadowrocket/generated/macos-location-spoofer.sgmodule
```

`verify.sh` 需要 Node.js；`update-location.sh` 不需要。如果测试成功，最后会显示：

```text
All macOS Shadowrocket checks passed.
```

### 4. 把脚本导入 Shadowrocket

在 Shadowrocket 的本地文件/脚本管理中导入仓库根目录的：

```text
location-spoofer.js
```

确保它位于 Shadowrocket 的本地 `Documents/Script` 区域，且文件名仍然是 `location-spoofer.js`。生成的模块默认按这个本地文件名加载脚本；改名会导致规则找不到脚本。

不同 Shadowrocket 版本的菜单名称可能略有差异。可从 Finder 定位该文件后，使用 Shadowrocket 打开，或在 Shadowrocket 的文件管理页选择“从文件导入”。

### 5. 导入并启用模块

将以下文件拖入或使用 Shadowrocket 打开：

```text
macos-shadowrocket/generated/macos-location-spoofer.sgmodule
```

然后在模块列表中确认 `macOS Location Spoofer` 已启用。模块中应同时看到：

- `macOS Location Spoofer Prepare`（请求阶段）；
- `macOS Location Spoofer Response`（响应阶段）。

两条规则缺一不可。Prepare 规则会设置 `Accept-Encoding: identity`，避免压缩响应使二进制改写失败。

仓库若提供 `dist/macos-location-spoofer.sgmodule`，它只是使用示例位置的预生成模块；要使用自己的纯文本配置，请始终导入 `update-location.sh` 刚生成的文件。

### 6. 开启 HTTPS 解密并信任自己的 CA

1. 在 Shadowrocket 中开启 HTTPS 解密 / MITM。
2. 在 Shadowrocket 中**生成一套新的本地 CA**，并安装其证书。
3. 打开 macOS“钥匙串访问”，把该证书放入**系统（System）钥匙串**，而不是只放在“登录”钥匙串。
4. 打开证书详情，在“信任”中设置为“始终信任”，按 macOS 提示使用管理员权限确认。
5. 回到 Shadowrocket，确认模块追加的 MITM 主机只有前述四个域名。

`locationd` 是系统服务，仅在登录钥匙串中信任证书往往不够。CA 的私钥不得上传 GitHub、发给他人或打包进 Issue。

### 7. 连接并验证位置

1. 开启 Shadowrocket 的 TUN/VPN。若 `locationd` 绕过隧道，可尝试 TUN-only（部分版本显示代理类型 `None`）和“包括所有网络”；除非当前网络明确需要，否则保持 `Enforce Routes` 关闭。这些选项会改变全机路由，若网络异常请恢复原值。
2. 断开并重新连接一次 Shadowrocket，使新脚本、模块和 CA 配置进入当前隧道。
3. 前往“系统设置 → 隐私与安全性 → 定位服务”，确认定位服务和地图权限均已开启。
4. 关闭后重新打开地图 App，点击“我的位置”。

Core Location 可能缓存旧结果，第一次变化并不一定立即出现。不要仅凭地图上的一个蓝点判断 MITM 是否成功；下一节给出了完整验证方法。

## 纯文本配置说明

`macos-shadowrocket/location.conf` 必须包含下面六个键，每个键只出现一次：

| 参数 | 合法值 | 默认示例 | 说明 |
| --- | --- | --- | --- |
| `latitude` | `-90` 到 `90` | `37.3349` | 纬度，北纬为正、南纬为负 |
| `longitude` | `-180` 到 `180` | `-122.00902` | 经度，东经为正、西经为负 |
| `altitude` | `-1000` 到 `20000` | `56` | 海拔，单位米，可为负数 |
| `horizontal_accuracy` | 大于 `0` | `15` | 水平精度，单位米；数值越小表示声称越精确 |
| `vertical_accuracy` | 大于 `0` | `25` | 垂直精度，单位米 |
| `debug` | `true` 或 `false` | `false` | 是否输出 Shadowrocket 调试日志 |

建议让海拔和精度与目标地点相互一致：水平精度可先从 `10–50` 米、垂直精度从 `20–100` 米开始；如果数据来源较粗糙，就不要填过于理想的精度。这些只是响应中声明的元数据，不保证 App 接受，也不是“更难检测”的保证；运行时会把数值截断为整数。

可通过可信地图、当地地理资料或高程服务查海拔。例如 Open‑Meteo 的查询格式为：

```text
https://api.open-meteo.com/v1/elevation?latitude=37.3349&longitude=-122.00902
```

公开数字高程模型通常是近似值，不等同于测量级高程。

Open‑Meteo 的成功响应形如 `{"elevation":[56.0]}`，应读取数组第一项。该服务使用约 90 米分辨率的 Copernicus DEM 2021 GLO‑90 地形模型，不代表建筑楼层高度；查询也会把目标坐标发送给第三方。详见 [Open‑Meteo Elevation API](https://open-meteo.com/en/docs/elevation-api)。

解析器接受空行、前后空格，以及第一个非空白字符为 `#` 的整行注释；不支持行末注释。它会拒绝：

- 未知键或重复键；
- 缺少任一必填键；
- 超出范围或非数字的值；
- 给 `debug` 填写 `true` / `false` 之外的值。

配置文件不会通过 `source` 或 `eval` 执行，因此类似 `$(command)` 的内容只会被当作非法值拒绝。

## 更换位置

每次更换目标位置都按同一流程操作：

```bash
open -e macos-shadowrocket/location.conf
./macos-shadowrocket/update-location.sh
```

然后：

1. 在 Shadowrocket 中重新导入或刷新生成的 `.sgmodule`；
2. 确认新模块的 Response 规则中已出现新的参数；
3. 断开并重新连接 Shadowrocket；
4. 重新打开地图并请求当前位置。

仅保存 `location.conf` 不会自动更新 Shadowrocket 中已经导入的模块。同一 CA 仍然有效，不需要每换一次位置就重新安装证书。

需要自动化时也可以直接运行 `generate-module.sh --help` 查看完整命令行参数，但日常使用更推荐编辑纯文本配置。

## 如何确认确实生效

### 本地静态检查

```bash
./macos-shadowrocket/verify.sh
./macos-shadowrocket/diagnose.sh
```

`verify.sh` 会检查 shell 语法、协议重写、Shadowrocket 运行时兼容、生成器参数校验和配置注入防护。`diagnose.sh` 是只读的，会显示系统、Shadowrocket、生成模块、DNS、代理快照与 `locationd` 状态；它**不能**证明 CA 已被信任或流量已经解密。

### 观察 `locationd`

另开一个终端运行：

```bash
./macos-shadowrocket/observe-locationd.sh
```

然后打开地图并请求当前位置。日志中应能观察到 `locationd` 与 `wloc` / `gs-loc` 相关活动；macOS 可能会隐藏部分隐私字段。

### 检查 Shadowrocket 运行日志

1. 临时把 `location.conf` 中的 `debug` 改为 `true`。
2. 重新运行 `./macos-shadowrocket/update-location.sh`。
3. 重新导入/刷新模块，并断开重连 Shadowrocket。
4. 在 Shadowrocket 日志中搜索 `Location spoofer`。

应重点确认：

- 请求主机是前述四个域名之一，路径精确为 `/clls/wloc`（可带查询参数）；
- 请求类型显示已被 MITM，而不是直连或旁路；
- 出现 `Location spoofer intercept`；
- 出现 `patched N wifi devices, M cell towers`，且 `N + M > 0`；
- `patched locations` 中的坐标与当前配置一致；
- 地图随后移动到目标位置。

以上三项——`/clls/wloc` 显示为 MITM、改写记录总数大于 0、地图位置变化——需要同时满足。仅有 DNS 可解析、连接到某个主机、`verify.sh` 通过或 `diagnose.sh` 输出正常，都不能单独证明真实流量已被改写。

调试日志可能包含目标坐标、请求元数据和网络信息。排障结束后将 `debug=false`，再次生成、重新导入并重连；分享日志前先脱敏。

## 恢复真实定位与卸载

要临时恢复真实定位：

1. 在 Shadowrocket 中禁用或删除 `macOS Location Spoofer` 模块；
2. 断开并重新连接 Shadowrocket；
3. 关闭并重新打开地图，必要时关闭再开启定位服务以清除旧缓存。

要完整移除：

1. 删除 Shadowrocket 中的模块和本地 `location-spoofer.js`；
2. 如果不再需要 HTTPS 解密，关闭 Shadowrocket 的 HTTPS 解密 / MITM；
3. 在“钥匙串访问”的**系统**钥匙串中删除你为本项目生成的 CA；
4. 删除 Shadowrocket 中对应的证书配置；
5. 删除本地 `location.conf` 和 `generated/` 输出。

只删除你自己生成并能明确识别的 CA，不要删除系统或其他软件使用的证书。
删除该 CA 也会使依赖它的其他 Shadowrocket HTTPS 解密规则失效，操作前先确认。不要删除 `/var/db/locationd`。

## 故障排查

| 现象 | 优先检查 |
| --- | --- |
| 地图仍显示真实位置 | 模块是否启用、是否重新导入了最新生成文件、Shadowrocket 是否已重连、定位服务是否开启，以及旧结果是否被缓存 |
| 有请求但不是 MITM | CA 是否位于系统钥匙串并“始终信任”、HTTPS 解密是否开启、四个主机是否生效、系统流量是否绕过 TUN |
| TLS / 证书错误 | 检查 CA 是否过期或重复、系统钥匙串信任设置是否正确；必要时在 Shadowrocket 重新生成自己的 CA 并重连 |
| 日志完全没有 `/clls/wloc` | `locationd` 可能仍在使用缓存或当前系统改用了其他定位来源；重新打开地图、切换 Wi‑Fi/定位服务后再观察 |
| `gzip`、解压或响应体错误 | 确认 Prepare 与 Response 两条规则都已启用，且使用的是刚生成的模块 |
| `patched 0 wifi devices` | 当前 Apple 响应可能没有 Wi‑Fi 条目；确认 Wi‑Fi 已开启并等待新扫描，另看是否改写了基站条目 |
| 找不到脚本或脚本超时 | 确认本地文件名精确为 `location-spoofer.js`，模块没有引用已删除的远程/本地路径，并检查 Shadowrocket 版本 |
| `configuration file not found` | 先把 `location.example.conf` 复制为 `location.conf`，或使用 `--config` 指定路径 |
| 改了配置但位置没变 | `location.conf` 不会热加载；必须重新生成、重新导入/刷新模块，再重连 Shadowrocket |

若要提交 Issue，请附上 macOS 版本、架构、Shadowrocket 版本、是否看到精确 `/clls/wloc`、MITM 状态和已经脱敏的 `Location spoofer` 日志。不要上传 CA、私钥、完整请求体、真实位置或不愿公开的目标坐标。

## 已知限制

- AppleWLoc 是未公开协议，字段、封装或主机可能随 macOS 更新而变化。
- 本项目依赖 Shadowrocket 能接管 `locationd` 的系统流量并完成 HTTPS 解密；路由旁路、证书固定或系统策略都可能使其失效。
- Core Location 会缓存结果，也可能融合 GNSS、IP、蓝牙、惯性传感器或其他来源，因此结果不保证立即、稳定或唯一。
- 使用自有后端、账号侧定位、IP 定位或证书固定的 App 可能完全不受影响。
- 本项目不会修改出口 IP、时区、语言、账号地区、硬件传感器或应用服务器保存的位置历史。
- 它不提供“不可检测”保证，也不应被用于绕过安全控制、考勤、风控、游戏规则或平台限制。
- 解析异常时默认放行原响应，真实位置可能重新出现。

## 文件结构

```text
.
├── README.md                              # 中文说明
├── README.en.md                           # English documentation
├── LICENSE                                # GNU AGPL-3.0
├── NOTICE                                 # 衍生项目与修改声明
├── location-spoofer.js                    # AppleWLoc/ARPC/protobuf 改写核心
├── dist/
│   └── macos-location-spoofer.sgmodule    # 示例位置的预生成模块
└── macos-shadowrocket/
    ├── location.example.conf              # 可提交的纯文本样例
    ├── location.conf                      # 你的本地配置（Git 忽略）
    ├── module.template.sgmodule            # Shadowrocket 模块模板
    ├── generate-module.sh                  # 参数校验与模块生成器
    ├── update-location.sh                  # 从 location.conf 生成模块
    ├── generated/                          # 个性化生成结果（Git 忽略）
    ├── diagnose.sh                         # 只读环境诊断
    ├── observe-locationd.sh                # 实时观察 locationd 日志
    ├── verify.sh                           # 一键本地验证
    ├── test-protocol.js                    # 协议编码/改写测试
    └── test-runtime.js                     # Shadowrocket 运行时测试
```

## 开发与测试

提交修改前运行：

```bash
./macos-shadowrocket/verify.sh
```

测试覆盖：

- synthetic/prefixed、marker、ARPC 与 bare 四类封装及尾部数据保留；
- AppleWLoc 响应中的 Wi‑Fi 与两种基站记录；
- 经纬度、海拔、水平/垂直精度和运动状态字段的改写；
- Shadowrocket 请求准备、gzip 解压和二进制响应体回写；
- 模块模板生成、数值范围和危险脚本路径校验；
- 示例配置、未知字段，以及配置内容不会被 shell 执行。

这些都是合成 fixture 的离线测试，不等同于真实网络、CA 信任或端到端 MITM 测试。

生成器的所有选项：

```bash
./macos-shadowrocket/generate-module.sh --help
```

## 致谢与许可证

本仓库是 [mekos2772/ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer) 的修改衍生项目；该项目基于 [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer) 对 Apple 定位协议的研究。这里的 2026 年修改聚焦于 macOS `locationd`、Shadowrocket for Mac、纯文本本地配置、限定域名的 CA/MITM 流程和自动化验证。

项目按 [GNU Affero General Public License v3.0](LICENSE) 发布。再发布或修改时请保留版权、许可证和醒目的修改说明，并按 AGPL-3.0 履行相应源代码义务；详见 [NOTICE](NOTICE)。本项目与 Apple、Shadowrocket 及上述上游作者均无官方隶属关系，也不提供任何担保。
