// entry/src/main/ets/pages/OutdoorMainPage.ets
// 整合后的户外活动主页面 - 包含地图、活动、群组、我的四个Tab
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { databaseService, Track, MapMarker, Geofence, GroupGeofence, ActivityType } from '../services/DatabaseService';
import { trackingService, TrackingStatus } from '../services/TrackingService';
import { geofenceService, GeofenceEvent, GroupGeofenceEvent } from '../services/GeofenceService';
import { sosService } from '../services/SOSService';
import { locationService } from '../services/LocationService';
import {
  wsService,
  GroupInfo,
  MemberInfo,
  SOSAlert,
  SOSAlertFrom,
  SOSAlertLocation,
  SOSTrackPoint,
  GroupData,
  ShareDuration,
  SHARE_DURATION_MS,
  GroupGeofenceData,
  GeofenceEventData
} from '../services/WebSocketService';
import { promptAction } from '@kit.ArkUI';
import router from '@ohos.router';

// 路由参数接口
interface RouterParams {
  tab?: string;
}

// 底部Tab类型
type TabType = 'map' | 'activity' | 'group' | 'profile';

// 标记类型
interface MarkerType {
  key: string;
  name: string;
  icon: string;
}

// 共享时长选项
interface ShareDurationOption {
  key: ShareDuration;
  name: string;
  description: string;
}

@Entry
@Component
export struct OutdoorMainPage {
  // Tab状态
  @State currentTab: TabType = 'map';
  // 地图状态
  @State currentLat: number = 39.9042;
  @State currentLon: number = 116.4074;
  // 轨迹状态
  @State trackingStatus: TrackingStatus = {
    isRecording: false,
    isPaused: false,
    currentTrackId: -1,
    distance: 0,
    duration: 0,
    pointCount: 0,
    startTime: 0,
    activityType: ActivityType.OTHER
  };
  @State tracks: Track[] = [];
  // 标记
  @State markers: MapMarker[] = [];
  @State showAddMarker: boolean = false;
  @State newMarkerName: string = '';
  @State newMarkerDesc: string = '';
  @State newMarkerType: string = 'custom';
  @State selectedMarkerLat: number = 0;
  @State selectedMarkerLon: number = 0;
  // 围栏
  @State geofences: Geofence[] = [];
  @State showAddFence: boolean = false;
  @State newFenceName: string = '';
  @State newFenceRadius: number = 100;
  // 群组围栏
  @State groupGeofences: GroupGeofence[] = [];
  @State showAddGroupFence: boolean = false;
  @State showGroupFenceList: boolean = false;
  @State newGroupFenceName: string = '';
  @State newGroupFenceRadius: number = 100;
  @State newGroupFenceType: string = 'safe';
  // 长按地图选择弹窗
  @State showLongPressMenu: boolean = false;
  // SOS
  @State showSOS: boolean = false;
  @State sosCountdown: number = 0;
  @State sosMessage: string = '';
  @State showSOSAlert: boolean = false;
  @State sosAlert: SOSAlert | null = null;
  // 群组状态
  @State isConnected: boolean = false;
  @State serverIP: string = '192.168.1.100';
  @State userName: string = '';
  @State showSettings: boolean = false;
  @State groups: GroupInfo[] = [];
  @State currentGroup: GroupInfo | null = null;
  @State members: MemberInfo[] = [];
  @State showCreateGroup: boolean = false;
  @State showJoinGroup: boolean = false;
  @State newGroupName: string = '';
  @State joinGroupCode: string = '';
  // 位置共享
  @State isSharing: boolean = false;
  @State shareExpireTime: number = 0;
  @State shareDuration: ShareDuration = 'always';
  @State shareRemainingTime: number = 0; // 剩余时间（毫秒）
  @State showShareDurationDialog: boolean = false; // 显示时长选择弹窗
  // 定时器
  private durationTimer: number = -1;
  private locationTimer: number = -1;
  private shareCountdownTimer: number = -1; // 共享倒计时定时器
  // 地图
  private context = getContext(this) as common.UIAbilityContext;
  private mapController: map.MapComponentController | null = null;
  private mapOption?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapMarkers: map.Marker[] = [];
  private fenceCircles: map.MapCircle[] = [];
  private groupFenceCircles: map.MapCircle[] = [];
  private trackPolyline: map.MapPolyline | null = null;
  private liveTrackPolyline: map.MapPolyline | null = null; // 实时轨迹线
  private currentPositionMarker: map.Marker | null = null; // 轨迹记录时的当前位置标记
  private isCreatingPositionMarker: boolean = false; // 防止并发创建标记
  private memberMarkers: Map<string, map.Marker> = new Map();
  // 标记类型列表
  private markerTypes: MarkerType[] = [
    { key: 'water', name: '水源点', icon: '💧' },
    { key: 'rest', name: '休息区', icon: '🏕️' },
    { key: 'danger', name: '危险区', icon: '⚠️' },
    { key: 'camp', name: '营地', icon: '⛺' },
    { key: 'custom', name: '自定义', icon: '📍' }
  ];
  // 共享时长选项列表
  private shareDurationOptions: ShareDurationOption[] = [
    { key: '15min', name: '15分钟', description: '短时间共享' },
    { key: '1hour', name: '1小时', description: '适合短途活动' },
    { key: '4hours', name: '4小时', description: '适合半日活动' },
    { key: 'always', name: '持续共享', description: '直到手动停止' }
  ];

  aboutToAppear(): void {
    // 处理路由参数，设置初始Tab
    const params = router.getParams() as RouterParams;
    if (params && params.tab) {
      const tab = params.tab as TabType;
      if (tab === 'map' || tab === 'activity' || tab === 'group' || tab === 'profile') {
        this.currentTab = tab;
      }
    }

    this.initMap();
    this.initServices();
    this.setupWSCallbacks();
  }

  aboutToDisappear(): void {
    if (this.durationTimer !== -1) {
      clearInterval(this.durationTimer);
    }
    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
    }
    if (this.shareCountdownTimer !== -1) {
      clearInterval(this.shareCountdownTimer);
    }
    locationService.stopLocationUpdates();
  }

  initMap() {
    this.mapOption = {
      position: {
        target: { latitude: this.currentLat, longitude: this.currentLon },
        zoom: 15
      },
      scaleControlsEnabled: true,
      compassControlsEnabled: true
    };

    this.mapCallback = async (err, controller) => {
      if (!err && controller) {
        this.mapController = controller;
        controller.setMyLocationEnabled(true);
        controller.setMyLocationControlsEnabled(true);

        // 地图长按显示选择菜单
        controller.on('mapLongClick', (pos: mapCommon.LatLng) => {
          this.selectedMarkerLat = pos.latitude;
          this.selectedMarkerLon = pos.longitude;
          this.showLongPressMenu = true;
        });

        // 移动到当前位置
        try {
          const loc = await locationService.getCurrentPosition();
          if (loc) {
            this.currentLat = loc.latitude;
            this.currentLon = loc.longitude;
            const cameraUpdate = map.newCameraPosition({
              target: { latitude: loc.latitude, longitude: loc.longitude },
              zoom: 15
            });
            controller.animateCamera(cameraUpdate);
          }
        } catch (e) {
          console.warn('[OutdoorMainPage] Failed to get initial location');
        }
      }
    };
  }

  async initServices() {
    await databaseService.init(this.context);
    await this.loadData();

    trackingService.setStatusCallback((status) => {
      this.trackingStatus = status;
    });

    geofenceService.setEventCallback((event: GeofenceEvent) => {
      this.handleGeofenceEvent(event);
    });

    // 设置群组围栏事件回调
    geofenceService.setGroupGeofenceEventCallback((event: GroupGeofenceEvent) => {
      this.handleGroupGeofenceEvent(event);
    });

    await geofenceService.loadAllFences();
  }

  setupWSCallbacks() {
    wsService.setConnectionCallback((connected) => {
      this.isConnected = connected;
      if (!connected) {
        promptAction.showToast({ message: '连接已断开，正在重连...' });
      }
    });

    wsService.on('registerSuccess', (msg) => {
      this.groups = msg.groups as GroupInfo[];
      this.showSettings = false;
      promptAction.showToast({ message: '连接成功' });
    });

    wsService.on('createGroupSuccess', (msg) => {
      const group = msg.group as GroupInfo;
      this.groups.push(group);
      this.currentGroup = group;
      this.showCreateGroup = false;
      promptAction.showToast({ message: `群组已创建，邀请码: ${group.code}` });
      this.startLocationSharing();
    });

    wsService.on('joinGroupSuccess', (msg) => {
      const group = msg.group as GroupInfo;
      this.groups.push(group);
      this.currentGroup = group;
      this.showJoinGroup = false;
      promptAction.showToast({ message: `已加入群组: ${group.name}` });
      wsService.getGroupInfo(group.code);
      this.startLocationSharing();
    });

    wsService.on('joinGroupFailed', (msg) => {
      promptAction.showToast({ message: msg.reason as string });
    });

    wsService.on('groupInfo', (msg) => {
      if (msg.error) {
        return;
      }
      const groupData = msg.group as Object;
      if (groupData) {
        // 加载成员
        const members = (groupData as Record<string, Object>)['members'] as MemberInfo[];
        if (members) {
          this.members = members;
          this.renderMembersOnMap();
        }

        // 加载群组围栏
        const groupGeofences = (groupData as Record<string, Object>)['groupGeofences'] as GroupGeofenceData[];
        if (groupGeofences && this.currentGroup) {
          this.groupGeofences = groupGeofences.map((gf): GroupGeofence => ({
            id: gf.id,
            groupCode: this.currentGroup!.code,
            name: gf.name,
            latitude: gf.latitude,
            longitude: gf.longitude,
            radius: gf.radius,
            type: gf.type,
            creatorId: gf.creatorId || '',
            createTime: gf.createTime || Date.now()
          }));
          // 同步到 GeofenceService
          for (const fence of this.groupGeofences) {
            geofenceService.addGroupFence(this.currentGroup!.code, fence);
          }
          this.renderGroupFencesOnMap();
        }
      }
    });

    wsService.on('locationUpdate', (msg) => {
      const member = msg.member as MemberInfo;
      this.updateMemberLocation(member);
    });

    wsService.on('memberJoined', (msg) => {
      const member = msg.member as MemberInfo;
      this.members.push(member);
      promptAction.showToast({ message: `${member.name} 加入了群组` });
    });

    wsService.on('memberLeft', (msg) => {
      const odId = msg.odId as string;
      const name = msg.name as string;
      this.members = this.members.filter(m => m.odId !== odId);
      this.removeMemberMarker(odId);
      promptAction.showToast({ message: `${name} 离开了群组` });
    });

    wsService.on('sosAlert', (msg) => {
      // 解析最近轨迹数据
      let recentTrack: SOSTrackPoint[] | undefined = undefined;
      if (msg.recentTrack && Array.isArray(msg.recentTrack)) {
        recentTrack = (msg.recentTrack as Object[]).map((p: Object): SOSTrackPoint => {
          const point = p as Record<string, number>;
          return {
            latitude: point['latitude'] || 0,
            longitude: point['longitude'] || 0,
            altitude: point['altitude'] || 0,
            timestamp: point['timestamp'] || 0
          };
        });
      }

      this.sosAlert = {
        from: msg.from as SOSAlertFrom,
        location: msg.location as SOSAlertLocation,
        battery: msg.battery as number,
        message: msg.message as string,
        timestamp: msg.timestamp as number,
        recentTrack: recentTrack
      };
      this.showSOSAlert = true;
      if (this.mapController) {
        const cameraUpdate = map.newCameraPosition({
          target: this.sosAlert.location,
          zoom: 16
        });
        this.mapController.animateCamera(cameraUpdate);
      }
    });

    wsService.on('kicked', (msg) => {
      const groupName = msg.groupName as string;
      const groupCode = msg.groupCode as string;
      promptAction.showToast({ message: `你已被移出群组: ${groupName}` });
      if (groupCode) {
        geofenceService.clearGroupFences(groupCode);
      }
      this.clearGroupFences();
      this.currentGroup = null;
      this.members = [];
      this.clearAllMemberMarkers();
    });

    wsService.on('groupDisbanded', (msg) => {
      const groupCode = msg.groupCode as string;
      promptAction.showToast({ message: '群组已解散' });
      if (groupCode) {
        geofenceService.clearGroupFences(groupCode);
      }
      this.clearGroupFences();
      this.currentGroup = null;
      this.members = [];
      this.clearAllMemberMarkers();
    });

    // 位置共享过期回调
    wsService.on('shareExpired', (msg) => {
      const groupCode = msg.groupCode as string;
      if (this.currentGroup && this.currentGroup.code === groupCode) {
        this.isSharing = false;
        this.shareExpireTime = 0;
        this.shareRemainingTime = 0;
        this.stopShareCountdown();
        promptAction.showToast({ message: '位置共享已停止' });
      }
    });

    // 群组围栏添加成功回调
    wsService.on('addGroupGeofenceSuccess', (msg) => {
      const geofence = msg.geofence as GroupGeofenceData;
      promptAction.showToast({ message: `围栏 "${geofence.name}" 已添加` });
      this.showAddGroupFence = false;
      this.newGroupFenceName = '';
      this.newGroupFenceRadius = 100;
    });

    // 群组围栏添加失败回调
    wsService.on('addGroupGeofenceFailed', (msg) => {
      promptAction.showToast({ message: msg.reason as string || '添加围栏失败' });
    });

    // 群组围栏被添加（广播）
    wsService.on('groupGeofenceAdded', (msg) => {
      const geofence = msg.geofence as GroupGeofenceData;
      const groupCode = msg.groupCode as string;
      if (this.currentGroup && this.currentGroup.code === groupCode) {
        const newFence: GroupGeofence = {
          id: geofence.id,
          groupCode: groupCode,
          name: geofence.name,
          latitude: geofence.latitude,
          longitude: geofence.longitude,
          radius: geofence.radius,
          type: geofence.type,
          creatorId: geofence.creatorId || '',
          createTime: geofence.createTime || Date.now()
        };
        this.groupGeofences.push(newFence);
        geofenceService.addGroupFence(groupCode, newFence);
        this.renderGroupFencesOnMap();
      }
    });

    // 群组围栏删除成功回调
    wsService.on('removeGroupGeofenceSuccess', (msg) => {
      promptAction.showToast({ message: '围栏已删除' });
    });

    // 群组围栏删除失败回调
    wsService.on('removeGroupGeofenceFailed', (msg) => {
      promptAction.showToast({ message: msg.reason as string || '删除围栏失败' });
    });

    // 群组围栏被删除（广播）
    wsService.on('groupGeofenceRemoved', (msg) => {
      const fenceId = msg.fenceId as string;
      const fenceName = msg.fenceName as string;
      const groupCode = msg.groupCode as string;
      if (this.currentGroup && this.currentGroup.code === groupCode) {
        this.groupGeofences = this.groupGeofences.filter(f => f.id !== fenceId);
        geofenceService.removeGroupFence(groupCode, fenceId);
        this.renderGroupFencesOnMap();
        promptAction.showToast({ message: `围栏 "${fenceName}" 已被删除` });
      }
    });
    // 围栏事件通知
    wsService.on('geofenceEventNotification', (msg) => {
      const event = msg.geofenceEvent as GeofenceEventData;
      const action = event.event === 'enter' ? '进入' : '离开';
      promptAction.showToast({ message: `${event.memberName} ${action}了 "${event.fenceName}"` });
    });
  }

  async loadData() {
    this.tracks = await databaseService.getTracks();
    this.markers = await databaseService.getMarkers();
    this.geofences = await databaseService.getGeofences();
    await this.renderMarkersOnMap();
    await this.renderFencesOnMap();
  }

  handleGeofenceEvent(event: GeofenceEvent) {
    const fence = this.geofences.find(f => f.id === event.fenceId);
    const fenceName = fence?.name || '未知区域';
    const action = event.event === 'enter' ? '进入' : '离开';
    console.info(`[OutdoorMainPage] ${action}围栏: ${fenceName}`);
  }

  handleGroupGeofenceEvent(event: GroupGeofenceEvent) {
    // 发送围栏事件到服务器
    if (this.currentGroup) {
      wsService.notifyGeofenceEvent(this.currentGroup.code, {
        memberId: event.memberId,
        memberName: event.memberName,
        fenceId: event.fenceId,
        fenceName: event.fenceName,
        event: event.event,
        timestamp: event.timestamp
      });
    }
    console.info(`[OutdoorMainPage] 群组围栏事件: ${event.memberName} ${event.event} ${event.fenceName}`);
  }

  build() {
    Column() {
      // 主内容区
      Stack() {
        // 地图视图 - 使用 visibility 保持组件存活，避免重建导致 mapController 丢失
        Column() {
          this.buildMapView()
        }
        .width('100%')
        .height('100%')
        .visibility(this.currentTab === 'map' ? Visibility.Visible : Visibility.Hidden)

        // 活动视图
        if (this.currentTab === 'activity') {
          this.buildActivityView()
        }

        // 群组视图
        if (this.currentTab === 'group') {
          this.buildGroupView()
        }

        // 个人视图
        if (this.currentTab === 'profile') {
          this.buildProfileView()
        }

        // SOS按钮（始终显示）
        this.buildSOSButton()

        // 弹窗层
        if (this.showAddMarker) {
          this.buildAddMarkerDialog()
        }
        if (this.showAddFence) {
          this.buildAddFenceDialog()
        }
        if (this.showSOS) {
          this.buildSOSDialog()
        }
        if (this.showSettings) {
          this.buildSettingsDialog()
        }
        if (this.showCreateGroup) {
          this.buildCreateGroupDialog()
        }
        if (this.showJoinGroup) {
          this.buildJoinGroupDialog()
        }
        if (this.showSOSAlert && this.sosAlert) {
          this.buildSOSAlertDialog()
        }
        if (this.showShareDurationDialog) {
          this.buildShareDurationDialog()
        }
        if (this.showAddGroupFence) {
          this.buildAddGroupFenceDialog()
        }
        if (this.showGroupFenceList) {
          this.buildGroupFenceListDialog()
        }
        if (this.showLongPressMenu) {
          this.buildLongPressMenuDialog()
        }
      }
      .layoutWeight(1)

      // 底部Tab栏
      this.buildTabBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .onAppear(() => this.reqPermissions())
  }

  // ========== 地图Tab视图 ==========
  @Builder
  buildMapView() {
    Stack({ alignContent: Alignment.TopStart }) {
      MapComponent({
        mapOptions: this.mapOption,
        mapCallback: this.mapCallback
      })
        .width('100%')
        .height('100%')

      // 顶部工具栏
      Row({ space: 8 }) {
        Button('标记')
          .fontSize(13)
          .height(32)
          .backgroundColor('#4CAF50')
          .onClick(() => {
            this.selectedMarkerLat = this.currentLat;
            this.selectedMarkerLon = this.currentLon;
            this.showAddMarker = true;
          })

        Button('围栏')
          .fontSize(13)
          .height(32)
          .backgroundColor('#FF9800')
          .onClick(() => {
            this.selectedMarkerLat = this.currentLat;
            this.selectedMarkerLon = this.currentLon;
            this.showAddFence = true;
          })

        // 群组围栏按钮（仅当已加入群组且是管理员时显示）
        if (this.currentGroup && this.currentGroup.isOwner) {
          Button('群组围栏')
            .fontSize(13)
            .height(32)
            .backgroundColor('#9C27B0')
            .onClick(() => {
              this.selectedMarkerLat = this.currentLat;
              this.selectedMarkerLon = this.currentLon;
              this.showAddGroupFence = true;
            })
        }

        Button(this.trackingStatus.isRecording ? '停止记录' : '开始记录')
          .fontSize(13)
          .height(32)
          .backgroundColor(this.trackingStatus.isRecording ? '#F44336' : '#2196F3')
          .onClick(() => this.toggleTracking())
      }
      .padding({ top: 50, left: 12, right: 12 })

      // 轨迹记录状态面板
      if (this.trackingStatus.isRecording) {
        this.buildTrackingPanel()
      }

      // 群组成员位置显示（如果已加入群组）
      if (this.currentGroup && this.members.length > 0) {
        this.buildMemberChips()
      }

      // 定位按钮
      Button() {
        Image($r('sys.media.ohos_ic_public_location'))
          .width(24)
          .height(24)
          .fillColor('#007DFF')
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.White)
      .borderRadius(22)
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.15)' })
      .position({ x: '100%', y: '50%' })
      .translate({ x: -60 })
      .onClick(() => this.moveToCurrentLocation())
    }
  }

  @Builder
  buildTrackingPanel() {
    Column() {
      Row({ space: 16 }) {
        Column() {
          Text(this.formatDistance(this.trackingStatus.distance)).fontSize(20).fontWeight(FontWeight.Bold)
          Text('距离').fontSize(11).fontColor('#666')
        }

        Column() {
          Text(this.formatDuration(this.trackingStatus.duration)).fontSize(20).fontWeight(FontWeight.Bold)
          Text('时长').fontSize(11).fontColor('#666')
        }

        Column() {
          Text(`${this.trackingStatus.pointCount}`).fontSize(20).fontWeight(FontWeight.Bold)
          Text('点数').fontSize(11).fontColor('#666')
        }
      }

      Row({ space: 12 }) {
        Button(this.trackingStatus.isPaused ? '继续' : '暂停')
          .fontSize(13)
          .height(32)
          .backgroundColor('#FF9800')
          .onClick(() => {
            if (this.trackingStatus.isPaused) {
              trackingService.resumeRecording();
            } else {
              trackingService.pauseRecording();
            }
          })

        Button('停止')
          .fontSize(13)
          .height(32)
          .backgroundColor('#F44336')
          .onClick(() => this.stopTracking())
      }
      .margin({ top: 8 })
    }
    .padding(12)
    .backgroundColor('rgba(255,255,255,0.95)')
    .borderRadius(12)
    .position({ x: 12, y: 110 })
  }

  @Builder
  buildMemberChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.members, (member: MemberInfo) => {
          Column() {
            Stack() {
              Text(member.name.charAt(0))
                .fontSize(14)
                .fontColor(Color.White)
                .width(36)
                .height(36)
                .textAlign(TextAlign.Center)
                .backgroundColor(member.odId === wsService.getOdId() ? '#FF9800' : '#007DFF')
                .borderRadius(18)
              Circle()
                .width(8)
                .height(8)
                .fill(member.isOnline ? '#4CAF50' : '#999')
                .position({ x: 26, y: 26 })
            }

            Text(member.name)
              .fontSize(10)
              .fontColor('#333')
              .maxLines(1)
          }
          .onClick(() => this.locateMember(member))
        })
      }
      .padding({ left: 12, right: 12 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .width('100%')
    .height(60)
    .position({ x: 0, y: '100%' })
    .translate({ y: -80 })
    .backgroundColor('rgba(255,255,255,0.9)')
  }

  // ========== 活动Tab视图 ==========
  @Builder
  buildActivityView() {
    Column() {
      Row() {
        Text('我的轨迹').fontSize(20).fontWeight(FontWeight.Bold)
        Blank()
        Text(`共 ${this.tracks.length} 条`).fontSize(14).fontColor('#999')
      }
      .width('100%')
      .padding({
        top: 50,
        left: 16,
        right: 16,
        bottom: 12
      })
      .backgroundColor(Color.White)

      if (this.tracks.length === 0) {
        Column() {
          Text('📍').fontSize(48)
          Text('暂无轨迹记录').fontSize(16).fontColor('#999').margin({ top: 12 })
          Text('点击地图页的"开始记录"按钮').fontSize(13).fontColor('#BBB').margin({ top: 4 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.tracks, (track: Track) => {
            ListItem() {
              this.buildTrackItem(track)
            }
          })
        }
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  buildTrackItem(track: Track) {
    Column() {
      Row() {
        Column() {
          Text(track.name).fontSize(16).fontWeight(FontWeight.Medium)
          Text(this.formatDate(track.startTime)).fontSize(12).fontColor('#999').margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text(this.formatDistance(track.distance)).fontSize(16).fontColor('#007DFF')
          Text(this.formatDuration(track.duration)).fontSize(12).fontColor('#999').margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.End)
      }

      Row({ space: 8 }) {
        Button('回放')
          .fontSize(12)
          .height(28)
          .backgroundColor('#E3F2FD')
          .fontColor('#2196F3')
          .onClick(() => this.playbackTrack(track))
        Button('GPX')
          .fontSize(12)
          .height(28)
          .backgroundColor('#E8F5E9')
          .fontColor('#4CAF50')
          .onClick(() => this.exportTrack(track, 'gpx'))
        Button('KML')
          .fontSize(12)
          .height(28)
          .backgroundColor('#FFF3E0')
          .fontColor('#FF9800')
          .onClick(() => this.exportTrack(track, 'kml'))
        Button('删除')
          .fontSize(12)
          .height(28)
          .backgroundColor('#FFEBEE')
          .fontColor('#F44336')
          .onClick(() => this.deleteTrack(track))
      }
      .width('100%')
      .margin({ top: 8 })
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  // ========== 群组Tab视图 ==========
  @Builder
  buildGroupView() {
    Column() {
      // 顶部状态栏
      Row() {
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
        if (this.currentGroup) {
          Text(`${this.currentGroup.name} (${this.currentGroup.code})`)
            .fontSize(14)
            .fontColor('#333')
        }
        Blank()
        Button('设置')
          .fontSize(12)
          .height(32)
          .backgroundColor('#F5F5F5')
          .fontColor('#666')
          .onClick(() => this.showSettings = true)
      }
      .width('100%')
      .padding({
        top: 50,
        left: 16,
        right: 16,
        bottom: 12
      })
      .backgroundColor(Color.White)

      // 主内容
      if (!this.isConnected) {
        // 未连接状态 - 显示引导
        this.buildGroupGuide()
      } else if (!this.currentGroup) {
        // 已连接但未加入群组
        this.buildNoGroupView()
      } else {
        // 已加入群组 - 显示成员列表
        this.buildGroupMemberList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  buildGroupGuide() {
    Column() {
      Text('👥').fontSize(64)
      Text('实时群组').fontSize(20).fontWeight(FontWeight.Bold).margin({ top: 16 })
      Text('与家人朋友共享位置，确保户外安全').fontSize(14).fontColor('#666').margin({ top: 8 })

      Button('连接服务器')
        .width('80%')
        .height(48)
        .backgroundColor('#007DFF')
        .margin({ top: 32 })
        .onClick(() => this.showSettings = true)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildNoGroupView() {
    Column() {
      Text('🏕️').fontSize(64)
      Text('还没有加入群组').fontSize(18).fontColor('#666').margin({ top: 16 })
      Text('创建或加入一个群组开始位置共享').fontSize(14).fontColor('#999').margin({ top: 8 })

      Row({ space: 16 }) {
        Button('创建群组')
          .width(140)
          .height(48)
          .backgroundColor('#4CAF50')
          .onClick(() => this.showCreateGroup = true)

        Button('加入群组')
          .width(140)
          .height(48)
          .backgroundColor('#2196F3')
          .onClick(() => this.showJoinGroup = true)
      }
      .margin({ top: 32 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildGroupMemberList() {
    Column() {
      // 位置共享状态栏
      this.buildShareStatusBar()

      // 成员列表
      List() {
        ForEach(this.members, (member: MemberInfo) => {
          ListItem() {
            this.buildMemberCard(member)
          }
        })
      }
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8 })

      // 群组围栏快捷入口
      if (this.groupGeofences.length > 0 || this.currentGroup?.isOwner) {
        Row() {
          Text('🟣').fontSize(18).margin({ right: 8 })
          Text('群组围栏').fontSize(14).fontColor('#9C27B0').layoutWeight(1)
          Text(`${this.groupGeofences.length} 个`).fontSize(13).fontColor('#999')
          Image($r('sys.media.ohos_ic_public_arrow_right'))
            .width(16)
            .height(16)
            .fillColor('#CCC')
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 12,
          bottom: 12
        })
        .backgroundColor(Color.White)
        .margin({ bottom: 8 })
        .onClick(() => {
          if (this.groupGeofences.length > 0) {
            this.showGroupFenceList = true;
          } else if (this.currentGroup?.isOwner) {
            this.selectedMarkerLat = this.currentLat;
            this.selectedMarkerLon = this.currentLon;
            this.showAddGroupFence = true;
          }
        })
      }

      // 底部操作栏
      Row({ space: 12 }) {
        Button('邀请码: ' + this.currentGroup?.code)
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
      .width('100%')
      .padding(12)
      .backgroundColor(Color.White)
    }
    .layoutWeight(1)
  }

  // 位置共享状态栏
  @Builder
  buildShareStatusBar() {
    Row() {
      // 共享状态图标和文字
      Row({ space: 8 }) {
        Circle()
          .width(10)
          .height(10)
          .fill(this.isSharing ? '#4CAF50' : '#999')
        Text(this.isSharing ? '正在共享位置' : '位置共享已停止')
          .fontSize(14)
          .fontColor(this.isSharing ? '#4CAF50' : '#666')
      }

      Blank()

      // 剩余时间显示（仅当有限时共享时显示）
      if (this.isSharing && this.shareExpireTime > 0) {
        Text(this.formatShareRemainingTime())
          .fontSize(13)
          .fontColor('#FF9800')
          .margin({ right: 8 })
      }

      // 共享控制按钮
      if (this.isSharing) {
        Button('停止共享')
          .fontSize(12)
          .height(32)
          .backgroundColor('#FFEBEE')
          .fontColor('#F44336')
          .onClick(() => this.stopLocationSharingWithConfirm())
      } else {
        Button('开始共享')
          .fontSize(12)
          .height(32)
          .backgroundColor('#E8F5E9')
          .fontColor('#4CAF50')
          .onClick(() => this.showShareDurationDialog = true)
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 12,
      bottom: 12
    })
    .backgroundColor(Color.White)
    .margin({ bottom: 8 })
  }

  @Builder
  buildMemberCard(member: MemberInfo) {
    Row() {
      Stack() {
        Text(member.name.charAt(0))
          .fontSize(18)
          .fontColor(Color.White)
          .width(48)
          .height(48)
          .textAlign(TextAlign.Center)
          .backgroundColor(member.odId === wsService.getOdId() ? '#FF9800' : '#007DFF')
          .borderRadius(24)
        Circle()
          .width(12)
          .height(12)
          .fill(member.isOnline ? '#4CAF50' : '#999')
          .position({ x: 36, y: 36 })
      }

      Column() {
        Text(member.name + (member.odId === wsService.getOdId() ? ' (我)' : ''))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Text(this.formatTimeAgo(member.lastUpdate))
          .fontSize(12)
          .fontColor('#999')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      Column() {
        Text(`🔋${member.battery}%`)
          .fontSize(13)
          .fontColor(member.battery < 20 ? '#F44336' : '#666')
        if (!member.isOnline) {
          Text('可能离线')
            .fontSize(11)
            .fontColor('#FF9800')
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.locateMember(member);
      this.currentTab = 'map';
    })
  }

  // ========== 我的Tab视图 ==========
  @Builder
  buildProfileView() {
    Column() {
      // 用户信息
      Row() {
        Text('我')
          .fontSize(24)
          .fontColor(Color.White)
          .width(60)
          .height(60)
          .textAlign(TextAlign.Center)
          .backgroundColor('#007DFF')
          .borderRadius(30)

        Column() {
          Text(this.userName || '户外探险者').fontSize(18).fontWeight(FontWeight.Bold)
          Text('ID: ' + (wsService.getOdId() || '未连接')).fontSize(13).fontColor('#999').margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 16 })
      }
      .width('100%')
      .padding({
        top: 60,
        left: 20,
        right: 20,
        bottom: 20
      })
      .backgroundColor(Color.White)

      // 统计数据
      Row() {
        Column() {
          Text(`${this.tracks.length}`).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#007DFF')
          Text('轨迹数').fontSize(12).fontColor('#666').margin({ top: 4 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.formatTotalDistance()).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
          Text('总里程').fontSize(12).fontColor('#666').margin({ top: 4 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.formatTotalDuration()).fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FF9800')
          Text('总时长').fontSize(12).fontColor('#666').margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding(20)
      .margin({ top: 12 })
      .backgroundColor(Color.White)

      // 功能列表
      Column() {
        this.buildMenuItem('📍', '我的标记', `${this.markers.length} 个`, () => {
        })
        this.buildMenuItem('🔔', '电子围栏', `${this.geofences.length} 个`, () => {
        })
        this.buildMenuItem('📊', '运动统计', '', () => {
        })
        this.buildMenuItem('⚙️', '设置', '', () => {
        })
        this.buildMenuItem('❓', '帮助与反馈', '', () => {
        })
      }
      .margin({ top: 12 })
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  buildMenuItem(icon: string, title: string, value: string, onClick: () => void) {
    Row() {
      Text(icon).fontSize(20).margin({ right: 12 })
      Text(title).fontSize(15).layoutWeight(1)
      if (value) {
        Text(value).fontSize(14).fontColor('#999')
      }
      Image($r('sys.media.ohos_ic_public_arrow_right'))
        .width(16)
        .height(16)
        .fillColor('#CCC')
        .margin({ left: 8 })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(onClick)
  }

  // ========== SOS按钮 ==========
  @Builder
  buildSOSButton() {
    Button('SOS')
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .width(56)
      .height(56)
      .backgroundColor('#F44336')
      .borderRadius(28)
      .shadow({ radius: 8, color: 'rgba(244,67,54,0.4)' })
      .position({ x: '100%', y: '100%' })
      .translate({ x: -72, y: -160 })
      .gesture(
        LongPressGesture({ repeat: false, duration: 1000 })
          .onAction(() => {
            this.showSOS = true;
            this.sosCountdown = 5;
            this.startSOSCountdown();
          })
      )
  }

  // ========== 底部Tab栏 ==========
  @Builder
  buildTabBar() {
    Row() {
      this.buildTabItem('map', '地图', $r('sys.media.ohos_ic_public_location'))
      this.buildTabItem('activity', '活动', $r('sys.media.ohos_ic_public_clock'))
      this.buildTabItem('group', '群组', $r('sys.media.ohos_ic_public_location'))
      this.buildTabItem('profile', '我的', $r('sys.media.ohos_ic_public_location'))
    }
    .width('100%')
    .height(56)
    .backgroundColor(Color.White)
    .justifyContent(FlexAlign.SpaceAround)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)', offsetY: -2 })
  }

  @Builder
  buildTabItem(tab: TabType, title: string, icon: Resource) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentTab === tab ? '#007DFF' : '#999')
      Text(title)
        .fontSize(11)
        .fontColor(this.currentTab === tab ? '#007DFF' : '#999')
        .margin({ top: 2 })
    }
    .onClick(() => this.currentTab = tab)
  }

  // ========== 弹窗 ==========
  @Builder
  buildAddMarkerDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showAddMarker = false)

      Column() {
        Text('添加标记').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 16 })

        TextInput({ placeholder: '标记名称' })
          .width('100%')
          .height(44)
          .margin({ bottom: 12 })
          .onChange((v) => this.newMarkerName = v)

        TextInput({ placeholder: '备注说明（可选）' })
          .width('100%')
          .height(44)
          .margin({ bottom: 12 })
          .onChange((v) => this.newMarkerDesc = v)

        Text('标记类型').fontSize(14).fontColor('#666').margin({ bottom: 8 })
        Row({ space: 8 }) {
          ForEach(this.markerTypes, (type: MarkerType) => {
            Column() {
              Text(type.icon).fontSize(24)
              Text(type.name).fontSize(11).fontColor(this.newMarkerType === type.key ? '#007DFF' : '#666')
            }
            .padding(8)
            .backgroundColor(this.newMarkerType === type.key ? '#E3F2FD' : '#F5F5F5')
            .borderRadius(8)
            .onClick(() => this.newMarkerType = type.key)
          })
        }
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showAddMarker = false)

          Button('确定')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#007DFF')
            .onClick(() => this.addMarker())
        }
      }
      .width('90%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '5%', y: '30%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildAddFenceDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showAddFence = false)

      Column() {
        Text('添加电子围栏').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 16 })

        TextInput({ placeholder: '围栏名称（如：营地安全区）' })
          .width('100%')
          .height(44)
          .margin({ bottom: 12 })
          .onChange((v) => this.newFenceName = v)

        Text('围栏半径').fontSize(14).fontColor('#666').margin({ bottom: 8 })
        Row({ space: 8 }) {
          ForEach([50, 100, 200, 500], (r: number) => {
            Button(`${r}m`)
              .fontSize(13)
              .height(32)
              .backgroundColor(this.newFenceRadius === r ? '#007DFF' : '#F5F5F5')
              .fontColor(this.newFenceRadius === r ? Color.White : '#666')
              .onClick(() => this.newFenceRadius = r)
          })
        }
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showAddFence = false)

          Button('确定')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#FF9800')
            .onClick(() => this.addFence())
        }
      }
      .width('90%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '5%', y: '30%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSOSDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.7)')

      Column() {
        Text('🆘').fontSize(48)
        Text('紧急求助').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F44336').margin({ top: 12 })

        if (this.sosCountdown > 0) {
          Text(`${this.sosCountdown} 秒后发送求助信息`)
            .fontSize(16)
            .fontColor('#666')
            .margin({ top: 16 })
          Text('点击取消可停止发送')
            .fontSize(13)
            .fontColor('#999')
            .margin({ top: 8 })
        } else {
          Text('正在发送求助信息...')
            .fontSize(16)
            .fontColor('#F44336')
            .margin({ top: 16 })
        }

        TextInput({ placeholder: '附加消息（可选）' })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((v) => this.sosMessage = v)

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => {
              this.showSOS = false;
              this.sosCountdown = 0;
            })

          Button('立即发送')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F44336')
            .onClick(() => this.sendSOS())
        }
        .margin({ top: 20 })
      }
      .width('90%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '5%', y: '25%' })
    }
    .width('100%')
    .height('100%')
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

          Button('关闭')
            .width('100%')
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .margin({ top: 8 })
            .onClick(() => this.showSettings = false)
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

        // 基本信息区域
        Column() {
          Text(`📍 位置: ${this.sosAlert?.location.latitude.toFixed(6)}, ${this.sosAlert?.location.longitude.toFixed(6)}`)
            .fontSize(13)
            .fontColor('#666')
          Text(`🔋 电量: ${this.sosAlert?.battery}%`)
            .fontSize(13)
            .fontColor(this.sosAlert && this.sosAlert.battery < 20 ? '#F44336' : '#666')
            .margin({ top: 4 })
          Text(`⏰ 时间: ${this.sosAlert ? this.formatSOSTime(this.sosAlert.timestamp) : ''}`)
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

        // 最近轨迹区域（如果有）
        if (this.sosAlert?.recentTrack && this.sosAlert.recentTrack.length > 0) {
          Column() {
            Text('📌 最近轨迹片段')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333')
              .margin({ bottom: 8 })

            // 显示最近3个轨迹点
            ForEach(this.sosAlert.recentTrack.slice(-3), (point: SOSTrackPoint, index: number) => {
              Row() {
                Text(`${index + 1}.`)
                  .fontSize(12)
                  .fontColor('#999')
                  .width(20)
                Text(`${point.latitude.toFixed(6)}, ${point.longitude.toFixed(6)}`)
                  .fontSize(12)
                  .fontColor('#666')
                  .layoutWeight(1)
                Text(this.formatSOSTrackTime(point.timestamp))
                  .fontSize(11)
                  .fontColor('#999')
              }
              .width('100%')
              .margin({ top: index > 0 ? 4 : 0 })
            })

            Text(`共 ${this.sosAlert.recentTrack.length} 个轨迹点`)
              .fontSize(11)
              .fontColor('#999')
              .margin({ top: 8 })
          }
          .margin({ top: 12 })
          .padding(12)
          .backgroundColor('#E3F2FD')
          .borderRadius(8)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        Row({ space: 12 }) {
          Button('关闭')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => {
              this.showSOSAlert = false;
            })

          Button('查看位置')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F44336')
            .onClick(() => {
              this.showSOSAlert = false;
              if (this.sosAlert && this.mapController) {
                const cameraUpdate = map.newCameraPosition({
                  target: this.sosAlert.location,
                  zoom: 17
                });
                this.mapController.animateCamera(cameraUpdate);
              }
              this.currentTab = 'map';
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('85%')
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '7.5%', y: '15%' })
    }
    .width('100%')
    .height('100%')
  }

  // 共享时长选择弹窗
  @Builder
  buildShareDurationDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showShareDurationDialog = false)

      Column() {
        Text('选择共享时长').fontSize(18).fontWeight(FontWeight.Bold)
        Text('设置位置共享的持续时间').fontSize(13).fontColor('#666').margin({ top: 4 })

        Column({ space: 8 }) {
          ForEach(this.shareDurationOptions, (option: ShareDurationOption) => {
            Row() {
              Column() {
                Text(option.name)
                  .fontSize(16)
                  .fontColor(this.shareDuration === option.key ? '#007DFF' : '#333')
                Text(option.description)
                  .fontSize(12)
                  .fontColor('#999')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.shareDuration === option.key) {
                Image($r('sys.media.ohos_ic_public_ok'))
                  .width(20)
                  .height(20)
                  .fillColor('#007DFF')
              }
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.shareDuration === option.key ? '#E3F2FD' : '#F5F5F5')
            .borderRadius(8)
            .onClick(() => this.shareDuration = option.key)
          })
        }
        .margin({ top: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showShareDurationDialog = false)

          Button('开始共享')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#4CAF50')
            .onClick(() => {
              this.showShareDurationDialog = false;
              this.startLocationSharingWithDuration(this.shareDuration);
            })
        }
        .margin({ top: 20 })
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

  // 添加群组围栏弹窗
  @Builder
  buildAddGroupFenceDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showAddGroupFence = false)

      Column() {
        Text('添加群组围栏').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
        Text('群组围栏对所有成员可见').fontSize(12).fontColor('#666').margin({ bottom: 16 })

        TextInput({ placeholder: '围栏名称（如：集合点安全区）' })
          .width('100%')
          .height(44)
          .margin({ bottom: 12 })
          .onChange((v) => this.newGroupFenceName = v)

        Text('围栏半径').fontSize(14).fontColor('#666').margin({ bottom: 8 })
        Row({ space: 8 }) {
          ForEach([50, 100, 200, 500], (r: number) => {
            Button(`${r}m`)
              .fontSize(13)
              .height(32)
              .backgroundColor(this.newGroupFenceRadius === r ? '#9C27B0' : '#F5F5F5')
              .fontColor(this.newGroupFenceRadius === r ? Color.White : '#666')
              .onClick(() => this.newGroupFenceRadius = r)
          })
        }
        .margin({ bottom: 12 })

        Text('围栏类型').fontSize(14).fontColor('#666').margin({ bottom: 8 })
        Row({ space: 12 }) {
          Column() {
            Text('🟢').fontSize(24)
            Text('安全区').fontSize(12).fontColor(this.newGroupFenceType === 'safe' ? '#4CAF50' : '#666')
          }
          .padding(12)
          .backgroundColor(this.newGroupFenceType === 'safe' ? '#E8F5E9' : '#F5F5F5')
          .borderRadius(8)
          .onClick(() => this.newGroupFenceType = 'safe')

          Column() {
            Text('🟠').fontSize(24)
            Text('警告区').fontSize(12).fontColor(this.newGroupFenceType === 'warning' ? '#FF9800' : '#666')
          }
          .padding(12)
          .backgroundColor(this.newGroupFenceType === 'warning' ? '#FFF3E0' : '#F5F5F5')
          .borderRadius(8)
          .onClick(() => this.newGroupFenceType = 'warning')
        }
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showAddGroupFence = false)

          Button('确定')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#9C27B0')
            .onClick(() => this.addGroupFence())
        }

        // 查看围栏列表按钮
        if (this.groupGeofences.length > 0) {
          Button(`查看围栏列表 (${this.groupGeofences.length})`)
            .width('100%')
            .height(40)
            .backgroundColor('#F5F5F5')
            .fontColor('#9C27B0')
            .margin({ top: 12 })
            .onClick(() => {
              this.showAddGroupFence = false;
              this.showGroupFenceList = true;
            })
        }
      }
      .width('90%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '5%', y: '20%' })
    }
    .width('100%')
    .height('100%')
  }

  // 群组围栏列表弹窗
  @Builder
  buildGroupFenceListDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showGroupFenceList = false)

      Column() {
        Row() {
          Text('群组围栏列表').fontSize(18).fontWeight(FontWeight.Bold)
          Blank()
          Text(`共 ${this.groupGeofences.length} 个`).fontSize(13).fontColor('#999')
        }
        .width('100%')
        .margin({ bottom: 16 })

        if (this.groupGeofences.length === 0) {
          Column() {
            Text('🔲').fontSize(48)
            Text('暂无群组围栏').fontSize(14).fontColor('#999').margin({ top: 8 })
          }
          .width('100%')
          .padding(32)
        } else {
          List() {
            ForEach(this.groupGeofences, (fence: GroupGeofence) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(fence.type === 'safe' ? '🟢' : '🟠').fontSize(20)
                  }
                  .margin({ right: 12 })

                  Column() {
                    Text(fence.name).fontSize(15).fontWeight(FontWeight.Medium)
                    Text(`半径: ${fence.radius}m`).fontSize(12).fontColor('#999').margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // 仅管理员可删除
                  if (this.currentGroup?.isOwner) {
                    Button('删除')
                      .fontSize(12)
                      .height(28)
                      .backgroundColor('#FFEBEE')
                      .fontColor('#F44336')
                      .onClick(() => this.deleteGroupFence(fence))
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor('#F9F9F9')
                .borderRadius(8)
                .margin({ bottom: 8 })
                .onClick(() => this.locateGroupFence(fence))
              }
            })
          }
          .width('100%')
          .height(200)
        }

        Row({ space: 12 }) {
          // 管理员可添加新围栏
          if (this.currentGroup?.isOwner) {
            Button('添加围栏')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#9C27B0')
              .onClick(() => {
                this.showGroupFenceList = false;
                this.selectedMarkerLat = this.currentLat;
                this.selectedMarkerLon = this.currentLon;
                this.showAddGroupFence = true;
              })
          }

          Button('关闭')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
            .onClick(() => this.showGroupFenceList = false)
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('90%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '5%', y: '20%' })
    }
    .width('100%')
    .height('100%')
  }

  // 长按地图选择菜单弹窗
  @Builder
  buildLongPressMenuDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showLongPressMenu = false)

      Column() {
        Text('选择操作').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 16 })

        // 添加标记选项
        Row() {
          Text('📍').fontSize(24).margin({ right: 12 })
          Column() {
            Text('添加标记').fontSize(16)
            Text('标注水源、营地、危险区等').fontSize(12).fontColor('#999').margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.showLongPressMenu = false;
          this.showAddMarker = true;
        })

        // 添加个人围栏选项
        Row() {
          Text('🔔').fontSize(24).margin({ right: 12 })
          Column() {
            Text('添加个人围栏').fontSize(16)
            Text('设置个人安全区域提醒').fontSize(12).fontColor('#999').margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.showLongPressMenu = false;
          this.showAddFence = true;
        })

        // 添加群组围栏选项（仅当已加入群组且是管理员时显示）
        if (this.currentGroup && this.currentGroup.isOwner) {
          Row() {
            Text('🟣').fontSize(24).margin({ right: 12 })
            Column() {
              Text('添加群组围栏').fontSize(16).fontColor('#9C27B0')
              Text('群组成员进出时收到通知').fontSize(12).fontColor('#999').margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#F3E5F5')
          .borderRadius(8)
          .margin({ bottom: 8 })
          .onClick(() => {
            this.showLongPressMenu = false;
            this.showAddGroupFence = true;
          })
        } else if (this.currentGroup && !this.currentGroup.isOwner) {
          // 非管理员提示
          Row() {
            Text('🟣').fontSize(24).margin({ right: 12 }).opacity(0.5)
            Column() {
              Text('添加群组围栏').fontSize(16).fontColor('#999')
              Text('需要管理员权限').fontSize(12).fontColor('#FF9800').margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .margin({ bottom: 8 })
          .opacity(0.6)
        }

        Button('取消')
          .width('100%')
          .height(44)
          .backgroundColor('#F5F5F5')
          .fontColor('#666')
          .margin({ top: 8 })
          .onClick(() => this.showLongPressMenu = false)
      }
      .width('85%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .position({ x: '7.5%', y: '30%' })
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
    promptAction.showToast({ message: `正在连接 ${url}...` });

    try {
      const success = await wsService.connect(url);
      if (!success) {
        promptAction.showToast({ message: '连接失败，请检查网络和服务器' });
      }
    } catch (e) {
      promptAction.showToast({ message: '连接异常' });
    }
  }

  startLocationSharing() {
    // 默认使用持续共享
    this.startLocationSharingWithDuration('always');
  }

  /**
   * 使用指定时长开始位置共享
   * @param duration 共享时长
   */
  startLocationSharingWithDuration(duration: ShareDuration) {
    if (!this.currentGroup) {
      promptAction.showToast({ message: '请先加入群组' });
      return;
    }

    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
    }

    // 使用 WebSocketService 的共享控制方法
    this.shareExpireTime = wsService.startLocationSharing(this.currentGroup.code, duration);
    this.shareDuration = duration;
    this.isSharing = true;

    // 启动位置更新定时器
    this.locationTimer = setInterval(async () => {
      if (!this.currentGroup || !this.isConnected) {
        return;
      }

      // 使用带过期检查的位置更新方法
      const loc = await locationService.getCurrentPosition();
      if (loc) {
        this.currentLat = loc.latitude;
        this.currentLon = loc.longitude;
        const sent = wsService.updateLocationWithExpiryCheck(
          this.currentGroup.code,
          loc.latitude,
          loc.longitude
        );

        // 如果位置更新被跳过（共享已过期），停止共享
        if (!sent) {
          this.handleShareExpired();
        }
      }
    }, 5000);

    // 启动倒计时显示（仅当有限时共享时）
    if (this.shareExpireTime > 0) {
      this.startShareCountdown();
    }

    this.uploadLocationNow();

    // 显示提示
    const durationText = this.getDurationText(duration);
    promptAction.showToast({ message: `位置共享已开启 (${durationText})` });
  }

  /**
   * 停止位置共享（带确认）
   */
  stopLocationSharingWithConfirm() {
    if (!this.currentGroup) {
      return;
    }

    // 直接停止，不需要确认
    this.stopLocationSharingInternal();
    promptAction.showToast({ message: '位置共享已停止' });
  }

  /**
   * 内部停止位置共享方法
   */
  private stopLocationSharingInternal() {
    if (this.currentGroup) {
      wsService.stopLocationSharing(this.currentGroup.code);
    }

    this.isSharing = false;
    this.shareExpireTime = 0;
    this.shareRemainingTime = 0;

    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
      this.locationTimer = -1;
    }

    this.stopShareCountdown();
  }

  /**
   * 处理共享过期
   */
  private handleShareExpired() {
    this.isSharing = false;
    this.shareExpireTime = 0;
    this.shareRemainingTime = 0;

    if (this.locationTimer !== -1) {
      clearInterval(this.locationTimer);
      this.locationTimer = -1;
    }

    this.stopShareCountdown();
    promptAction.showToast({ message: '位置共享已停止' });
  }

  /**
   * 启动共享倒计时显示
   */
  private startShareCountdown() {
    this.stopShareCountdown();

    this.shareCountdownTimer = setInterval(() => {
      if (this.shareExpireTime > 0) {
        this.shareRemainingTime = this.shareExpireTime - Date.now();
        if (this.shareRemainingTime <= 0) {
          this.handleShareExpired();
        }
      }
    }, 1000);
  }

  /**
   * 停止共享倒计时显示
   */
  private stopShareCountdown() {
    if (this.shareCountdownTimer !== -1) {
      clearInterval(this.shareCountdownTimer);
      this.shareCountdownTimer = -1;
    }
  }

  /**
   * 格式化共享剩余时间
   */
  formatShareRemainingTime(): string {
    if (this.shareRemainingTime <= 0) {
      return '';
    }

    const totalSeconds = Math.floor(this.shareRemainingTime / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
      return `剩余 ${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
    return `剩余 ${minutes}:${seconds.toString().padStart(2, '0')}`;
  }

  /**
   * 获取时长文本描述
   */
  getDurationText(duration: ShareDuration): string {
    const option = this.shareDurationOptions.find(o => o.key === duration);
    return option?.name || '持续共享';
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

    // 先停止位置共享
    if (this.isSharing) {
      this.stopLocationSharingInternal();
    }

    // 清除群组围栏
    geofenceService.clearGroupFences(this.currentGroup.code);
    this.clearGroupFences();

    wsService.leaveGroup(this.currentGroup.code);
    this.groups = this.groups.filter(g => g.code !== this.currentGroup?.code);
    this.currentGroup = null;
    this.members = [];
    this.clearAllMemberMarkers();
  }

  async toggleTracking() {
    if (this.trackingStatus.isRecording) {
      await this.stopTracking();
    } else {
      const name = `轨迹_${this.formatDate(Date.now())}`;
      const trackId = await trackingService.startRecording(name);
      if (trackId > 0) {
        promptAction.showToast({ message: '开始记录轨迹' });
        // 隐藏系统蓝点，避免与轨迹位置偏差
        if (this.mapController) {
          this.mapController.setMyLocationEnabled(false);
        }
        this.startDurationTimer();
      } else {
        promptAction.showToast({ message: '启动记录失败' });
      }
    }
  }

  startDurationTimer() {
    if (this.durationTimer !== -1) {
      clearInterval(this.durationTimer);
    }
    this.durationTimer = setInterval(() => {
      if (this.trackingStatus.isRecording) {
        this.trackingStatus = trackingService.getStatus();
        // 实时更新轨迹显示（使用轨迹记录的最后一个点作为当前位置）
        this.updateLiveTrack();
      } else {
        clearInterval(this.durationTimer);
        this.durationTimer = -1;
      }
    }, 1000);
  }

  // 更新实时轨迹显示
  async updateLiveTrack() {
    if (!this.mapController) {
      console.warn('[OutdoorMainPage] updateLiveTrack: mapController is null');
      return;
    }
    if (!this.trackingStatus.isRecording) {
      return;
    }
    if (this.trackingStatus.currentTrackId < 0) {
      console.warn('[OutdoorMainPage] updateLiveTrack: invalid trackId');
      return;
    }

    try {
      const points = await databaseService.getTrackPoints(this.trackingStatus.currentTrackId);
      console.info(`[OutdoorMainPage] Live track points: ${points.length}`);

      // 获取最新记录的轨迹点位置（用于显示当前位置标记）
      let currentPosition: mapCommon.LatLng;
      if (points.length > 0) {
        const lastPoint = points[points.length - 1];
        currentPosition = {
          latitude: lastPoint.latitude,
          longitude: lastPoint.longitude
        };
      } else {
        // 如果还没有记录点，使用当前GPS位置
        currentPosition = {
          latitude: this.currentLat,
          longitude: this.currentLon
        };
      }

      // 更新当前位置标记（替代系统蓝点）
      await this.updateCurrentPositionMarker(currentPosition);

      // 至少需要2个点才能画线
      if (points.length < 2) {
        return;
      }

      const latLngs: mapCommon.LatLng[] = points.map((p): mapCommon.LatLng => ({
        latitude: p.latitude,
        longitude: p.longitude
      }));

      // 移除旧的实时轨迹线
      if (this.liveTrackPolyline) {
        this.liveTrackPolyline.remove();
        this.liveTrackPolyline = null;
      }

      // 绘制新的实时轨迹线
      const options: mapCommon.MapPolylineOptions = {
        points: latLngs,
        color: 0xFFFF5722, // 橙色，区别于回放轨迹的蓝色
        width: 8,
        zIndex: 15
      };
      this.liveTrackPolyline = await this.mapController.addPolyline(options);
      console.info(`[OutdoorMainPage] Live polyline drawn with ${latLngs.length} points`);
    } catch (e) {
      console.error('[OutdoorMainPage] updateLiveTrack error:', JSON.stringify(e));
    }
  }

  // 更新当前位置标记（轨迹记录时使用，替代系统蓝点）
  async updateCurrentPositionMarker(position: mapCommon.LatLng) {
    if (!this.mapController) {
      return;
    }

    // 如果标记已存在，只更新位置
    if (this.currentPositionMarker) {
      this.currentPositionMarker.setPosition(position);
      return;
    }

    // 防止并发创建标记
    if (this.isCreatingPositionMarker) {
      return;
    }

    try {
      this.isCreatingPositionMarker = true;

      // 首次创建当前位置标记（使用默认红色标记）
      const markerOptions: mapCommon.MarkerOptions = {
        position: position,
        title: '当前位置',
        visible: true,
        zIndex: 20,
        alpha: 1,
        anchorU: 0.5,
        anchorV: 0.5,
        clickable: false,
        draggable: false,
        flat: false
      };
      this.currentPositionMarker = await this.mapController.addMarker(markerOptions);
    } catch (e) {
      console.error('[OutdoorMainPage] updateCurrentPositionMarker error:', JSON.stringify(e));
    } finally {
      this.isCreatingPositionMarker = false;
    }
  }

  // 清除实时轨迹
  clearLiveTrack() {
    if (this.liveTrackPolyline) {
      this.liveTrackPolyline.remove();
      this.liveTrackPolyline = null;
    }
  }

  async stopTracking() {
    if (this.durationTimer !== -1) {
      clearInterval(this.durationTimer);
      this.durationTimer = -1;
    }

    // 清除实时轨迹显示
    this.clearLiveTrack();

    // 清除当前位置标记
    this.clearCurrentPositionMarker();

    // 恢复系统蓝点显示
    if (this.mapController) {
      this.mapController.setMyLocationEnabled(true);
    }

    const track = await trackingService.stopRecording();
    if (track) {
      this.tracks = await databaseService.getTracks();
      promptAction.showToast({ message: `轨迹已保存，共${track.distance.toFixed(2)}km` });
    }
  }

  // 清除当前位置标记
  clearCurrentPositionMarker() {
    this.isCreatingPositionMarker = false;
    if (this.currentPositionMarker) {
      this.currentPositionMarker.remove();
      this.currentPositionMarker = null;
    }
  }

  async addMarker() {
    if (!this.newMarkerName.trim()) {
      return;
    }

    const marker: MapMarker = {
      name: this.newMarkerName,
      description: this.newMarkerDesc,
      latitude: this.selectedMarkerLat,
      longitude: this.selectedMarkerLon,
      type: this.newMarkerType,
      createTime: Date.now()
    };

    await databaseService.addMarker(marker);
    this.markers = await databaseService.getMarkers();
    await this.renderMarkersOnMap();

    this.showAddMarker = false;
    this.newMarkerName = '';
    this.newMarkerDesc = '';
    this.newMarkerType = 'custom';
  }

  async addFence() {
    if (!this.newFenceName.trim()) {
      return;
    }

    const fence: Geofence = {
      name: this.newFenceName,
      latitude: this.selectedMarkerLat,
      longitude: this.selectedMarkerLon,
      radius: this.newFenceRadius,
      type: 'safe',
      enabled: 1,
      createTime: Date.now()
    };

    await geofenceService.addFence(fence);
    this.geofences = await databaseService.getGeofences();
    await this.renderFencesOnMap();

    this.showAddFence = false;
    this.newFenceName = '';
    this.newFenceRadius = 100;
  }

  // 添加群组围栏
  async addGroupFence() {
    if (!this.newGroupFenceName.trim()) {
      promptAction.showToast({ message: '请输入围栏名称' });
      return;
    }

    if (!this.currentGroup) {
      promptAction.showToast({ message: '请先加入群组' });
      return;
    }

    if (!this.currentGroup.isOwner) {
      promptAction.showToast({ message: '需要管理员权限' });
      return;
    }

    const geofence: GroupGeofenceData = {
      name: this.newGroupFenceName,
      latitude: this.selectedMarkerLat,
      longitude: this.selectedMarkerLon,
      radius: this.newGroupFenceRadius,
      type: this.newGroupFenceType
    };

    // 发送到服务器
    wsService.addGroupGeofence(this.currentGroup.code, geofence);
  }

  // 删除群组围栏
  async deleteGroupFence(fence: GroupGeofence) {
    if (!this.currentGroup || !fence.id) {
      return;
    }

    if (!this.currentGroup.isOwner) {
      promptAction.showToast({ message: '需要管理员权限' });
      return;
    }

    wsService.removeGroupGeofence(this.currentGroup.code, fence.id);
  }

  // 定位到群组围栏
  locateGroupFence(fence: GroupGeofence) {
    if (!this.mapController) {
      return;
    }

    const cameraUpdate = map.newCameraPosition({
      target: { latitude: fence.latitude, longitude: fence.longitude },
      zoom: 16
    });
    this.mapController.animateCamera(cameraUpdate);
    this.showGroupFenceList = false;
    this.currentTab = 'map';
  }

  async renderMarkersOnMap() {
    if (!this.mapController) {
      return;
    }

    for (const m of this.mapMarkers) {
      m.remove();
    }
    this.mapMarkers = [];

    for (const marker of this.markers) {
      const type = this.markerTypes.find(t => t.key === marker.type);
      const iconText = type?.icon || '📍';

      const options: mapCommon.MarkerOptions = {
        position: { latitude: marker.latitude, longitude: marker.longitude },
        visible: true,
        zIndex: 10,
        alpha: 1,
        anchorU: 0.5,
        anchorV: 0.5,
        clickable: true,
        draggable: false,
        flat: false,
        title: marker.name,
        snippet: `${iconText} ${marker.description || marker.type}`
      };

      const mapMarker = await this.mapController.addMarker(options);
      mapMarker.setInfoWindowVisible(true);
      this.mapMarkers.push(mapMarker);
    }
  }

  async renderFencesOnMap() {
    if (!this.mapController) {
      return;
    }

    for (const c of this.fenceCircles) {
      c.remove();
    }
    this.fenceCircles = [];

    for (const fence of this.geofences) {
      if (!fence.enabled) {
        continue;
      }

      const options: mapCommon.MapCircleOptions = {
        center: { latitude: fence.latitude, longitude: fence.longitude },
        radius: fence.radius,
        fillColor: fence.type === 'safe' ? 0x304CAF50 : 0x30FF9800,
        strokeColor: fence.type === 'safe' ? 0xFF4CAF50 : 0xFFFF9800,
        strokeWidth: 2,
        visible: true,
        zIndex: 5
      };
      const circle = await this.mapController.addCircle(options);
      this.fenceCircles.push(circle);
    }
  }

  // 渲染群组围栏到地图
  async renderGroupFencesOnMap() {
    if (!this.mapController) {
      return;
    }

    // 清除现有群组围栏圆圈
    for (const c of this.groupFenceCircles) {
      c.remove();
    }
    this.groupFenceCircles = [];

    // 绘制群组围栏
    for (const fence of this.groupGeofences) {
      const options: mapCommon.MapCircleOptions = {
        center: { latitude: fence.latitude, longitude: fence.longitude },
        radius: fence.radius,
        fillColor: fence.type === 'safe' ? 0x309C27B0 : 0x30FF5722,
        strokeColor: fence.type === 'safe' ? 0xFF9C27B0 : 0xFFFF5722,
        strokeWidth: 3,
        visible: true,
        zIndex: 6
      };
      const circle = await this.mapController.addCircle(options);
      this.groupFenceCircles.push(circle);
    }
  }

  // 清除群组围栏
  clearGroupFences() {
    for (const c of this.groupFenceCircles) {
      c.remove();
    }
    this.groupFenceCircles = [];
    this.groupGeofences = [];
  }

  async playbackTrack(track: Track) {
    console.info(`[OutdoorMainPage] playbackTrack called, trackId: ${track.id}, mapController: ${this.mapController !==
      null}`);

    if (!this.mapController) {
      promptAction.showToast({ message: '地图未就绪，请稍候再试' });
      return;
    }

    if (!track.id) {
      promptAction.showToast({ message: '轨迹ID无效' });
      return;
    }

    try {
      const points = await databaseService.getTrackPoints(track.id);
      console.info(`[OutdoorMainPage] Track ${track.id} has ${points.length} points`);

      if (points.length === 0) {
        promptAction.showToast({ message: '该轨迹没有记录点' });
        return;
      }

      // 清除旧的轨迹线
      if (this.trackPolyline) {
        this.trackPolyline.remove();
        this.trackPolyline = null;
      }

      const latLngs: mapCommon.LatLng[] = points.map((p): mapCommon.LatLng => ({
        latitude: p.latitude,
        longitude: p.longitude
      }));

      console.info(`[OutdoorMainPage] Drawing polyline with ${latLngs.length} points, first: ${JSON.stringify(latLngs[0])}`);

      const options: mapCommon.MapPolylineOptions = {
        points: latLngs,
        color: 0xFF2196F3,
        width: 8,
        zIndex: 10
      };

      this.trackPolyline = await this.mapController.addPolyline(options);
      console.info(`[OutdoorMainPage] Polyline added: ${this.trackPolyline !== null}`);

      // 移动相机到轨迹起点
      const cameraUpdate = map.newCameraPosition({
        target: latLngs[0],
        zoom: 16
      });
      this.mapController.animateCamera(cameraUpdate);

      // 切换到地图页面显示轨迹
      this.currentTab = 'map';
      promptAction.showToast({ message: `显示轨迹: ${points.length}个点` });
    } catch (e) {
      console.error(`[OutdoorMainPage] playbackTrack error: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '显示轨迹失败' });
    }
  }

  async exportTrack(track: Track, format: 'gpx' | 'kml') {
    if (!track.id) {
      promptAction.showToast({ message: '轨迹数据无效' });
      return;
    }

    promptAction.showToast({ message: `正在导出${format.toUpperCase()}...` });

    let filePath = '';
    if (format === 'gpx') {
      filePath = await trackingService.exportToGPX(track.id, this.context);
    } else {
      filePath = await trackingService.exportToKML(track.id, this.context);
    }

    if (filePath) {
      promptAction.showToast({ message: `导出成功: ${filePath.split('/').pop()}` });
    } else {
      promptAction.showToast({ message: '导出失败' });
    }
  }

  async deleteTrack(track: Track) {
    if (!track.id) {
      return;
    }
    await databaseService.deleteTrack(track.id);
    this.tracks = await databaseService.getTracks();
  }

  startSOSCountdown() {
    const timer = setInterval(() => {
      this.sosCountdown--;
      if (this.sosCountdown <= 0) {
        clearInterval(timer);
        if (this.showSOS) {
          this.sendSOS();
        }
      }
    }, 1000);
  }

  async sendSOS() {
    // 触发SOS获取完整消息（包含位置、电量、时间戳、最近轨迹）
    const sosMsg = await sosService.triggerSOS(this.sosMessage);

    if (!sosMsg) {
      promptAction.showToast({ message: 'SOS发送失败，无法获取位置' });
      this.showSOS = false;
      this.sosCountdown = 0;
      this.sosMessage = '';
      return;
    }

    // 验证SOS消息完整性
    if (!sosService.validateSOSMessage(sosMsg)) {
      console.warn('[OutdoorMainPage] SOS message validation failed');
    }

    // 发送到群组或保存到本地
    if (this.currentGroup && this.isConnected) {
      // 发送到群组（包含最近轨迹片段）
      wsService.sendSOS(
        this.currentGroup.code,
        sosMsg.latitude,
        sosMsg.longitude,
        sosMsg.message,
        sosMsg.recentTrack as Object[]
      );
      // 同时保存到本地记录
      await sosService.saveSOSToLocal(sosMsg, true, this.currentGroup.code);
      promptAction.showToast({ message: 'SOS已发送到群组' });
    } else {
      // 未加入群组时保存到本地记录
      await sosService.saveSOSToLocal(sosMsg, false, '');
      promptAction.showToast({ message: 'SOS已保存到本地记录（未加入群组）' });
    }

    this.showSOS = false;
    this.sosCountdown = 0;
    this.sosMessage = '';
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

  updateMemberLocation(member: MemberInfo) {
    const index = this.members.findIndex(m => m.odId === member.odId);
    if (index !== -1) {
      const existingMember = this.members[index];
      existingMember.latitude = member.latitude;
      existingMember.longitude = member.longitude;
      existingMember.battery = member.battery;
      existingMember.signal = member.signal;
      existingMember.lastUpdate = member.lastUpdate;
      existingMember.isOnline = member.isOnline;
    }
    this.updateMemberMarker(member);
  }

  async updateMemberMarker(member: MemberInfo) {
    if (!this.mapController) {
      return;
    }

    if (member.odId === wsService.getOdId()) {
      return;
    }

    const existingMarker = this.memberMarkers.get(member.odId);
    if (existingMarker) {
      existingMarker.setPosition({ latitude: member.latitude, longitude: member.longitude });
    } else {
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

  clearAllMemberMarkers() {
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

  async moveToCurrentLocation() {
    promptAction.showToast({ message: '正在获取位置...' });
    try {
      const loc = await locationService.getCurrentPosition();
      if (loc && this.mapController) {
        this.currentLat = loc.latitude;
        this.currentLon = loc.longitude;
        const cameraUpdate = map.newCameraPosition({
          target: { latitude: loc.latitude, longitude: loc.longitude },
          zoom: 15
        });
        this.mapController.animateCamera(cameraUpdate);
      } else {
        promptAction.showToast({ message: '无法获取位置' });
      }
    } catch (e) {
      promptAction.showToast({ message: '获取位置失败' });
    }
  }

  // ========== 工具方法 ==========
  formatDistance(km: number): string {
    if (km >= 1) {
      return `${km.toFixed(2)} km`;
    }
    return `${Math.round(km * 1000)} m`;
  }

  formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;

    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${minutes}:${secs.toString().padStart(2, '0')}`;
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${date.getMinutes()
      .toString()
      .padStart(2, '0')}`;
  }

  formatTimeAgo(timestamp: number): string {
    const diff = Date.now() - timestamp;
    if (diff < 60000) {
      return '刚刚';
    }
    if (diff < 3600000) {
      return `${Math.floor(diff / 60000)}分钟前`;
    }
    if (diff < 86400000) {
      return `${Math.floor(diff / 3600000)}小时前`;
    }
    return `${Math.floor(diff / 86400000)}天前`;
  }

  formatTotalDistance(): string {
    const total = this.tracks.reduce((sum, t) => sum + t.distance, 0);
    return `${total.toFixed(1)}km`;
  }

  formatTotalDuration(): string {
    const total = this.tracks.reduce((sum, t) => sum + t.duration, 0);
    const hours = Math.floor(total / 3600000);
    const minutes = Math.floor((total % 3600000) / 60000);
    if (hours > 0) {
      return `${hours}h${minutes}m`;
    }
    return `${minutes}m`;
  }

  // 格式化SOS警报时间
  formatSOSTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - timestamp;

    // 如果是今天，显示时间
    if (date.toDateString() === now.toDateString()) {
      return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
    }

    // 如果是昨天，显示"昨天"
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    if (date.toDateString() === yesterday.toDateString()) {
      return '昨天';
    }

    // 其他情况显示日期
    return `${date.getMonth() + 1}/${date.getDate()}`;
  }

  // 格式化SOS轨迹点时间
  formatSOSTrackTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
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
        if (loc) {
          this.currentLat = loc.latitude;
          this.currentLon = loc.longitude;
          if (this.mapController) {
            const cameraUpdate = map.newCameraPosition({
              target: { latitude: loc.latitude, longitude: loc.longitude },
              zoom: 15
            });
            this.mapController.animateCamera(cameraUpdate);
          }
        }
      }
    } catch (err) {
      console.error('[OutdoorMainPage] Permission error:', JSON.stringify(err));
    }
  }
}

