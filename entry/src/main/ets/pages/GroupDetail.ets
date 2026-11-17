// entry/src/main/ets/pages/GroupDetail.ets
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { databaseService, Group, GroupMember, Geofence } from '../services/DatabaseService';
import { geofenceService } from '../services/GeofenceService';
import { locationService } from '../services/LocationService';
import router from '@ohos.router';

interface RouterParams {
  groupId: number;
}

@Entry
@Component
export struct GroupDetail {
  @State group: Group | null = null;
  @State members: GroupMember[] = [];
  @State geofences: Geofence[] = [];
  @State showInvite: boolean = false;
  @State showAddFence: boolean = false;
  @State newFenceName: string = '';
  @State newFenceRadius: number = 100;
  @State selectedLat: number = 0;
  @State selectedLon: number = 0;
  private context = getContext(this) as common.UIAbilityContext;
  private mapController: map.MapComponentController | null = null;
  private mapOption?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private memberMarkers: map.Marker[] = [];
  private fenceCircles: map.MapCircle[] = [];

  aboutToAppear(): void {
    const params = router.getParams() as RouterParams;
    if (params?.groupId) {
      this.loadGroupData(params.groupId);
    }
    this.mapOption = {
      position: {
        target: { latitude: 39.9042, longitude: 116.4074 },
        zoom: 14
      }
    };

    this.mapCallback = async (err, controller) => {
      if (!err && controller) {
        this.mapController = controller;
        controller.setMyLocationEnabled(true);
        await this.renderMembersOnMap();
        await this.renderFencesOnMap();
      }
    };
  }

  async loadGroupData(groupId: number) {
    const groups = await databaseService.getGroups();
    this.group = groups.find(g => g.id === groupId) || null;
    this.members = await databaseService.getMembers(groupId);
    this.geofences = await databaseService.getGeofences();
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Image($r('sys.media.ohos_ic_public_arrow_left'))
          .width(24)
          .height(24)
          .onClick(() => router.back())

        Text(this.group?.name || '群组详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 12 })
          .layoutWeight(1)

        if (this.group?.isOwner === 1) {
          Button('设置')
            .fontSize(13)
            .height(32)
            .backgroundColor('#F5F5F5')
            .fontColor('#666')
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(Color.White)

      // 地图区域
      Stack() {
        MapComponent({
          mapOptions: this.mapOption,
          mapCallback: this.mapCallback
        })
          .width('100%')
          .height(300)

        // 工具栏
        Row({ space: 8 }) {
          Button('添加围栏')
            .fontSize(12)
            .height(28)
            .backgroundColor('#FF9800')
            .onClick(() => {
              this.selectedLat = 39.9042;
              this.selectedLon = 116.4074;
              this.showAddFence = true;
            })

          Button('邀请成员')
            .fontSize(12)
            .height(28)
            .backgroundColor('#4CAF50')
            .onClick(() => this.showInvite = true)
        }
        .position({ x: 12, y: 12 })
      }

      // 成员列表
      Column() {
        Row() {
          Text('群组成员').fontSize(16).fontWeight(FontWeight.Medium)
          Blank()
          Text(`${this.members.length} 人`).fontSize(14).fontColor('#999')
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 12,
          bottom: 8
        })

        List() {
          ForEach(this.members, (member: GroupMember) => {
            ListItem() {
              this.buildMemberRow(member)
            }
          })
        }
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .backgroundColor('#F5F5F5')

      // 邀请弹窗
      if (this.showInvite) {
        this.buildInviteDialog()
      }

      // 添加围栏弹窗
      if (this.showAddFence) {
        this.buildAddFenceDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildMemberRow(member: GroupMember) {
    Row() {
      // 头像
      Stack() {
        Text(member.name.charAt(0))
          .fontSize(16)
          .fontColor(Color.White)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor('#007DFF')
          .borderRadius(20)

        // 在线状态
        Circle()
          .width(10)
          .height(10)
          .fill(member.lastUpdate > Date.now() - 300000 ? '#4CAF50' : '#999')
          .position({ x: 30, y: 30 })
      }

      Column() {
        Row() {
          Text(member.name).fontSize(15)
          if (member.role === 0) {
            Text('管理员')
              .fontSize(10)
              .fontColor('#FF9800')
              .margin({ left: 6 })
              .padding({
                left: 4,
                right: 4,
                top: 2,
                bottom: 2
              })
              .backgroundColor('#FFF3E0')
              .borderRadius(4)
          }
        }

        Row({ space: 12 }) {
          Text(`🔋 ${member.battery}%`)
            .fontSize(12)
            .fontColor(member.battery < 20 ? '#F44336' : '#666')
          Text(`📶 ${member.signal}/4`).fontSize(12).fontColor('#666')
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      // 操作按钮
      Row({ space: 8 }) {
        Button() {
          Image($r('sys.media.ohos_ic_public_location'))
            .width(18)
            .height(18)
            .fillColor('#007DFF')
        }
        .width(32)
        .height(32)
        .backgroundColor('#E3F2FD')
        .borderRadius(16)
        .onClick(() => this.locateMember(member))

        if (this.group?.isOwner === 1 && member.role !== 0) {
          Button() {
            Image($r('sys.media.ohos_ic_public_remove'))
              .width(18)
              .height(18)
              .fillColor('#F44336')
          }
          .width(32)
          .height(32)
          .backgroundColor('#FFEBEE')
          .borderRadius(16)
          .onClick(() => this.removeMember(member))
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .margin({ bottom: 1 })
  }

  @Builder
  buildInviteDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showInvite = false)

      Column() {
        Text('邀请成员').fontSize(18).fontWeight(FontWeight.Bold)

        // 群组码
        Column() {
          Text('群组邀请码').fontSize(14).fontColor('#666')
          Text(this.group?.code || '')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#007DFF')
            .margin({ top: 8 })
            .letterSpacing(4)
        }
        .margin({ top: 20 })

        Text('分享此邀请码给好友，即可加入群组')
          .fontSize(13)
          .fontColor('#999')
          .margin({ top: 12 })

        Row({ space: 12 }) {
          Button('复制邀请码')
            .layoutWeight(1)
            .height(44)
            .backgroundColor('#007DFF')
            .onClick(() => {
              // 复制到剪贴板
              this.showInvite = false;
            })
        }
        .margin({ top: 24 })
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
  buildAddFenceDialog() {
    Column() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showAddFence = false)

      Column() {
        Text('添加安全围栏').fontSize(18).fontWeight(FontWeight.Bold)

        TextInput({ placeholder: '围栏名称' })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((v) => this.newFenceName = v)

        Text('围栏半径').fontSize(14).fontColor('#666').margin({ top: 12 })
        Row({ space: 8 }) {
          ForEach([50, 100, 200, 500], (r: number) => {
            Button(`${r}m`)
              .fontSize(13)
              .height(32)
              .backgroundColor(this.newFenceRadius === r ? '#FF9800' : '#F5F5F5')
              .fontColor(this.newFenceRadius === r ? Color.White : '#666')
              .onClick(() => this.newFenceRadius = r)
          })
        }
        .margin({ top: 8 })

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

  async renderMembersOnMap() {
    if (!this.mapController) {
      return;
    }

    for (const m of this.memberMarkers) {
      m.remove();
    }
    this.memberMarkers = [];

    for (const member of this.members) {
      if (member.latitude === 0) {
        continue;
      }

      const options: mapCommon.MarkerOptions = {
        position: { latitude: member.latitude, longitude: member.longitude },
        visible: true,
        title: member.name,
        zIndex: 10,
        alpha: 1,
        anchorU: 0.5,
        anchorV: 1,
        clickable: true,
        draggable: false,
        flat: false
      };
      const marker = await this.mapController.addMarker(options);
      this.memberMarkers.push(marker);
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
        fillColor: 0x304CAF50,
        strokeColor: 0xFF4CAF50,
        strokeWidth: 2,
        visible: true,
        zIndex: 5
      };
      const circle = await this.mapController.addCircle(options);
      this.fenceCircles.push(circle);
    }
  }

  locateMember(member: GroupMember) {
    if (!this.mapController || member.latitude === 0) {
      return;
    }

    const cameraUpdate = map.newCameraPosition({
      target: { latitude: member.latitude, longitude: member.longitude },
      zoom: 16
    });
    this.mapController.animateCamera(cameraUpdate);
  }

  async removeMember(member: GroupMember) {
    if (!member.id) {
      return;
    }
    await databaseService.deleteMember(member.id);
    if (this.group?.id) {
      this.members = await databaseService.getMembers(this.group.id);
    }
  }

  async addFence() {
    if (!this.newFenceName.trim()) {
      return;
    }

    const fence: Geofence = {
      name: this.newFenceName,
      latitude: this.selectedLat,
      longitude: this.selectedLon,
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
  }
}
