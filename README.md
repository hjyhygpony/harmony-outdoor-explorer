# Harmony Outdoor Explorer

基于 HarmonyOS / ArkTS 的户外探险应用，包含地图导航、轨迹记录、电子围栏、SOS、群组位置共享、本地数据存储和 Node.js WebSocket 服务端。

## 功能

- 华为 Map Kit 地图展示
- 地点搜索与路线规划
- 驾车、步行、骑行导航入口
- GPS 轨迹记录、暂停、继续和回放
- GPX / KML 导入导出
- Haversine 距离计算
- 电子围栏与进入/离开事件
- SOS 紧急求助
- 群组创建、加入和成员位置共享
- 群组管理员踢人
- 电量、信号和最后在线状态
- Node.js WebSocket 实时同步服务
- HarmonyOS 权限、后台定位和本地数据库

## 技术栈

| 层 | 技术 |
|---|---|
| 客户端 | HarmonyOS、ArkTS、ArkUI |
| 系统能力 | Map Kit、Location、Push Kit、Safety Detect、后台任务 |
| 本地存储 | HarmonyOS Database / Preferences |
| 实时通信 | WebSocket |
| 服务端 | Node.js、`ws`、`uuid` |
| SDK | HarmonyOS 6.0.0 / API 20 |

## 项目结构

```text
harmony-outdoor-explorer/
├─ AppScope/
├─ entry/src/main/ets/
│  ├─ pages/       # 首页、地图、户外记录、群组页面
│  ├─ services/    # 定位、轨迹、围栏、SOS、数据库、WebSocket
│  ├─ model/       # 数据模型
│  └─ utils/       # GPX/KML/权限工具
├─ server/
│  ├─ index.js     # WebSocket 群组位置服务
│  └─ package.json
├─ hvigor/
├─ build-profile.json5
├─ oh-package.json5
└─ README.md
```

## 启动 HarmonyOS 客户端

1. 使用 DevEco Studio 打开本目录。
2. 配置 HarmonyOS SDK 和自动签名。
3. 将 `entry/src/main/module.json5` 中的 `YOUR_HUAWEI_CLIENT_ID` 替换成你自己的 AppGallery Connect client ID。
4. 在 DevEco Studio 中申请 Map Kit、Push Kit、Safety Detect 等所需服务。
5. 启动模拟器或连接真机。
6. 在群组页面填写电脑的局域网 IP，默认示例为 `192.168.1.100`。

仓库不包含：

- 签名证书、`.p12`、`.p7b`、`.cer`
- 机器专属 `local.properties`
- `oh_modules`、`.hvigor`、`build`
- 系统镜像和本地 SDK
- 真实华为服务凭据

## AppGallery Connect 配置

从 AppGallery Connect 下载自己的 `agconnect-services.json`，放到 `entry/src/main/agconnect-services.json`。该文件已被 .gitignore 排除，不要提交真实 client secret 或 API Key。仓库只提供 `agconnect-services.example.json`。

## 启动 WebSocket 服务端

```powershell
cd server
npm install
npm start
```

默认监听：

```text
ws://<服务器IP>:8080
```

确保手机与服务器在可达网络中。跨公网部署还需要端口映射、反向代理或公网服务器，并建议增加 TLS、鉴权和限流。

## 群组服务协议

服务端使用 JSON 消息，主要类型包括：

- `register`
- `createGroup`
- `joinGroup`
- `leaveGroup`
- `updateLocation`
- `updateStatus`
- `sos`
- `getGroupInfo`
- `kickMember`
- `addGeofence`
- `removeGroupGeofence`
- `geofenceEvent`
- `startSharing`
- `stopSharing`

## 说明

这是课程实践项目，重点展示 HarmonyOS 地图、定位、轨迹和实时群组协作能力。地图、推送、设备安全等云服务需要在华为开发者平台单独配置；服务端使用内存存储，进程重启后群组数据会清空。

