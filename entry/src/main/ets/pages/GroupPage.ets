// entry/src/main/ets/pages/GroupPage.ets
// 群组功能页面 - 支持WebSocket实时同步
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import {
  wsService,
  GroupInfo,
  MemberInfo,
  SOSAlert,
  SOSAlertFrom,
  SOSAlertLocation,
  WSMessage,
  GroupData
} from '../services/WebSocketService';
import { locationService } from '../services/LocationService';
import { promptAction } from '@kit.ArkUI';
import router from '@ohos.router';

@Entry
@Component
export struct GroupPage {
  // 连接状态
  @State isConnected: boolean = false;
  @State serverIP: string = '192.168.1.100'; // 默认服务器IP
  @State userName: string = '';
  @State showSettings: boolean = true;
  // 群组
  @State groups: GroupInfo[] = [];
  @State currentGroup: GroupInfo | null = null;
  @State members: MemberInfo[] = [];
  // 创建/加入群组
  @State showCreateGroup: boolean = false;
  @State showJoinGroup: boolean = false;
  @State newGroupName: string = '';
  @State joinGroupCode: string = '';
  // 位置共享
  @State shareExpireTime: number = 0;
  @State currentLat: number = 0;
  @State currentLon: number = 0;
  // SOS
  @State showSOSAlert: boolean = false;
  @State sosAlert: SOSAlert | null = null;
  // 地图
  private context = getContext(this) as common.UIAbilityContext;
  private mapController: map.MapComponentController | null = null;
  private mapOption?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private memberMarkers: Map<string, map.Marker> = new Map();
  private locationTimer: number = -1;

  aboutToAppear(): void {
    this.initMap();
    this.setupWSCallbacks();
  }

  aboutToDisappear(): void {
    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
    }
  }

  initMap() {
    this.mapOption = {
      position: {
        target: { latitude: 39.9042, longitude: 116.4074 },
        zoom: 14
      },
      scaleControlsEnabled: true
    };

    this.mapCallback = async (err, controller) => {
      if (!err && controller) {
        this.mapController = controller;
        controller.setMyLocationEnabled(true);
        controller.setMyLocationControlsEnabled(true);
      }
    };
  }

  setupWSCallbacks() {
    // 连接状态
    wsService.setConnectionCallback((connected) => {
      this.isConnected = connected;
      if (!connected) {
        promptAction.showToast({ message: '连接已断开，正在重连...' });
      }
    });

    // 注册成功
    wsService.on('registerSuccess', (msg) => {
      this.groups = msg.groups as GroupInfo[];
      this.showSettings = false;
      promptAction.showToast({ message: '连接成功' });
    });

    // 创建群组成功
    wsService.on('createGroupSuccess', (msg) => {
      const group = msg.group as GroupInfo;
      this.groups.push(group);
      this.currentGroup = group;
      this.showCreateGroup = false;
      promptAction.showToast({ message: `群组已创建，邀请码: ${group.code}` });
      this.startLocationSharing();
    });

    // 加入群组成功
    wsService.on('joinGroupSuccess', (msg) => {
      const group = msg.group as GroupInfo;
      this.groups.push(group);
      this.currentGroup = group;
      this.showJoinGroup = false;
      promptAction.showToast({ message: `已加入群组: ${group.name}` });
      wsService.getGroupInfo(group.code);
      this.startLocationSharing();
    });

    // 加入失败
    wsService.on('joinGroupFailed', (msg) => {
      promptAction.showToast({ message: msg.reason as string });
    });
    // 群组信息
    wsService.on('groupInfo', (msg) => {
      if (msg.error) {
        return;
      }
      // 检查group属性是否为GroupData类型
      const groupData = msg.group as GroupData;
      if (groupData && groupData.members) {
        this.members = groupData.members;
        this.renderMembersOnMap();
      }
    });

    // 位置更新
    wsService.on('locationUpdate', (msg) => {
      const member = msg.member as MemberInfo;
      this.updateMemberLocation(member);
    });

    // 成员加入
    wsService.on('memberJoined', (msg) => {
      const member = msg.member as MemberInfo;
      this.members.push(member);
      promptAction.showToast({ message: `${member.name} 加入了群组` });
    });

    // 成员离开
    wsService.on('memberLeft', (msg) => {
      const odId = msg.odId as string;
      const name = msg.name as string;
      this.members = this.members.filter(m => m.odId !== odId);
      this.removeMemberMarker(odId);
      promptAction.showToast({ message: `${name} 离开了群组` });
    });
    // SOS警报
    wsService.on('sosAlert', (msg) => {
      this.sosAlert = {
        from: msg.from as SOSAlertFrom,
        location: msg.location as SOSAlertLocation,
        battery: msg.battery as number,
        message: msg.message as string,
        timestamp: msg.timestamp as number
      };
      this.showSOSAlert = true;
      // 移动地图到SOS位置
      if (this.mapController) {
        const cameraUpdate = map.newCameraPosition({
          target: this.sosAlert.location,
          zoom: 16
        });
        this.mapController.animateCamera(cameraUpdate);
      }
    });

    // 被踢出
    wsService.on('kicked', (msg) => {
      const groupName = msg.groupName as string;
      promptAction.showToast({ message: `你已被移出群组: ${groupName}` });
      this.currentGroup = null;
      this.members = [];
      this.clearAllMarkers();
    });

    // 群组解散
    wsService.on('groupDisbanded', (msg) => {
      promptAction.showToast({ message: '群组已解散' });
      this.currentGroup = null;
      this.members = [];
      this.clearAllMarkers();
    });
  }

  build() {
    Stack() {
      // 地图
      MapComponent({
        mapOptions: this.mapOption,
        mapCallback: this.mapCallback
      })
        .width('100%')
        .height('100%')

      // 顶部状态栏
      Column() {
        Row() {
          // 连接状态
          Row() {
            Circle()
              .width(8)
              .height(8)
              .fill(this.isConnected ? '#4CAF50' : '#F44336')
            Text(this.isConnected ? '已连接' : '未连接')
              .fontSize(12)
              .fontColor(this.isConnected ? '#4CAF50' : '#F44336')
              .margin({ left: 4 })
          }

          Blank()

          // 当前群组
          if (this.currentGroup) {
            Text(`${this.currentGroup.name} (${this.currentGroup.code})`)
              .fontSize(14)
              .fontColor('#333')
          }

          Blank()
          // 设置按钮
          Button() {
            Text('设置')
              .fontSize(12)
              .fontColor('#666')
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.White)
          .borderRadius(18)
          .onClick(() => this.showSettings = true)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .padding({ top: 50 })

      // 底部操作栏
      Column() {
        // 成员列表（横向滚动）
        if (this.members.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.members, (member: MemberInfo) => {
                this.buildMemberChip(member)
              })
            }
            .padding({ left: 12, right: 12 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .height(70)
        }

        // 操作按钮
        Row({ space: 12 }) {
          if (!this.currentGroup) {
            Button('创建群组')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#4CAF50')
              .onClick(() => this.showCreateGroup = true)

            Button('加入群组')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#2196F3')
              .onClick(() => this.showJoinGroup = true)
          } else {
            Button('邀请码: ' + this.currentGroup.code)
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#E3F2FD')
              .fontColor('#2196F3')

            Button('退出群组')
              .width(100)
              .height(44)
              .backgroundColor('#FFEBEE')
              .fontColor('#F44336')
              .onClick(() => this.leaveGroup())
          }
        }
        .width('100%')
        .padding(12)
      }
      .width('100%')
      .backgroundColor('rgba(255,255,255,0.95)')
      .position({ x: 0, y: '100%' })
      .translate({ y: this.members.length > 0 ? -180 : -110 })

      // SOS按钮
      Button('SOS')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(56)
        .height(56)
        .backgroundColor('#F44336')
        .borderRadius(28)
        .shadow({ radius: 8, color: 'rgba(244,67,54,0.4)' })
        .position({ x: '100%', y: '50%' })
        .translate({ x: -72 })
        .gesture(
          LongPressGesture({ repeat: false, duration: 1000 })
            .onAction(() => this.sendSOS())
        )

      // 设置弹窗
      if (this.showSettings) {
        this.buildSettingsDialog()
      }

      // 创建群组弹窗
      if (this.showCreateGroup) {
        this.buildCreateGroupDialog()
      }

      // 加入群组弹窗
      if (this.showJoinGroup) {
        this.buildJoinGroupDialog()
      }

      // SOS警报弹窗
      if (this.showSOSAlert && this.sosAlert) {
        this.buildSOSAlertDialog()
      }
    }
    .width('100%')
    .height('100%')
    .onAppear(() => this.reqPermissions())
  }

  @Builder
  buildMemberChip(member: MemberInfo) {
    Column() {
      Stack() {
        Text(member.name.charAt(0))
          .fontSize(16)
          .fontColor(Color.White)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor(member.odId === wsService.getOdId() ? '#FF9800' : '#007DFF')
          .borderRadius(20)

        // 在线状态
        Circle()
          .width(10)
          .height(10)
          .fill(member.isOnline ? '#4CAF50' : '#999')
          .position({ x: 30, y: 30 })
      }

      Text(member.name)
        .fontSize(11)
        .fontColor('#333')
        .maxLines(1)
        .margin({ top: 4 })

      Row() {
        Text(`🔋${member.battery}%`)
          .fontSize(9)
          .fontColor(member.battery < 20 ? '#F44336' : '#999')
      }
    }
    .width(60)
    .onClick(() => this.locateMember(member))
  }

  @Builder
  buildSettingsDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          if (this.isConnected) {
            this.showSettings = false;
          }
        })

      Column() {
        Text('连接设置').fontSize(18).fontWeight(FontWeight.Bold)

        TextInput({ placeholder: '你的昵称', text: this.userName })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((v) => this.userName = v)

        TextInput({ placeholder: '服务器IP (如: 192.168.1.100)', text: this.serverIP })
          .width('100%')
          .height(44)
          .margin({ top: 12 })
          .onChange((v) => this.serverIP = v)

        Text('提示: 确保手机和服务器在同一局域网')
          .fontSize(12)
          .fontColor('#999')
          .margin({ top: 8 })

        Button(this.isConnected ? '已连接' : '连接服务器')
          .width('100%')
          .height(44)
          .backgroundColor(this.isConnected ? '#4CAF50' : '#007DFF')
          .margin({ top: 16 })
          .enabled(!this.isConnected)
          .onClick(() => this.connectServer())

        if (this.isConnected) {
          Button('断开连接')
            .width('100%')
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#F44336')
            .margin({ top: 8 })
            .onClick(() => {
              wsService.disconnect();
              this.isConnected = false;
            })
        }
      }
      .width('85%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '7.5%', y: '25%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildCreateGroupDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showCreateGroup = false)

      Column() {
        Text('创建群组').fontSize(18).fontWeight(FontWeight.Bold)

        TextInput({ placeholder: '群组名称（如：周末徒步）' })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((v) => this.newGroupName = v)

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showCreateGroup = false)

          Button('创建')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#4CAF50')
            .onClick(() => {
              if (this.newGroupName.trim()) {
                wsService.createGroup(this.newGroupName);
              }
            })
        }
        .margin({ top: 20 })
      }
      .width('85%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '7.5%', y: '30%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildJoinGroupDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showJoinGroup = false)

      Column() {
        Text('加入群组').fontSize(18).fontWeight(FontWeight.Bold)

        TextInput({ placeholder: '输入6位邀请码' })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .maxLength(6)
          .onChange((v) => this.joinGroupCode = v.toUpperCase())

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showJoinGroup = false)

          Button('加入')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#2196F3')
            .onClick(() => {
              if (this.joinGroupCode.length === 6) {
                wsService.joinGroup(this.joinGroupCode);
              }
            })
        }
        .margin({ top: 20 })
      }
      .width('85%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '7.5%', y: '30%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSOSAlertDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(244,67,54,0.3)')

      Column() {
        Text('🆘').fontSize(48)
        Text('紧急求助').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F44336')

        Text(`${this.sosAlert?.from.name} 发出求助！`)
          .fontSize(16)
          .margin({ top: 12 })

        Column() {
          Text(`📍 位置: ${this.sosAlert?.location.latitude.toFixed(6)}, ${this.sosAlert?.location.longitude.toFixed(6)}`)
            .fontSize(13)
            .fontColor('#666')
          Text(`🔋 电量: ${this.sosAlert?.battery}%`)
            .fontSize(13)
            .fontColor('#666')
            .margin({ top: 4 })
          if (this.sosAlert?.message) {
            Text(`💬 消息: ${this.sosAlert.message}`)
              .fontSize(13)
              .fontColor('#666')
              .margin({ top: 4 })
          }
        }
        .margin({ top: 12 })
        .padding(12)
        .backgroundColor('#FFF3E0')
        .borderRadius(8)
        .width('100%')

        Button('查看位置')
          .width('100%')
          .height(44)
          .backgroundColor('#F44336')
          .margin({ top: 16 })
          .onClick(() => {
            this.showSOSAlert = false;
            if (this.sosAlert && this.mapController) {
              const cameraUpdate = map.newCameraPosition({
                target: this.sosAlert.location,
                zoom: 17
              });
              this.mapController.animateCamera(cameraUpdate);
            }
          })
      }
      .width('85%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '7.5%', y: '20%' })
    }
    .width('100%')
    .height('100%')
  }

  // ========== 业务方法 ==========

  async connectServer() {
    if (!this.userName.trim()) {
      promptAction.showToast({ message: '请输入昵称' });
      return;
    }
    if (!this.serverIP.trim()) {
      promptAction.showToast({ message: '请输入服务器IP' });
      return;
    }

    wsService.init(this.userName);
    const url = `ws://${this.serverIP}:8080`;
    console.info(`[GroupPage] Connecting to: ${url}`);
    promptAction.showToast({ message: `正在连接 ${url}...` });

    try {
      const success = await wsService.connect(url);
      if (!success) {
        promptAction.showToast({ message: '连接失败，请确保:\n1. 服务器已启动\n2. IP地址正确\n3. 在同一网络' });
      }
    } catch (e) {
      console.error('[GroupPage] Connect error:', JSON.stringify(e));
      promptAction.showToast({ message: '连接异常: ' + JSON.stringify(e) });
    }
  }

  startLocationSharing() {
    // 停止之前的定时器
    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
    }

    // 每5秒上报一次位置
    this.locationTimer = setInterval(async () => {
      if (!this.currentGroup || !this.isConnected) {
        return;
      }

      const loc = await locationService.getCurrentPosition();
      if (loc) {
        this.currentLat = loc.latitude;
        this.currentLon = loc.longitude;
        wsService.updateLocation(
          this.currentGroup.code,
          loc.latitude,
          loc.longitude,
          this.shareExpireTime
        );
      }
    }, 5000);

    // 立即上报一次
    this.uploadLocationNow();
  }

  async uploadLocationNow() {
    if (!this.currentGroup) {
      return;
    }

    const loc = await locationService.getCurrentPosition();
    if (loc) {
      this.currentLat = loc.latitude;
      this.currentLon = loc.longitude;
      wsService.updateLocation(
        this.currentGroup.code,
        loc.latitude,
        loc.longitude,
        this.shareExpireTime
      );
    }
  }

  leaveGroup() {
    if (!this.currentGroup) {
      return;
    }

    wsService.leaveGroup(this.currentGroup.code);
    this.groups = this.groups.filter(g => g.code !== this.currentGroup?.code);
    this.currentGroup = null;
    this.members = [];
    this.clearAllMarkers();

    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
      this.locationTimer = -1;
    }
  }

  async sendSOS() {
    if (!this.currentGroup) {
      promptAction.showToast({ message: '请先加入群组' });
      return;
    }

    const loc = await locationService.getCurrentPosition();
    if (loc) {
      wsService.sendSOS(
        this.currentGroup.code,
        loc.latitude,
        loc.longitude,
        '紧急求助！请立即查看我的位置！'
      );
      promptAction.showToast({ message: 'SOS已发送' });
    }
  }

  locateMember(member: MemberInfo) {
    if (!this.mapController || member.latitude === 0) {
      return;
    }

    const cameraUpdate = map.newCameraPosition({
      target: { latitude: member.latitude, longitude: member.longitude },
      zoom: 16
    });
    this.mapController.animateCamera(cameraUpdate);
  }

  // ========== 地图标记 ==========
  updateMemberLocation(member: MemberInfo) {
    // 更新成员列表
    const index = this.members.findIndex(m => m.odId === member.odId);
    if (index !== -1) {
      // 手动更新成员属性
      const existingMember = this.members[index];
      existingMember.latitude = member.latitude;
      existingMember.longitude = member.longitude;
      existingMember.battery = member.battery;
      existingMember.signal = member.signal;
      existingMember.lastUpdate = member.lastUpdate;
      existingMember.isOnline = member.isOnline;
    }

    // 更新地图标记
    this.updateMemberMarker(member);
  }

  async updateMemberMarker(member: MemberInfo) {
    if (!this.mapController) {
      return;
    }

    // 不显示自己的标记（使用系统蓝点）
    if (member.odId === wsService.getOdId()) {
      return;
    }

    const existingMarker = this.memberMarkers.get(member.odId);
    if (existingMarker) {
      // 更新位置
      existingMarker.setPosition({ latitude: member.latitude, longitude: member.longitude });
    } else {
      // 创建新标记
      const options: mapCommon.MarkerOptions = {
        position: { latitude: member.latitude, longitude: member.longitude },
        visible: true,
        title: member.name,
        zIndex: 20,
        alpha: 1,
        anchorU: 0.5,
        anchorV: 1,
        clickable: true,
        draggable: false,
        flat: false
      };
      const marker = await this.mapController.addMarker(options);
      this.memberMarkers.set(member.odId, marker);
    }
  }

  removeMemberMarker(odId: string) {
    const marker = this.memberMarkers.get(odId);
    if (marker) {
      marker.remove();
      this.memberMarkers.delete(odId);
    }
  }

  clearAllMarkers() {
    this.memberMarkers.forEach((marker) => {
      marker.remove();
    });
    this.memberMarkers.clear();
  }

  async renderMembersOnMap() {
    for (const member of this.members) {
      if (member.latitude !== 0 && member.odId !== wsService.getOdId()) {
        await this.updateMemberMarker(member);
      }
    }
  }

  async reqPermissions() {
    const permissions: Array<Permissions> = [
      'ohos.permission.LOCATION',
      'ohos.permission.APPROXIMATELY_LOCATION'
    ];
    const atManager = abilityAccessCtrl.createAtManager();

    try {
      const result = await atManager.requestPermissionsFromUser(this.context, permissions);
      const isGranted = result.authResults.every(s => s === 0);
      if (isGranted) {
        const loc = await locationService.getCurrentPosition();
        if (loc && this.mapController) {
          this.currentLat = loc.latitude;
          this.currentLon = loc.longitude;
          const cameraUpdate = map.newCameraPosition({
            target: { latitude: loc.latitude, longitude: loc.longitude },
            zoom: 15
          });
          this.mapController.animateCamera(cameraUpdate);
        }
      }
    } catch (err) {
      console.error('[GroupPage] Permission error:', JSON.stringify(err));
    }
  }
}

