// entry/src/main/ets/services/SOSService.ets
import geoLocationManager from '@ohos.geoLocationManager';
import { batteryInfo } from '@kit.BasicServicesKit';
import { BusinessError } from '@ohos.base';
import { TrackPoint, SOSRecord, databaseService } from './DatabaseService';
import { trackingService } from './TrackingService';

export interface SOSMessage {
  latitude: number;
  longitude: number;
  altitude: number;
  battery: number;
  timestamp: number;
  message: string;
  recentTrack: TrackPoint[];
}

interface DeviceStatus {
  battery: number;
  charging: boolean;
}

export class SOSService {
  private static instance: SOSService;
  private sosCallback: ((msg: SOSMessage) => void) | null = null;

  static getInstance(): SOSService {
    if (!SOSService.instance) {
      SOSService.instance = new SOSService();
    }
    return SOSService.instance;
  }

  setSOSCallback(cb: ((msg: SOSMessage) => void) | null) {
    this.sosCallback = cb;
  }

  async triggerSOS(customMessage?: string): Promise<SOSMessage | null> {
    try {
      // 获取当前位置
      const request: geoLocationManager.CurrentLocationRequest = {
        priority: geoLocationManager.LocationRequestPriority.ACCURACY,
        scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
        maxAccuracy: 0,
        timeoutMs: 10000
      };

      const location = await geoLocationManager.getCurrentLocation(request);

      // 获取电量
      const battery = batteryInfo.batterySOC;

      // 获取最近5分钟的轨迹片段（用于救援参考）
      const recentTrack = await trackingService.getRecentTrackPoints(5);

      const sosMsg: SOSMessage = {
        latitude: location.latitude,
        longitude: location.longitude,
        altitude: location.altitude || 0,
        battery: battery,
        timestamp: Date.now(),
        message: customMessage || '紧急求助！请立即查看我的位置！',
        recentTrack: recentTrack
      };

      // 触发回调
      if (this.sosCallback) {
        this.sosCallback(sosMsg);
      }

      console.info('[SOSService] SOS triggered:', JSON.stringify(sosMsg));
      return sosMsg;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[SOSService] SOS error: ${err.message}`);
      return null;
    }
  }

  /**
   * 保存SOS记录到本地数据库
   * @param msg SOS消息
   * @param sentToGroup 是否已发送到群组
   * @param groupCode 群组代码（如果已发送）
   * @returns 记录ID
   */
  async saveSOSToLocal(msg: SOSMessage, sentToGroup: boolean = false, groupCode: string = ''): Promise<number> {
    try {
      const record: SOSRecord = {
        latitude: msg.latitude,
        longitude: msg.longitude,
        altitude: msg.altitude,
        battery: msg.battery,
        message: msg.message,
        recentTrack: JSON.stringify(msg.recentTrack),
        timestamp: msg.timestamp,
        sentToGroup: sentToGroup ? 1 : 0,
        groupCode: groupCode
      };

      const id = await databaseService.addSOSRecord(record);
      console.info(`[SOSService] SOS saved to local, id: ${id}, sentToGroup: ${sentToGroup}`);
      return id;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[SOSService] Save SOS error: ${err.message}`);
      return -1;
    }
  }

  /**
   * 获取本地SOS记录列表
   * @returns SOS记录列表
   */
  async getLocalSOSRecords(): Promise<SOSRecord[]> {
    return await databaseService.getSOSRecords();
  }

  /**
   * 删除本地SOS记录
   * @param id 记录ID
   */
  async deleteLocalSOSRecord(id: number): Promise<void> {
    await databaseService.deleteSOSRecord(id);
  }

  /**
   * 验证SOS消息数据完整性
   * 确保包含位置、电量、时间戳三个必要字段
   * @param msg SOS消息
   * @returns 是否完整
   */
  validateSOSMessage(msg: SOSMessage): boolean {
    // 检查位置（经纬度在有效范围内）
    const hasValidLocation = typeof msg.latitude === 'number' &&
      typeof msg.longitude === 'number' &&
      msg.latitude >= -90 && msg.latitude <= 90 &&
      msg.longitude >= -180 && msg.longitude <= 180;

    // 检查电量（0-100范围）
    const hasValidBattery = typeof msg.battery === 'number' &&
      msg.battery >= 0 && msg.battery <= 100;

    // 检查时间戳（正整数）
    const hasValidTimestamp = typeof msg.timestamp === 'number' &&
      msg.timestamp > 0;

    return hasValidLocation && hasValidBattery && hasValidTimestamp;
  }

  // 格式化SOS消息用于分享
  formatSOSMessage(msg: SOSMessage): string {
    const time = new Date(msg.timestamp).toLocaleString();
    let text = `🆘 紧急求助\n`;
    text += `📍 位置: ${msg.latitude.toFixed(6)}, ${msg.longitude.toFixed(6)}\n`;
    text += `🔋 电量: ${msg.battery}%\n`;
    text += `⏰ 时间: ${time}\n`;
    text += `💬 消息: ${msg.message}\n`;

    if (msg.recentTrack.length > 0) {
      text += `\n📌 最近轨迹:\n`;
      msg.recentTrack.slice(-3).forEach((p, i) => {
        text += `  ${i + 1}. ${p.latitude.toFixed(6)}, ${p.longitude.toFixed(6)}\n`;
      });
    }

    return text;
  }

  // 获取设备状态
  getDeviceStatus(): DeviceStatus {
    return {
      battery: batteryInfo.batterySOC,
      charging: batteryInfo.chargingStatus === 1 || // CHARGING状态
        batteryInfo.chargingStatus === 3 // FULL状态
    } as DeviceStatus;
  }
}

export const sosService = SOSService.getInstance();
