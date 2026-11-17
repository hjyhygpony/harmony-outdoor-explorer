import { locationService } from '../services/LocationService';
import { abilityAccessCtrl, common, Permissions, Want } from '@kit.AbilityKit';
import { BusinessError, AsyncCallback } from '@kit.BasicServicesKit';
import { MapComponent, mapCommon, map, navi, site } from '@kit.MapKit';

// 导航模式
enum NavMode {
  DRIVING = 'driving',
  WALKING = 'walk',
  CYCLING = 'cycle',
  TAXI = 'taxi'
}

// 搜索结果项
interface SearchItem {
  name: string;
  address: string;
  latitude: number;
  longitude: number;
}

@Entry
@Component
export struct MapHome {
  // 当前定位
  @State currentLatitude: number = 39.9042;
  @State currentLongitude: number = 116.4074;
  @State currentAddress: string = '正在获取位置...';

  // 起点
  @State startLatitude: number = 0;
  @State startLongitude: number = 0;
  @State startAddress: string = '我的位置';
  @State isStartUsingCurrentLocation: boolean = true;

  // 终点
  @State endLatitude: number = 0;
  @State endLongitude: number = 0;
  @State endAddress: string = '';

  // UI状态
  @State isRouteMode: boolean = false;
  @State selectedNavMode: NavMode = NavMode.DRIVING;

  // 搜索相关
  @State isSearching: boolean = false; // 是否显示搜索面板
  @State searchType: 'start' | 'end' = 'end'; // 搜索类型
  @State searchKeyword: string = ''; // 搜索关键词
  @State searchResults: SearchItem[] = []; // 搜索结果
  @State isLoading: boolean = false; // 搜索加载中

  // 路线规划结果
  @State routeDistance: number = 0;
  @State routeDuration: number = 0;

  private context = getContext(this) as common.UIAbilityContext;
  private mapController: map.MapComponentController | null = null;
  private mapOption?: mapCommon.MapOptions;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private startMarker: map.Marker | null = null;
  private endMarker: map.Marker | null = null;
  private currentPolyline: map.MapPolyline | null = null;
  private searchTimer: number = -1; // 搜索防抖定时器


  aboutToAppear(): void {
    this.mapOption = {
      position: {
        target: { latitude: this.currentLatitude, longitude: this.currentLongitude },
        zoom: 15
      },
      scaleControlsEnabled: true,
      compassControlsEnabled: true
    };

    this.mapCallback = async (err, controller) => {
      if (!err && controller) {
        this.mapController = controller;
        try {
          this.mapController.setMyLocationEnabled(true);
          this.mapController.setMyLocationControlsEnabled(true);
          this.mapController.on("mapClick", (pos: mapCommon.LatLng) => {
            if (!this.isSearching) {
              this.handleMapClick(pos);
            }
          });
        } catch (e) {
          console.warn('MapDebug', '地图初始化失败: ' + JSON.stringify(e));
        }
      }
    };
  }

  onPageShow(): void {
    if (this.mapController) this.mapController.show();
  }

  onPageHide(): void {
    if (this.mapController) this.mapController.hide();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 地图
      MapComponent({
        mapOptions: this.mapOption,
        mapCallback: this.mapCallback
      })
        .width('100%')
        .height('100%')

      // 搜索面板（全屏覆盖）
      if (this.isSearching) {
        this.buildSearchOverlay()
      } else {
        // 顶部地址栏
        Column() {
          this.buildAddressBar()
        }
        .width('100%')
        .padding({ top: 50, left: 12, right: 12 })
      }

      // 底部导航面板
      if (this.isRouteMode && this.endLatitude !== 0 && !this.isSearching) {
        Column() {
          this.buildNavigationPanel()
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: -280 })
      }

      // 右下角定位按钮
      if (!this.isSearching) {
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
    .height('100%')
    .onAppear(() => this.reqPermissions())
    .onDisAppear(() => locationService.stopLocationUpdates())
  }


  // 地址栏（点击进入搜索）
  @Builder
  buildAddressBar() {
    Column({ space: 0 }) {
      // 起点
      Row() {
        Circle().width(10).height(10).fill('#00C853').margin({ left: 12, right: 10 })

        Text(this.isStartUsingCurrentLocation ? '我的位置' : this.startAddress)
          .fontSize(14)
          .fontColor('#333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (!this.isStartUsingCurrentLocation) {
          Text('定位')
            .fontSize(12)
            .fontColor('#007DFF')
            .margin({ right: 8 })
            .onClick(() => this.resetToCurrentLocation())
        }

        Image($r('sys.media.ohos_ic_public_edit'))
          .width(18)
          .height(18)
          .fillColor('#999')
          .margin({ right: 12 })
      }
      .width('100%')
      .height(46)
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 12, topRight: 12 })
      .onClick(() => this.openSearch('start'))

      Divider().color('#EEE').width('92%')

      // 终点
      Row() {
        Circle().width(10).height(10).fill('#FF5252').margin({ left: 12, right: 10 })

        Text(this.endAddress || '输入目的地')
          .fontSize(14)
          .fontColor(this.endAddress ? '#333' : '#999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.endAddress) {
          Text('×')
            .fontSize(18)
            .fontColor('#999')
            .margin({ right: 12 })
            .onClick(() => this.clearRoute())
        } else {
          Image($r('sys.media.ohos_ic_public_edit'))
            .width(18)
            .height(18)
            .fillColor('#999')
            .margin({ right: 12 })
        }
      }
      .width('100%')
      .height(46)
      .backgroundColor(Color.White)
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .onClick(() => this.openSearch('end'))
    }
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)' })
    .borderRadius(12)
  }


  // 搜索面板（全屏）
  @Builder
  buildSearchOverlay() {
    Column() {
      // 顶部搜索框
      Row() {
        // 返回按钮
        Image($r('sys.media.ohos_ic_public_arrow_left'))
          .width(24)
          .height(24)
          .fillColor('#333')
          .margin({ left: 12 })
          .onClick(() => this.closeSearch())

        // 搜索输入框
        TextInput({ placeholder: this.searchType === 'start' ? '输入起点' : '输入目的地', text: this.searchKeyword })
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F5F5F5')
          .borderRadius(20)
          .margin({ left: 12, right: 12 })
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.searchKeyword = value;
            this.debounceSearch(value);
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Color.White)

      // 快捷选项
      if (this.searchType === 'start' && this.searchKeyword === '') {
        Row() {
          Button('📍 我的位置')
            .fontSize(13)
            .fontColor('#007DFF')
            .backgroundColor('#E3F2FD')
            .borderRadius(16)
            .height(32)
            .onClick(() => {
              this.resetToCurrentLocation();
              this.closeSearch();
            })
        }
        .width('100%')
        .padding({ left: 16, top: 12 })
        .justifyContent(FlexAlign.Start)
      }

      // 搜索结果列表
      if (this.isLoading) {
        Row() {
          LoadingProgress().width(24).height(24)
          Text('搜索中...').fontSize(14).fontColor('#999').margin({ left: 8 })
        }
        .width('100%')
        .height(60)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.searchResults, (item: SearchItem, index: number) => {
            ListItem() {
              Row() {
                Image($r('sys.media.ohos_ic_public_location'))
                  .width(20)
                  .height(20)
                  .fillColor('#999')
                  .margin({ left: 16, right: 12 })

                Column() {
                  Text(item.name)
                    .fontSize(15)
                    .fontColor('#333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(item.address)
                    .fontSize(12)
                    .fontColor('#999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .height(64)
              .onClick(() => this.selectSearchResult(item))
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: '#F0F0F0', startMargin: 48 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
    .padding({ top: 50 })
  }


  // 导航面板
  @Builder
  buildNavigationPanel() {
    Column() {
      Row() {
        this.buildNavTab('驾车', NavMode.DRIVING)
        this.buildNavTab('步行', NavMode.WALKING)
        this.buildNavTab('骑行', NavMode.CYCLING)
        this.buildNavTab('打车', NavMode.TAXI)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
      .padding({ top: 16, bottom: 12 })
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 20, topRight: 20 })

      Column({ space: 12 }) {
        if (this.selectedNavMode === NavMode.TAXI) {
          Row() {
            Text('预估价格').fontSize(14).fontColor('#666')
            Text(' ¥25 - ¥35').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E6A23C')
          }
          Button('立即呼叫网约车')
            .onClick(() => this.launchExternalMap(NavMode.TAXI))
            .width('90%').height(44).backgroundColor('#E6A23C').borderRadius(22)
        } else {
          Row({ space: 20 }) {
            Column() {
              Text(this.formatDistance()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#333')
              Text('距离').fontSize(12).fontColor('#999')
            }
            Divider().vertical(true).height(40).color('#EEE')
            Column() {
              Text(this.formatDuration()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#007DFF')
              Text('预计时间').fontSize(12).fontColor('#999')
            }
          }.margin({ top: 8 })

          Button('开始导航')
            .onClick(() => this.launchExternalMap(this.selectedNavMode))
            .width('90%').height(44).backgroundColor('#007DFF').borderRadius(22).margin({ top: 12 })
        }
        Button('取消').onClick(() => this.clearRoute()).fontColor('#999').backgroundColor(Color.Transparent).fontSize(14)
      }
      .width('100%')
      .padding({ top: 8, bottom: 24 })
      .backgroundColor(Color.White)
    }
    .shadow({ radius: 16, color: 'rgba(0,0,0,0.1)', offsetY: -4 })
  }

  @Builder
  buildNavTab(title: string, mode: NavMode) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(this.selectedNavMode === mode ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedNavMode === mode ? '#007DFF' : '#666')
      if (this.selectedNavMode === mode) {
        Divider().width(24).strokeWidth(3).color('#007DFF').margin({ top: 6 })
      }
    }
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .onClick(() => {
      this.selectedNavMode = mode;
      if (mode !== NavMode.TAXI) this.planRoute();
    })
  }


  // 打开搜索面板
  openSearch(type: 'start' | 'end') {
    this.searchType = type;
    this.searchKeyword = '';
    this.searchResults = [];
    this.isSearching = true;
  }

  // 关闭搜索面板
  closeSearch() {
    this.isSearching = false;
    this.searchKeyword = '';
    this.searchResults = [];
  }

  // 防抖搜索
  debounceSearch(keyword: string) {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    if (keyword.trim().length === 0) {
      this.searchResults = [];
      return;
    }
    this.searchTimer = setTimeout(() => {
      this.doSearch(keyword);
    }, 300);
  }

  // 执行搜索
  async doSearch(keyword: string) {
    if (keyword.trim().length === 0) return;

    this.isLoading = true;
    try {
      const params: site.QueryAutoCompleteParams = {
        query: keyword,
        location: {
          latitude: this.currentLatitude,
          longitude: this.currentLongitude
        },
        language: "zh_CN"
      };

      const result = await site.queryAutoComplete(this.getUIContext().getHostContext(), params);

      if (result.sites && result.sites.length > 0) {
        this.searchResults = result.sites.map((s): SearchItem => ({
          name: s.name || '',
          address: s.formatAddress || '',
          latitude: s.location?.latitude || 0,
          longitude: s.location?.longitude || 0
        })).filter(item => item.latitude !== 0);
      } else {
        this.searchResults = [];
      }
    } catch (e) {
      console.error('MapDebug', '搜索失败: ' + JSON.stringify(e));
      this.searchResults = [];
    }
    this.isLoading = false;
  }

  // 选择搜索结果
  async selectSearchResult(item: SearchItem) {
    if (this.searchType === 'start') {
      this.startLatitude = item.latitude;
      this.startLongitude = item.longitude;
      this.startAddress = item.name;
      this.isStartUsingCurrentLocation = false;
      await this.updateStartMarker();
    } else {
      this.endLatitude = item.latitude;
      this.endLongitude = item.longitude;
      this.endAddress = item.name;
      this.isRouteMode = true;
      await this.updateEndMarker();
    }

    this.closeSearch();

    // 移动地图到选中位置
    if (this.mapController) {
      const cameraUpdate = map.newCameraPosition({
        target: { latitude: item.latitude, longitude: item.longitude },
        zoom: 15
      });
      this.mapController.animateCamera(cameraUpdate);
    }

    // 如果起点终点都有，规划路线
    if (this.startLatitude !== 0 || this.isStartUsingCurrentLocation) {
      if (this.endLatitude !== 0) {
        if (this.isStartUsingCurrentLocation) {
          this.startLatitude = this.currentLatitude;
          this.startLongitude = this.currentLongitude;
        }
        this.planRoute();
      }
    }
  }

  // 重置为当前位置
  resetToCurrentLocation() {
    this.isStartUsingCurrentLocation = true;
    this.startLatitude = this.currentLatitude;
    this.startLongitude = this.currentLongitude;
    this.startAddress = '我的位置';
    if (this.startMarker) {
      this.startMarker.remove();
      this.startMarker = null;
    }
    if (this.endLatitude !== 0) {
      this.planRoute();
    }
  }


  // 处理地图点击
  async handleMapClick(pos: mapCommon.LatLng) {
    if (!this.mapController) return;

    let address = '';
    try {
      const addr = await locationService.getAddressFromCoords(pos.latitude, pos.longitude);
      if (addr) {
        address = `${addr.locality || ''}${addr.subLocality || ''}${addr.roadName || ''}`;
      }
    } catch (e) {
      address = `${pos.latitude.toFixed(5)}, ${pos.longitude.toFixed(5)}`;
    }

    // 默认设置为终点
    this.endLatitude = pos.latitude;
    this.endLongitude = pos.longitude;
    this.endAddress = address || '已选择终点';
    this.isRouteMode = true;
    await this.updateEndMarker();

    if (this.isStartUsingCurrentLocation) {
      this.startLatitude = this.currentLatitude;
      this.startLongitude = this.currentLongitude;
      if (this.startMarker) {
        this.startMarker.remove();
        this.startMarker = null;
      }
    }

    this.planRoute();
  }

  async updateStartMarker() {
    if (!this.mapController) return;
    if (this.startMarker) {
      this.startMarker.remove();
      this.startMarker = null;
    }
    if (this.startLatitude === 0) return;

    const markerOptions: mapCommon.MarkerOptions = {
      position: { latitude: this.startLatitude, longitude: this.startLongitude },
      visible: true,
      zIndex: 10,
      alpha: 1,
      anchorU: 0.5,
      anchorV: 0.5,
      clickable: false,
      draggable: false,
      flat: false
    };
    this.startMarker = await this.mapController.addMarker(markerOptions);
  }

  async updateEndMarker() {
    if (!this.mapController) return;
    if (this.endMarker) {
      this.endMarker.remove();
      this.endMarker = null;
    }
    if (this.endLatitude === 0) return;

    const markerOptions: mapCommon.MarkerOptions = {
      position: { latitude: this.endLatitude, longitude: this.endLongitude },
      visible: true,
      zIndex: 11,
      alpha: 1,
      anchorU: 0.5,
      anchorV: 1,
      clickable: false,
      draggable: false,
      flat: false
    };
    this.endMarker = await this.mapController.addMarker(markerOptions);
  }


  async planRoute() {
    if (!this.mapController) return;

    if (this.isStartUsingCurrentLocation) {
      try {
        const loc = await locationService.getCurrentPosition();
        if (loc) {
          this.currentLatitude = loc.latitude;
          this.currentLongitude = loc.longitude;
          this.startLatitude = loc.latitude;
          this.startLongitude = loc.longitude;
        }
      } catch (e) {
        console.warn('MapDebug', '获取当前位置失败');
      }
    }

    if (this.startLatitude === 0 || this.endLatitude === 0) return;

    if (this.currentPolyline) {
      this.currentPolyline.remove();
      this.currentPolyline = null;
    }

    let routeColor = 0xFF007DFF;
    if (this.selectedNavMode === NavMode.WALKING) routeColor = 0xFF00C853;
    if (this.selectedNavMode === NavMode.CYCLING) routeColor = 0xFFFF9800;

    try {
      let routePoints: Array<mapCommon.LatLng> = [];
      const origin: mapCommon.LatLng = { latitude: this.startLatitude, longitude: this.startLongitude };
      const destination: mapCommon.LatLng = { latitude: this.endLatitude, longitude: this.endLongitude };

      if (this.selectedNavMode === NavMode.DRIVING) {
        const params: navi.DrivingRouteParams = { origins: [origin], destination, language: "zh_CN" };
        const result = await navi.getDrivingRoutes(this.getUIContext().getHostContext(), params);
        routePoints = this.extractRoutePoints(result);
      } else if (this.selectedNavMode === NavMode.WALKING) {
        const params: navi.RouteParams = { origins: [origin], destination, language: "zh_CN" };
        const result = await navi.getWalkingRoutes(this.getUIContext().getHostContext(), params);
        routePoints = this.extractRoutePoints(result);
      } else if (this.selectedNavMode === NavMode.CYCLING) {
        const params: navi.RouteParams = { origins: [origin], destination, language: "zh_CN" };
        const result = await navi.getCyclingRoutes(this.getUIContext().getHostContext(), params);
        routePoints = this.extractRoutePoints(result);
      }

      if (routePoints.length > 0) {
        const polylineOption: mapCommon.MapPolylineOptions = {
          points: routePoints,
          color: routeColor,
          width: 10,
          zIndex: 5
        };
        this.currentPolyline = await this.mapController.addPolyline(polylineOption);
        this.fitRouteBounds(routePoints);
      } else {
        this.drawFallbackRoute(routeColor);
      }
    } catch (e) {
      console.error('MapDebug', '路线规划失败: ' + JSON.stringify(e));
      this.drawFallbackRoute(routeColor);
    }
  }

  fitRouteBounds(points: Array<mapCommon.LatLng>) {
    if (!this.mapController || points.length === 0) return;

    let minLat = points[0].latitude, maxLat = points[0].latitude;
    let minLng = points[0].longitude, maxLng = points[0].longitude;

    for (const p of points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    const centerLat = (minLat + maxLat) / 2;
    const centerLng = (minLng + maxLng) / 2;
    const maxDiff = Math.max(maxLat - minLat, maxLng - minLng);

    let zoom = 15;
    if (maxDiff > 0.5) zoom = 10;
    else if (maxDiff > 0.2) zoom = 11;
    else if (maxDiff > 0.1) zoom = 12;
    else if (maxDiff > 0.05) zoom = 13;
    else if (maxDiff > 0.02) zoom = 14;

    const cameraUpdate = map.newCameraPosition({ target: { latitude: centerLat, longitude: centerLng }, zoom });
    this.mapController.animateCamera(cameraUpdate);
  }


  extractRoutePoints(result: navi.RouteResult): Array<mapCommon.LatLng> {
    const points: Array<mapCommon.LatLng> = [];
    if (result.routes && result.routes.length > 0) {
      const route = result.routes[0];

      if (route.steps && route.steps.length > 0) {
        let totalDistance = 0, totalDuration = 0;
        for (const step of route.steps) {
          if (step.distance) totalDistance += step.distance;
          if (step.durationInTraffic) totalDuration += step.durationInTraffic;
          else if (step.duration) totalDuration += step.duration;
        }
        this.routeDistance = totalDistance;
        this.routeDuration = totalDuration;
      }

      if (route.overviewPolyline && route.overviewPolyline.length > 0) {
        return route.overviewPolyline;
      }

      if (route.steps && route.steps.length > 0) {
        for (const step of route.steps) {
          if (step.roads && step.roads.length > 0) {
            for (const road of step.roads) {
              if (road.polyline && road.polyline.length > 0) {
                points.push(...road.polyline);
              }
            }
          }
        }
      }
    }
    return points;
  }

  async drawFallbackRoute(routeColor: number) {
    if (!this.mapController) return;

    const points: Array<mapCommon.LatLng> = [
      { latitude: this.startLatitude, longitude: this.startLongitude },
      { latitude: this.endLatitude, longitude: this.endLongitude }
    ];

    this.routeDistance = this.calculateStraightDistance() * 1000;
    this.routeDuration = this.estimateTimeByDistance() * 60;

    const polylineOption: mapCommon.MapPolylineOptions = { points, color: routeColor, width: 10, zIndex: 5 };
    try {
      this.currentPolyline = await this.mapController.addPolyline(polylineOption);
      this.fitRouteBounds(points);
    } catch (e) {
      console.error('MapDebug', '绘制备用路线失败');
    }
  }

  clearRoute() {
    this.isRouteMode = false;
    this.endLatitude = 0;
    this.endLongitude = 0;
    this.endAddress = '';
    this.routeDistance = 0;
    this.routeDuration = 0;

    if (this.endMarker) { this.endMarker.remove(); this.endMarker = null; }
    if (this.currentPolyline) { this.currentPolyline.remove(); this.currentPolyline = null; }
  }

  launchExternalMap(mode: NavMode) {
    let uri = 'maps://route/plan?';
    uri += `sname=${encodeURIComponent(this.startAddress)}&slat=${this.startLatitude}&slon=${this.startLongitude}`;
    uri += `&dname=${encodeURIComponent(this.endAddress)}&dlat=${this.endLatitude}&dlon=${this.endLongitude}`;

    let typeParam = '';
    switch (mode) {
      case NavMode.DRIVING: typeParam = 'drive'; break;
      case NavMode.WALKING: typeParam = 'walk'; break;
      case NavMode.CYCLING: typeParam = 'cycle'; break;
      case NavMode.TAXI: typeParam = 'taxi'; break;
    }
    uri += `&type=${typeParam}`;

    const want: Want = { action: 'ohos.want.action.viewData', uri };
    this.context.startAbility(want).catch((err: BusinessError) => {
      console.error('MapDebug', `启动导航失败: ${JSON.stringify(err)}`);
    });
  }


  formatDistance(): string {
    if (this.routeDistance > 0) {
      if (this.routeDistance >= 1000) return `${(this.routeDistance / 1000).toFixed(1)}km`;
      return `${Math.round(this.routeDistance)}m`;
    }
    return `${this.calculateStraightDistance().toFixed(1)}km`;
  }

  formatDuration(): string {
    if (this.routeDuration > 0) {
      const minutes = Math.round(this.routeDuration / 60);
      if (minutes >= 60) {
        const hours = Math.floor(minutes / 60);
        const mins = minutes % 60;
        return `${hours}h${mins}min`;
      }
      return `${minutes}min`;
    }
    return `${this.estimateTimeByDistance()}min`;
  }

  calculateStraightDistance(): number {
    const R = 6371;
    const dLat = (this.endLatitude - this.startLatitude) * Math.PI / 180;
    const dLon = (this.startLongitude - this.endLongitude) * Math.PI / 180;
    const a = Math.sin(dLat / 2)**2 +
      Math.cos(this.startLatitude * Math.PI / 180) *
      Math.cos(this.endLatitude * Math.PI / 180) *
      Math.sin(dLon / 2)**2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  estimateTimeByDistance(): number {
    const dist = this.calculateStraightDistance();
    let speed = 40;
    if (this.selectedNavMode === NavMode.WALKING) speed = 5;
    if (this.selectedNavMode === NavMode.CYCLING) speed = 15;
    return Math.round((dist / speed) * 60);
  }

  async reqPermissions() {
    const permissions: Array<Permissions> = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION'];
    const atManager = abilityAccessCtrl.createAtManager();

    try {
      const result = await atManager.requestPermissionsFromUser(this.context, permissions);
      const isGranted = result.authResults.every(s => s === 0);
      if (isGranted) {
        this.startLocationService();
        if (this.mapController) this.mapController.setMyLocationEnabled(true);
      } else {
        this.currentAddress = '需要定位权限';
      }
    } catch (err) {
      console.error('MapDebug', `权限请求失败: ${JSON.stringify(err)}`);
    }
  }

  startLocationService() {
    let isInitialMove = true;
    locationService.startLocationUpdates(async (loc) => {
      this.currentLatitude = loc.latitude;
      this.currentLongitude = loc.longitude;

      if (this.isStartUsingCurrentLocation) {
        this.startLatitude = loc.latitude;
        this.startLongitude = loc.longitude;
      }

      if (this.mapController && isInitialMove) {
        const cameraUpdate = map.newCameraPosition({ target: { latitude: loc.latitude, longitude: loc.longitude }, zoom: 15 });
        this.mapController.animateCamera(cameraUpdate);
        isInitialMove = false;
      }

      try {
        const addr = await locationService.getAddressFromCoords(loc.latitude, loc.longitude);
        if (addr) {
          this.currentAddress = `${addr.locality || ''}${addr.subLocality || ''}${addr.roadName || ''}`;
        }
      } catch {}
    });
  }

  async moveToCurrentLocation() {
    const loc = await locationService.getCurrentPosition();
    if (loc && this.mapController) {
      this.currentLatitude = loc.latitude;
      this.currentLongitude = loc.longitude;
      const cameraUpdate = map.newCameraPosition({ target: { latitude: loc.latitude, longitude: loc.longitude }, zoom: 15 });
      this.mapController.animateCamera(cameraUpdate);
    }
  }
}
