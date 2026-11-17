// entry/src/main/ets/services/LocationService.ets
import geoLocationManager from '@ohos.geoLocationManager';
import { BusinessError } from '@ohos.base';

export class LocationService {
  private static instance: LocationService;
  // 修复: 显式定义 callback 类型，且初始值设为 null 便于逻辑判断
  private callback: ((loc: geoLocationManager.Location) => void) | null = null;

  static getInstance(): LocationService {
    if (!LocationService.instance) {
      LocationService.instance = new LocationService();
    }
    return LocationService.instance;
  }

  /**
   * 构建持续定位请求配置 (用于 on 监听)
   */
  private buildContinuousRequest(): geoLocationManager.LocationRequest {
    const request: geoLocationManager.LocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
      timeInterval: 3, // 这里的单位是 秒(s)，不是毫秒。API文挡定义为 interval(s)
      distanceInterval: 0,
      maxAccuracy: 0
    };
    return request;
  }

  /**
   * 获取单次当前位置
   * 注意：单次定位使用 CurrentLocationRequest，它没有 timeInterval 字段
   */
  async getCurrentPosition(): Promise<geoLocationManager.Location | null> {
    try {
      // 修复: 显式定义 CurrentLocationRequest 类型对象
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        maxAccuracy: 0,
        timeoutMs: 5000 // 单次定位通常设置超时时间
      };

      console.info("[DEBUG] getCurrentPosition request:", JSON.stringify(request));
      const result = await geoLocationManager.getCurrentLocation(request);
      console.info('[LocationService] current location -> ', JSON.stringify(result));

      return result;
    } catch (error) {
      // 修复: 显式转换错误类型
      const err = error as BusinessError;
      console.error(`[LocationService] getCurrentPosition error code: ${err.code}, msg: ${err.message}`);
      return null;
    }
  }

  /** 开启持续定位 **/
  startLocationUpdates(cb: (loc: geoLocationManager.Location) => void) {
    if (this.callback !== null) {
      return; // 防止重复注册
    }
    this.callback = cb;

    // 获取配置对象
    const req = this.buildContinuousRequest();

    try {
      geoLocationManager.on('locationChange', req, this.callback);
      console.info('[LocationService] listening started');
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[LocationService] start error: ${err.message}`);
    }
  }

  /**停止持续定位**/
  stopLocationUpdates() {
    if (this.callback) {
      try {
        geoLocationManager.off('locationChange', this.callback);
        this.callback = null;
        console.info('[LocationService] listening stopped');
      } catch (error) {
        const err = error as BusinessError;
        console.error(`[LocationService] stop error: ${err.message}`);
      }
    }
  }

  /**逆地理编码：将坐标转换为详细地址**/
  async getAddressFromCoords(lat: number, lon: number): Promise<geoLocationManager.GeoAddress | null> {
    const reverseGeocodeRequest: geoLocationManager.ReverseGeoCodeRequest = {
      latitude: lat,
      longitude: lon,
      maxItems: 1, // 只需要一个最精确的地址
      locale: 'zh-CN' // 指定中文
    };

    try {
      const addresses = await geoLocationManager.getAddressesFromLocation(reverseGeocodeRequest);
      if (addresses && addresses.length > 0) {
        console.info(`[LocationService] Address found: ${addresses[0].placeName}`);
        return addresses[0];
      }
      return null;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[LocationService] Geocode error: ${err.message}`);
      return null;
    }
  }
}

export const locationService = LocationService.getInstance();