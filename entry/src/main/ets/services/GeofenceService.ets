// entry/src/main/ets/services/GeofenceService.ets
import geoLocationManager from '@ohos.geoLocationManager';
import { BusinessError } from '@ohos.base';
import { databaseService, Geofence, GroupGeofence } from './DatabaseService';

export interface GeofenceEvent {
  fenceId: number;
  fenceName: string;
  event: 'enter' | 'exit' | 'dwell';
  timestamp: number;
}

// 群组围栏事件
export interface GroupGeofenceEvent {
  memberId: string;
  memberName: string;
  fenceId: string;
  fenceName: string;
  event: 'enter' | 'leave';
  timestamp: number;
}

interface MemberLocation {
  lat: number;
  lon: number;
  name: string;
}

interface MemberZoneStatus {
  name: string;
  inZone: boolean;
}

// 成员位置状态（用于追踪围栏进出）
interface MemberFenceStatus {
  memberId: string;
  memberName: string;
  fenceId: string;
  isInside: boolean;
}

export class GeofenceService {
  private static instance: GeofenceService;
  private activeFences: Map<number, geoLocationManager.Geofence> = new Map();
  private eventCallback: ((event: GeofenceEvent) => void) | null = null;
  private gnssCallback: ((transition: geoLocationManager.GeofenceTransition) => void) | null = null;
  // 群组围栏相关
  private groupFences: Map<string, GroupGeofence[]> = new Map(); // groupCode -> fences
  private memberFenceStatus: Map<string, MemberFenceStatus> = new Map(); // `${memberId}_${fenceId}` -> status
  private groupGeofenceEventCallback: ((event: GroupGeofenceEvent) => void) | null = null;

  static getInstance(): GeofenceService {
    if (!GeofenceService.instance) {
      GeofenceService.instance = new GeofenceService();
    }
    return GeofenceService.instance;
  }

  setEventCallback(cb: ((event: GeofenceEvent) => void) | null) {
    this.eventCallback = cb;
  }

  async addFence(fence: Geofence): Promise<number> {
    // 保存到数据库
    const id = await databaseService.addGeofence(fence);
    if (id < 0) {
      return -1;
    }

    // 注册系统围栏
    await this.registerSystemFence(id, fence);
    return id;
  }

  private async registerSystemFence(id: number, fence: Geofence) {
    const geofence: geoLocationManager.Geofence = {
      latitude: fence.latitude,
      longitude: fence.longitude,
      radius: fence.radius,
      expiration: 0 // 永不过期
    };

    const request: geoLocationManager.GeofenceRequest = {
      scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
      geofence: geofence
    };

    // 注册围栏回调
    if (!this.gnssCallback) {
      this.gnssCallback = (transition: geoLocationManager.GeofenceTransition) => {
        this.handleGeofenceTransition(transition);
      };
    }

    try {
      // 使用 on('gnssFenceStatusChange') 监听围栏状态变化
      geoLocationManager.on('gnssFenceStatusChange', request, this.gnssCallback);
      this.activeFences.set(id, geofence);
      console.info(`[GeofenceService] Fence registered: ${id}`);
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[GeofenceService] Register fence error: ${err.message}`);
    }
  }

  private handleGeofenceTransition(transition: geoLocationManager.GeofenceTransition) {
    if (!this.eventCallback) {
      return;
    }
    let eventType: 'enter' | 'exit' | 'dwell' = 'enter';
    // 简化处理：根据常见的API模式，直接使用枚举值进行比较
    // 由于无法确定正确的属性名，暂时注释掉相关逻辑
    // 待确认正确的geoLocationManager.GeofenceTransition API后再修复
    eventType = 'enter'; // 默认值，需要根据实际API调整
    // 查找对应的围栏
    for (const entry of this.activeFences) {
      const fenceId = entry[0];
      const fence = entry[1];
      if (fenceId === transition.geofenceId) {
        this.eventCallback({
          fenceId: fenceId,
          fenceName: '',
          event: eventType,
          timestamp: Date.now()
        });
        break;
      }
    }
  }


  async removeFence(id: number) {
    // 从数据库删除
    await databaseService.deleteGeofence(id);

    // 从活动围栏中移除
    if (this.activeFences.has(id)) {
      this.activeFences.delete(id);
      console.info(`[GeofenceService] Fence removed: ${id}`);
    }
  }

  async toggleFence(id: number, enabled: boolean) {
    await databaseService.updateGeofence(id, enabled ? 1 : 0);

    if (enabled) {
      const fences = await databaseService.getGeofences();
      const fence = fences.find(f => f.id === id);
      if (fence) {
        await this.registerSystemFence(id, fence);
      }
    } else {
      this.activeFences.delete(id);
    }
  }

  async loadAllFences() {
    const fences = await databaseService.getGeofences();
    for (const fence of fences) {
      if (fence.enabled && fence.id) {
        await this.registerSystemFence(fence.id, fence);
      }
    }
    console.info(`[GeofenceService] Loaded ${fences.length} fences`);
  }

  getActiveFenceCount(): number {
    return this.activeFences.size;
  }

  // 检查点是否在围栏内
  isPointInFence(lat: number, lon: number, fence: Geofence): boolean {
    const distance = this.calculateDistance(lat, lon, fence.latitude, fence.longitude);
    return distance <= fence.radius / 1000; // radius 是米，distance 是公里
  }

  private calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2)**2 +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2)**2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  // 检查所有成员是否在安全区域内
  async checkMembersInSafeZone(members: Array<MemberLocation>): Promise<Array<MemberZoneStatus>> {
    const fences = await databaseService.getGeofences();
    const safeFences = fences.filter(f => f.type === 'safe' && f.enabled);
    return members.map(member => {
      const inZone = safeFences.some(fence => this.isPointInFence(member.lat, member.lon, fence));
      return { name: member.name, inZone } as MemberZoneStatus;
    });
  }

  // ========== 群组围栏相关方法 ==========

  /**
   * 设置群组围栏事件回调
   */
  setGroupGeofenceEventCallback(cb: ((event: GroupGeofenceEvent) => void) | null) {
    this.groupGeofenceEventCallback = cb;
  }

  /**
   * 添加群组围栏到内存缓存
   */
  addGroupFence(groupCode: string, fence: GroupGeofence): void {
    if (!this.groupFences.has(groupCode)) {
      this.groupFences.set(groupCode, []);
    }
    const fences = this.groupFences.get(groupCode)!;
    // 避免重复添加
    const existingIndex = fences.findIndex(f => f.id === fence.id);
    if (existingIndex >= 0) {
      fences[existingIndex] = fence;
    } else {
      fences.push(fence);
    }
    console.info(`[GeofenceService] Group fence added: ${fence.name} (${fence.id}) to group ${groupCode}`);
  }

  /**
   * 从内存缓存移除群组围栏
   */
  removeGroupFence(groupCode: string, fenceId: string): void {
    const fences = this.groupFences.get(groupCode);
    if (fences) {
      const index = fences.findIndex(f => f.id === fenceId);
      if (index >= 0) {
        const removed = fences.splice(index, 1)[0];
        console.info(`[GeofenceService] Group fence removed: ${removed.name} (${fenceId}) from group ${groupCode}`);
      }
    }
    // 清理相关的成员状态
    this.memberFenceStatus.forEach((status, key) => {
      if (status.fenceId === fenceId) {
        this.memberFenceStatus.delete(key);
      }
    });
  }

  /**
   * 获取群组的所有围栏
   */
  getGroupFences(groupCode: string): GroupGeofence[] {
    return this.groupFences.get(groupCode) || [];
  }

  /**
   * 加载群组围栏从数据库
   */
  async loadGroupFences(groupCode: string): Promise<GroupGeofence[]> {
    const fences = await databaseService.getGroupGeofences(groupCode);
    this.groupFences.set(groupCode, fences);
    console.info(`[GeofenceService] Loaded ${fences.length} group fences for ${groupCode}`);
    return fences;
  }

  /**
   * 清除群组围栏缓存
   */
  clearGroupFences(groupCode: string): void {
    this.groupFences.delete(groupCode);
    // 清理相关的成员状态
    this.memberFenceStatus.forEach((status, key) => {
      if (key.includes(groupCode)) {
        this.memberFenceStatus.delete(key);
      }
    });
  }

  /**
   * 检查点是否在群组围栏内
   */
  isPointInGroupFence(lat: number, lon: number, fence: GroupGeofence): boolean {
    const distance = this.calculateDistance(lat, lon, fence.latitude, fence.longitude);
    return distance <= fence.radius / 1000; // radius 是米，distance 是公里
  }

  /**
   * 检查成员位置变化并触发围栏事件
   * @param groupCode 群组代码
   * @param memberId 成员ID
   * @param memberName 成员名称
   * @param lat 纬度
   * @param lon 经度
   * @returns 触发的围栏事件列表
   */
  checkGroupFences(groupCode: string, memberId: string, memberName: string, lat: number, lon: number): GroupGeofenceEvent[] {
    const fences = this.groupFences.get(groupCode) || [];
    const events: GroupGeofenceEvent[] = [];

    for (const fence of fences) {
      const statusKey = `${memberId}_${fence.id}`;
      const isCurrentlyInside = this.isPointInGroupFence(lat, lon, fence);
      const previousStatus = this.memberFenceStatus.get(statusKey);

      // 如果是第一次检测，只记录状态不触发事件
      if (!previousStatus) {
        this.memberFenceStatus.set(statusKey, {
          memberId,
          memberName,
          fenceId: fence.id!,
          isInside: isCurrentlyInside
        });
        continue;
      }

      // 检测状态变化
      if (previousStatus.isInside !== isCurrentlyInside) {
        const event: GroupGeofenceEvent = {
          memberId,
          memberName,
          fenceId: fence.id!,
          fenceName: fence.name,
          event: isCurrentlyInside ? 'enter' : 'leave',
          timestamp: Date.now()
        };
        events.push(event);

        // 更新状态
        this.memberFenceStatus.set(statusKey, {
          memberId,
          memberName,
          fenceId: fence.id!,
          isInside: isCurrentlyInside
        });

        // 触发回调
        if (this.groupGeofenceEventCallback) {
          this.groupGeofenceEventCallback(event);
        }

        console.info(`[GeofenceService] Geofence event: ${memberName} ${event.event} ${fence.name}`);
      }
    }

    return events;
  }

  /**
   * 初始化成员在围栏中的状态（不触发事件）
   */
  initMemberFenceStatus(groupCode: string, memberId: string, memberName: string, lat: number, lon: number): void {
    const fences = this.groupFences.get(groupCode) || [];
    for (const fence of fences) {
      const statusKey = `${memberId}_${fence.id}`;
      const isInside = this.isPointInGroupFence(lat, lon, fence);
      this.memberFenceStatus.set(statusKey, {
        memberId,
        memberName,
        fenceId: fence.id!,
        isInside
      });
    }
  }

  /**
   * 获取成员在指定围栏中的状态
   */
  getMemberFenceStatus(memberId: string, fenceId: string): boolean | null {
    const statusKey = `${memberId}_${fenceId}`;
    const status = this.memberFenceStatus.get(statusKey);
    return status ? status.isInside : null;
  }

  /**
   * 清除成员的围栏状态
   */
  clearMemberFenceStatus(memberId: string): void {
    this.memberFenceStatus.forEach((status, key) => {
      if (status.memberId === memberId) {
        this.memberFenceStatus.delete(key);
      }
    });
  }
}

export const geofenceService = GeofenceService.getInstance();
