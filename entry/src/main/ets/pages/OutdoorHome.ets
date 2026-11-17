// entry/src/main/ets/pages/OutdoorHome.ets
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { databaseService, Track, MapMarker, Geofence, ActivityType } from '../services/DatabaseService';
import { trackingService, TrackingStatus } from '../services/TrackingService';
import { geofenceService, GeofenceEvent } from '../services/GeofenceService';
import { sosService } from '../services/SOSService';
import { locationService } from '../services/LocationService';
import { promptAction } from '@kit.ArkUI';

// 底部Tab类型（移除群组，群组功能在实时群组页面）
type TabType = 'map' | 'track' | 'me';

// 标记类型
interface MarkerType {
  key: string;
  name: string;
  icon: string;
}

@Entry
@Component
export struct OutdoorHome {
  @State currentTab: TabType = 'map';
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
  // 定时器
  private durationTimer: number = -1;
  // SOS
  @State showSOS: boolean = false;
  @State sosCountdown: number = 0;
  @State sosMessage: string = '';
  // 地图
  private context = getContext(this) as common.UIAbilityContext;
  private mapController: map.MapComponentController | null = null;
  private mapOption?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private mapMarkers: map.Marker[] = [];
  private fenceCircles: map.MapCircle[] = [];
  private trackPolyline: map.MapPolyline | null = null;
  // 标记类型列表
  private markerTypes: MarkerType[] = [
    { key: 'water', name: '水源点', icon: '💧' },
    { key: 'rest', name: '休息区', icon: '🏕️' },
    { key: 'danger', name: '危险区', icon: '⚠️' },
    { key: 'camp', name: '营地', icon: '⛺' },
    { key: 'custom', name: '自定义', icon: '📍' }
  ];

  aboutToAppear(): void {
    this.initMap();
    this.initServices();
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

        // 地图长按添加标记
        controller.on('mapLongClick', (pos: mapCommon.LatLng) => {
          this.selectedMarkerLat = pos.latitude;
          this.selectedMarkerLon = pos.longitude;
          this.showAddMarker = true;
        });

        // 地图准备好后，尝试移动到当前位置
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
            console.info(`[OutdoorHome] Map moved to: ${loc.latitude}, ${loc.longitude}`);
          }
        } catch (e) {
          console.warn('[OutdoorHome] Failed to get initial location');
        }
      }
    };
  }

  async initServices() {
    await databaseService.init(this.context);
    await this.loadData();

    // 设置轨迹状态回调
    trackingService.setStatusCallback((status) => {
      this.trackingStatus = status;
    });

    // 设置围栏事件回调
    geofenceService.setEventCallback((event: GeofenceEvent) => {
      this.handleGeofenceEvent(event);
    });

    // 加载围栏
    await geofenceService.loadAllFences();
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
    // 这里可以添加通知逻辑
    console.info(`[OutdoorHome] ${action}围栏: ${fenceName}`);
  }

  build() {
    Column() {
      // 主内容区
      Stack() {
        if (this.currentTab === 'map') {
          this.buildMapView()
        } else if (this.currentTab === 'track') {
          this.buildTrackView()
        } else {
          this.buildMeView()
        }

        // SOS按钮（始终显示）
        this.buildSOSButton()

        // 添加标记弹窗
        if (this.showAddMarker) {
          this.buildAddMarkerDialog()
        }

        // 添加围栏弹窗
        if (this.showAddFence) {
          this.buildAddFenceDialog()
        }

        // SOS确认弹窗
        if (this.showSOS) {
          this.buildSOSDialog()
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
    .onDisAppear(() => {
      // 清理定时器
      if (this.durationTimer !== -1) {
        clearInterval(this.durationTimer);
        this.durationTimer = -1;
      }
      locationService.stopLocationUpdates();
    })
  }

  // ========== 地图视图 ==========
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
            // 在当前位置添加标记
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

        Button(this.trackingStatus.isRecording ? '停止记录' : '开始记录')
          .fontSize(13)
          .height(32)
          .backgroundColor(this.trackingStatus.isRecording ? '#F44336' : '#2196F3')
          .onClick(() => this.toggleTracking())
      }
      .padding({ top: 50, left: 12, right: 12 })

      // 轨迹记录状态
      if (this.trackingStatus.isRecording) {
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

  // ========== 轨迹视图 ==========
  @Builder
  buildTrackView() {
    Column() {
      // 标题
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

      // 轨迹列表
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

      // 操作按钮
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

  // ========== 我的视图 ==========
  @Builder
  buildMeView() {
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
          Text('户外探险者').fontSize(18).fontWeight(FontWeight.Bold)
          Text('ID: 12345678').fontSize(13).fontColor('#999').margin({ top: 4 })
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

  // ========== 弹窗 ==========
  @Builder
  buildAddMarkerDialog() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showAddMarker = false)

      // 弹窗内容
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

        // 类型选择
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

  // ========== 底部Tab栏 ==========
  @Builder
  buildTabBar() {
    Row() {
      this.buildTabItem('map', '地图', $r('sys.media.ohos_ic_public_location'))
      this.buildTabItem('track', '轨迹', $r('sys.media.ohos_ic_public_clock'))
      this.buildTabItem('me', '我的', $r('sys.media.ohos_ic_public_location'))
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

  // ========== 业务方法 ==========
  async toggleTracking() {
    if (this.trackingStatus.isRecording) {
      await this.stopTracking();
    } else {
      const name = `轨迹_${this.formatDate(Date.now())}`;
      const trackId = await trackingService.startRecording(name);
      if (trackId > 0) {
        promptAction.showToast({ message: '开始记录轨迹' });
        // 启动定时器刷新时间显示
        this.startDurationTimer();
      } else {
        promptAction.showToast({ message: '启动记录失败' });
      }
    }
  }

  // 启动时间刷新定时器
  startDurationTimer() {
    if (this.durationTimer !== -1) {
      clearInterval(this.durationTimer);
    }
    this.durationTimer = setInterval(() => {
      if (this.trackingStatus.isRecording) {
        // 从 TrackingService 获取正确的状态（包含暂停逻辑）
        this.trackingStatus = trackingService.getStatus();
      } else {
        clearInterval(this.durationTimer);
        this.durationTimer = -1;
      }
    }, 1000);
  }

  async stopTracking() {
    // 停止定时器
    if (this.durationTimer !== -1) {
      clearInterval(this.durationTimer);
      this.durationTimer = -1;
    }

    const track = await trackingService.stopRecording();
    if (track) {
      this.tracks = await databaseService.getTracks();
      promptAction.showToast({ message: `轨迹已保存，共${track.distance.toFixed(2)}km` });
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

  async renderMarkersOnMap() {
    if (!this.mapController) {
      return;
    }

    // 清除旧标记
    for (const m of this.mapMarkers) {
      m.remove();
    }
    this.mapMarkers = [];

    // 添加新标记
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

      // 设置信息窗口始终显示图标
      mapMarker.setInfoWindowVisible(true);

      this.mapMarkers.push(mapMarker);
    }
  }

  async renderFencesOnMap() {
    if (!this.mapController) {
      return;
    }

    // 清除旧围栏
    for (const c of this.fenceCircles) {
      c.remove();
    }
    this.fenceCircles = [];

    // 添加新围栏
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

  async playbackTrack(track: Track) {
    if (!this.mapController || !track.id) {
      promptAction.showToast({ message: '地图未就绪' });
      return;
    }

    const points = await databaseService.getTrackPoints(track.id);
    if (points.length === 0) {
      promptAction.showToast({ message: '该轨迹没有记录点' });
      return;
    }

    // 清除旧轨迹
    if (this.trackPolyline) {
      this.trackPolyline.remove();
      this.trackPolyline = null;
    }

    // 绘制轨迹
    const latLngs: mapCommon.LatLng[] = points.map((p): mapCommon.LatLng => ({
      latitude: p.latitude,
      longitude: p.longitude
    }));

    const options: mapCommon.MapPolylineOptions = {
      points: latLngs,
      color: 0xFF2196F3,
      width: 8,
      zIndex: 10
    };
    this.trackPolyline = await this.mapController.addPolyline(options);

    // 移动到轨迹起点
    const cameraUpdate = map.newCameraPosition({
      target: latLngs[0],
      zoom: 15
    });
    this.mapController.animateCamera(cameraUpdate);

    // 切换到地图页
    this.currentTab = 'map';
    promptAction.showToast({ message: `显示轨迹: ${points.length}个点` });
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
      console.info(`[OutdoorHome] Exported: ${filePath}`);
      promptAction.showToast({ message: `导出成功: ${filePath.split('/').pop()}` });
    } else {
      promptAction.showToast({ message: '导出失败，轨迹可能没有数据' });
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
    const msg = await sosService.triggerSOS(this.sosMessage);
    if (msg) {
      const formatted = sosService.formatSOSMessage(msg);
      console.info(`[OutdoorHome] SOS sent:\n${formatted}`);
      // 这里可以添加发送到群组的逻辑
    }
    this.showSOS = false;
    this.sosCountdown = 0;
    this.sosMessage = '';
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
        promptAction.showToast({ message: `当前位置: ${loc.latitude.toFixed(4)}, ${loc.longitude.toFixed(4)}` });
      } else {
        promptAction.showToast({ message: '无法获取位置' });
      }
    } catch (e) {
      console.error('[OutdoorHome] moveToCurrentLocation error:', JSON.stringify(e));
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
        // 先获取一次当前位置并移动地图
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

        // 开始持续定位
        locationService.startLocationUpdates((loc) => {
          this.currentLat = loc.latitude;
          this.currentLon = loc.longitude;
        });
      }
    } catch (err) {
      console.error('[OutdoorHome] Permission error:', JSON.stringify(err));
    }
  }
}
