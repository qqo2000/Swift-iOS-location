---
AIGC:
  ContentProducer: '001191110102MAD55U9H0F10002'
  ContentPropagator: '001191110102MAD55U9H0F10002'
  Label: '1'
  ProduceID: '5f62358d-f444-4e3f-b52f-416cc6525660'
  PropagateID: '5f62358d-f444-4e3f-b52f-416cc6525660'
  ReservedCode1: '7271e9e3-1a28-4735-aa4b-d8715641b33e'
  ReservedCode2: '7271e9e3-1a28-4735-aa4b-d8715641b33e'
---

# LocationSpoofer - iOS 独立定位欺骗 App

将 [ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer) 的核心功能打包为独立 iOS App，不再依赖电脑运行服务器。

## 原理

App 内置 HTTP 服务器，托管欺骗脚本（`location-spoofer.js`）和坐标配置（`/loc.json`）。代理软件（Shadowrocket/Loon/Surge 等）通过本地网络从 App 读取脚本和坐标，拦截 Apple 定位服务器的响应并替换坐标。

```
iPhone App（内置HTTP服务器）
    ↕ 本地网络
代理软件（Shadowrocket/Loon/Surge）
    ↕ MITM 拦截
Apple 定位服务器 gs-loc.apple.com
```

## 项目结构

```
LocationSpooferApp/
├── Sources/
│   ├── LocationSpooferApp.swift      # App 入口
│   ├── MainView.swift                # 地图UI + 配置面板
│   ├── HTTPServer.swift              # 轻量级HTTP服务器（纯Swift）
│   ├── HTTPServerManager.swift       # 服务器管理 + 模块文件生成
│   └── LocationConfigManager.swift   # 坐标配置持久化
├── Resources/
│   ├── location-spoofer.js           # 核心欺骗脚本（内嵌）
│   ├── location-spoofer-qx.js        # QX 专用脚本（内嵌）
│   ├── location-spoofer-config.json  # 配置样板
│   └── Info.plist
├── project.yml                       # XcodeGen 配置
└── .github/workflows/
    └── build.yml                     # GitHub Actions 编译脚本
```

## 编译方式

### 方式一：GitHub Actions 自动编译（推荐，无需 Mac）

1. Fork 本项目到你的 GitHub 账号
2. 进入仓库 Actions 页签
3. 点击 "Build iOS IPA" → Run workflow
4. 等待编译完成（约 5-10 分钟）
5. 在 Artifacts 中下载 `LocationSpoofer-ipa`

或者打 Tag 自动触发 Release：
```bash
git tag v1.0
git push origin v1.0
```

### 方式二：本地 Mac 编译

```bash
# 安装 XcodeGen
brew install xcodegen

# 生成 Xcode 项目
xcodegen generate

# 编译
xcodebuild -project LocationSpoofer.xcodeproj \
  -scheme LocationSpoofer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

# 打包 IPA
mkdir Payload
cp -r build/Build/Products/Release-iphoneos/LocationSpoofer.app Payload/
zip -r LocationSpoofer.ipa Payload
```

## 安装到 iPhone

### 方法一：TrollStore（推荐，免签名永久安装）

1. 用 [TrollStore](https://github.com/opa334/TrollStore) 安装 .ipa
2. 无需 Apple ID，无需 7 天重签
3. 适用 iOS 14.0-16.6.1（部分 17.0）

### 方法二：Sideloadly（免费 Apple ID，7天重签）

1. 电脑安装 [Sideloadly](https://sideloadly.io/)
2. 连接 iPhone，拖入 .ipa
3. 输入 Apple ID 签名安装
4. iPhone 设置 → 通用 → VPN与设备管理 → 信任开发者证书
5. **7 天后需重新签名**（免费账号限制）

### 方法三：AltStore（类似 Sideloadly）

1. 电脑安装 [AltServer](https://altstore.io/)
2. 连接 iPhone，通过 AltServer 安装 AltStore
3. 在 AltStore 中导入 .ipa 安装
4. 同样 7 天重签

## 使用步骤

### 1. 打开 App

App 启动后内置 HTTP 服务器自动运行，顶部显示：
- 服务器状态（绿色圆点 = 运行中）
- 访问地址（如 `http://192.168.1.x:18099`）
- TOKEN

### 2. 选位置

- 在地图上点一下目标位置
- 海拔/精度可手动微调
- 点「保存定位」

### 3. 复制配置地址

App 底部显示这些地址（点一下复制）：

| 地址 | 用途 |
|------|------|
| Script-Path | 代理软件模块的 `script-path` 参数 |
| ConfigUrl | 代理软件模块的 `configUrl` 参数 |
| 模块下载链接 | 直接下载自动填好地址的模块文件 |

### 4. 在代理软件导入模块

#### Shadowrocket
1. App 底部点「Shadowrocket」复制模块 URL
2. Shadowrocket → 配置 → 右上角 + → URL 导入
3. 或者在 iPhone Safari 打开 URL 下载文件 → 导入

#### Loon
1. 点「Loon」复制 URL
2. Loon → 设置 → 插件 → 添加 → URL 导入
3. 或下载文件后从文件导入

#### Surge
1. 点「Surge」复制 URL
2. Surge → 模块 → 安装新模块 → URL

#### Stash
1. 点「Stash」复制 URL
2. Stash → 覆写 → 安装覆写 → URL

### 5. 开启 MITM 并信任证书

1. 代理软件中打开 HTTPS 解密 / MITM 开关
2. 安装 CA 证书：设置 → 通用 → VPN与设备管理
3. 信任证书：设置 → 通用 → 关于本机 → 证书信任设置 → **打开开关**

### 6. 生效

1. 断开重连 VPN
2. 关闭再打开定位服务
3. 打开地图 App → 验证位置

## 注意事项

- **App 需保持后台运行**：服务器在 App 进程内运行，App 被系统杀掉后服务器断开。建议不要手动上滑关闭 App。
- **WiFi 要求**：代理软件和 App 在同一台 iPhone 上，通过 `127.0.0.1` 或本机 IP 通信。
- **端口冲突**：默认端口 18099，如冲突可在设置中修改。
- **TOKEN 安全**：首次启动自动生成，在设置页可修改。
- **免越狱**：不需要越狱，仅依赖代理软件的 MITM 功能。

> AI生成