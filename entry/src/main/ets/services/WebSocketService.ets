// entry/src/main/ets/services/WebSocketService.ets
import webSocket from '@ohos.net.webSocket';
import { BusinessError } from '@ohos.base';
import { batteryInfo } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';

// 位置共享时长类型
export type ShareDuration = '15min' | '1hour' | '4hours' | 'always';

// 共享时长对应的毫秒数
export const SHARE_DURATION_MS: Record<ShareDuration, number> = {
  '15min': 15 * 60 * 1000,
  '1hour': 60 * 60 * 1000,
  '4hours': 4 * 60 * 60 * 1000,
  'always': 0  // 0 表示永不过期
};

// 群组围栏接口
export interface GroupGeofenceData {
  id?: string;
  groupCode?: string;
  name: string;
  latitude: number;
  longitude: number;
  radius: number;
  type: string; // safe, warning
  creatorId?: string;
  createTime?: number;
}

// 围栏事件接口
export interface GeofenceEventData {
  memberId: string;
  memberName: string;
  fenceId: string;
  fenceName: string;
  event: 'enter' | 'leave';
  timestamp: number;
}

// 消息类型
export interface WSMessage {
  type: string;
  odId?: string;
  name?: string;
  groupName?: string;
  groupCode?: string;
  groups?: GroupInfo[];
  group?: GroupInfo | GroupData;
  member?: MemberInfo;
  latitude?: number;
  longitude?: number;
  battery?: number;
  signal?: number;
  shareExpireTime?: number;
  duration?: ShareDuration;
  targetOdId?: string;
  geofence?: GroupGeofenceData;
  fenceId?: string;
  fenceName?: string;
  geofenceEvent?: GeofenceEventData;
  message?: string;
  recentTrack?: Object[];
  reason?: string;
  error?: boolean;
  from?: MessageFrom;
  location?: MessageLocation;
  timestamp?: number;
  data?: Object | string | number | boolean;
}

// 群组信息
export interface GroupInfo {
  code: string;
  name: string;
  memberCount: number;
  isOwner: boolean;
}

// 成员信息
export interface MemberInfo {
  odId: string;
  name: string;
  role: number;
  latitude: number;
  longitude: number;
  battery: number;
  signal: number;
  lastUpdate: number;
  isOnline?: boolean;
}

// SOS警报发送者信息
export interface SOSAlertFrom {
  odId: string;
  name: string;
}

// SOS警报位置信息
export interface SOSAlertLocation {
  latitude: number;
  longitude: number;
}

// SOS警报轨迹点
export interface SOSTrackPoint {
  latitude: number;
  longitude: number;
  altitude: number;
  timestamp: number;
}

// SOS警报
export interface SOSAlert {
  from: SOSAlertFrom;
  location: SOSAlertLocation;
  battery: number;
  message: string;
  timestamp: number;
  recentTrack?: SOSTrackPoint[]; // 最近5分钟轨迹片段
}

// 消息发送者信息
export interface MessageFrom {
  odId: string;
  name: string;
}

// 消息位置信息
export interface MessageLocation {
  latitude: number;
  longitude: number;
}

// 群组数据信息
export interface GroupData {
  members: MemberInfo[];
}

// 回调类型
export type MessageCallback = (msg: WSMessage) => void;

export type ConnectionCallback = (connected: boolean) => void;

// 位置共享会话信息
export interface ShareSession {
  groupCode: string;
  duration: ShareDuration;
  startTime: number;
  expireTime: number; // 0 表示永不过期
  isActive: boolean;
}

export class WebSocketService {
  private static instance: WebSocketService;
  private ws: webSocket.WebSocket | null = null;
  private serverUrl: string = '';
  private isConnected: boolean = false;
  private reconnectTimer: number = -1;
  private heartbeatTimer: number = -1;
  // 用户信息
  private odId: string = '';
  private userName: string = '';
  // 回调
  private messageCallbacks: Map<string, MessageCallback[]> = new Map();
  private connectionCallback: ConnectionCallback | null = null;
  // 当前群组
  private currentGroups: GroupInfo[] = [];
  // 位置共享会话
  private shareSessions: Map<string, ShareSession> = new Map();
  private shareExpiryCheckTimer: number = -1;

  static getInstance(): WebSocketService {
    if (!WebSocketService.instance) {
      WebSocketService.instance = new WebSocketService();
    }
    return WebSocketService.instance;
  }

  // 初始化用户信息
  init(userName: string) {
    // 使用设备ID作为唯一标识
    this.odId = deviceInfo.udid || `device_${Date.now()}`;
    this.userName = userName;
    console.info(`[WebSocket] Init: ${userName} (${this.odId})`);
  }

  getOdId(): string {
    return this.odId;
  }

  getUserName(): string {
    return this.userName;
  }

  // 连接服务器
  async connect(serverUrl: string): Promise<boolean> {
    this.serverUrl = serverUrl;

    if (this.ws) {
      try {
        this.ws.close();
      } catch (e) {
        console.warn('[WebSocket] Close error:', (e as BusinessError).message);
      }
      this.ws = null;
    }

    return new Promise((resolve) => {
      try {
        this.ws = webSocket.createWebSocket();

        this.ws.on('open', () => {
          console.info('[WebSocket] Connected to ' + serverUrl);
          this.isConnected = true;
          this.connectionCallback?.(true);

          // 注册
          this.send({
            type: 'register',
            odId: this.odId,
            name: this.userName
          });

          // 启动心跳
          this.startHeartbeat();
          resolve(true);
        });
        this.ws.on('message', (err, data) => {
          if (err) {
            console.error('[WebSocket] Message error:', err.message);
            return;
          }
          if (typeof data === 'string') {
            this.handleMessage(data);
          } else if (data instanceof ArrayBuffer) {
            // 在ArkTS中，ArrayBuffer可以直接转换为字符串处理
            // 或者只处理字符串数据，忽略二进制数据
            console.warn('[WebSocket] Received ArrayBuffer data, skipping binary message');
          }
        });

        this.ws.on('close', () => {
          console.info('[WebSocket] Disconnected');
          this.isConnected = false;
          this.connectionCallback?.(false);
          this.stopHeartbeat();
          // 不自动重连，让用户手动重连
        });

        this.ws.on('error', (err) => {
          console.error('[WebSocket] Error:', JSON.stringify(err));
          this.isConnected = false;
          resolve(false);
        });

        // 使用回调方式连接
        this.ws.connect(serverUrl, (err: BusinessError, connected: boolean) => {
          if (err) {
            console.error('[WebSocket] Connect callback error:', JSON.stringify(err));
            this.isConnected = false;
            resolve(false);
            return;
          }
          console.info('[WebSocket] Connect callback success:', connected);
          // 连接成功会触发 'open' 事件
        });
      } catch (e) {
        const err = e as BusinessError;
        console.error('[WebSocket] Connect error:', err.message);
        resolve(false);
      }
    });
  }


  // 断开连接
  disconnect() {
    this.stopHeartbeat();
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.ws) {
      try {
        this.ws.close();
      } catch (e) {
      }
      this.ws = null;
    }
    this.isConnected = false;
  }

  // 发送消息
  send(msg: WSMessage): boolean {
    if (!this.ws || !this.isConnected) {
      console.warn('[WebSocket] Not connected');
      return false;
    }
    try {
      this.ws.send(JSON.stringify(msg));
      return true;
    } catch (e) {
      console.error('[WebSocket] Send error:', (e as BusinessError).message);
      return false;
    }
  }

  // 处理收到的消息
  private handleMessage(data: string) {
    try {
      const msg = JSON.parse(data) as WSMessage;
      console.info('[WebSocket] Received:', msg.type);

      // 处理注册成功
      if (msg.type === 'registerSuccess') {
        this.currentGroups = msg.groups as GroupInfo[];
      }

      // 触发回调
      const callbacks = this.messageCallbacks.get(msg.type);
      if (callbacks) {
        callbacks.forEach(cb => cb(msg));
      }

      // 触发通用回调
      const allCallbacks = this.messageCallbacks.get('*');
      if (allCallbacks) {
        allCallbacks.forEach(cb => cb(msg));
      }
    } catch (e) {
      console.error('[WebSocket] Parse error:', (e as BusinessError).message);
    }
  }

  // 注册消息回调
  on(type: string, callback: MessageCallback) {
    if (!this.messageCallbacks.has(type)) {
      this.messageCallbacks.set(type, []);
    }
    this.messageCallbacks.get(type)?.push(callback);
  }

  // 移除消息回调
  off(type: string, callback?: MessageCallback) {
    if (!callback) {
      this.messageCallbacks.delete(type);
    } else {
      const callbacks = this.messageCallbacks.get(type);
      if (callbacks) {
        const index = callbacks.indexOf(callback);
        if (index !== -1) {
          callbacks.splice(index, 1);
        }
      }
    }
  }

  // 设置连接状态回调
  setConnectionCallback(callback: ConnectionCallback | null) {
    this.connectionCallback = callback;
  }

  // 心跳
  private startHeartbeat() {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnected) {
        this.send({ type: 'ping' });
      }
    }, 30000);
  }

  private stopHeartbeat() {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  // 重连
  private scheduleReconnect() {
    if (this.reconnectTimer !== -1) {
      return;
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      if (!this.isConnected && this.serverUrl) {
        console.info('[WebSocket] Reconnecting...');
        this.connect(this.serverUrl);
      }
    }, 5000);
  }

  // ========== 业务方法 ==========

  // 创建群组
  createGroup(groupName: string) {
    this.send({
      type: 'createGroup',
      odId: this.odId,
      name: this.userName,
      groupName
    });
  }

  // 加入群组
  joinGroup(groupCode: string) {
    this.send({
      type: 'joinGroup',
      odId: this.odId,
      name: this.userName,
      groupCode
    });
  }

  // 离开群组
  leaveGroup(groupCode: string) {
    this.send({
      type: 'leaveGroup',
      odId: this.odId,
      groupCode
    });
  }

  // 更新位置
  updateLocation(groupCode: string, latitude: number, longitude: number, shareExpireTime?: number) {
    this.send({
      type: 'updateLocation',
      odId: this.odId,
      groupCode,
      latitude,
      longitude,
      battery: batteryInfo.batterySOC,
      signal: 4, // TODO: 获取真实信号强度
      shareExpireTime
    });
  }

  // 更新状态
  updateStatus(groupCode: string) {
    this.send({
      type: 'updateStatus',
      odId: this.odId,
      groupCode,
      battery: batteryInfo.batterySOC,
      signal: 4
    });
  }

  // 发送SOS
  sendSOS(groupCode: string, latitude: number, longitude: number, message: string, recentTrack?: Object[]) {
    this.send({
      type: 'sos',
      odId: this.odId,
      groupCode,
      latitude,
      longitude,
      battery: batteryInfo.batterySOC,
      message,
      recentTrack
    });
  }

  // 获取群组信息
  getGroupInfo(groupCode: string) {
    this.send({
      type: 'getGroupInfo',
      odId: this.odId,
      groupCode
    });
  }

  // 踢出成员
  kickMember(groupCode: string, targetOdId: string) {
    this.send({
      type: 'kickMember',
      odId: this.odId,
      groupCode,
      targetOdId
    });
  }

  // 添加围栏 (旧方法，保留兼容性)
  addGeofence(groupCode: string, geofence: GroupGeofenceData) {
    this.send({
      type: 'addGeofence',
      odId: this.odId,
      groupCode,
      geofence
    });
  }

  // ========== 群组围栏方法 ==========

  /**
   * 添加群组围栏
   * @param groupCode 群组代码
   * @param geofence 围栏数据
   */
  addGroupGeofence(groupCode: string, geofence: GroupGeofenceData): void {
    this.send({
      type: 'addGroupGeofence',
      odId: this.odId,
      groupCode,
      geofence: {
        id: geofence.id,
        groupCode: geofence.groupCode,
        name: geofence.name,
        latitude: geofence.latitude,
        longitude: geofence.longitude,
        radius: geofence.radius,
        type: geofence.type,
        creatorId: this.odId,
        createTime: Date.now()
      }
    });
  }

  /**
   * 删除群组围栏
   * @param groupCode 群组代码
   * @param fenceId 围栏ID
   */
  removeGroupGeofence(groupCode: string, fenceId: string): void {
    this.send({
      type: 'removeGroupGeofence',
      odId: this.odId,
      groupCode,
      fenceId
    });
  }

  /**
   * 通知围栏事件
   * @param groupCode 群组代码
   * @param event 围栏事件数据
   */
  notifyGeofenceEvent(groupCode: string, event: GeofenceEventData): void {
    this.send({
      type: 'geofenceEvent',
      odId: this.odId,
      groupCode,
      geofenceEvent: event
    });
  }

  // 获取连接状态
  getIsConnected(): boolean {
    return this.isConnected;
  }

  // 获取当前群组列表
  getGroups(): GroupInfo[] {
    return this.currentGroups;
  }

  // ========== 位置共享时效控制方法 ==========

  /**
   * 开始位置共享
   * @param groupCode 群组代码
   * @param duration 共享时长
   * @returns 过期时间戳（0表示永不过期）
   */
  startLocationSharing(groupCode: string, duration: ShareDuration): number {
    const now = Date.now();
    const durationMs = SHARE_DURATION_MS[duration];
    const expireTime = durationMs > 0 ? now + durationMs : 0;

    const session: ShareSession = {
      groupCode,
      duration,
      startTime: now,
      expireTime,
      isActive: true
    };

    this.shareSessions.set(groupCode, session);

    // 通知服务器开始共享
    this.send({
      type: 'startSharing',
      odId: this.odId,
      groupCode,
      duration,
      shareExpireTime: expireTime
    });

    // 启动过期检查定时器
    this.startShareExpiryCheck();

    console.info(`[WebSocket] Started location sharing for ${groupCode}, duration: ${duration}, expires: ${expireTime >
      0 ? new Date(expireTime).toISOString() : 'never'}`);

    return expireTime;
  }

  /**
   * 停止位置共享
   * @param groupCode 群组代码
   */
  stopLocationSharing(groupCode: string): void {
    const session = this.shareSessions.get(groupCode);
    if (session) {
      session.isActive = false;
      this.shareSessions.delete(groupCode);
    }

    // 通知服务器停止共享
    this.send({
      type: 'stopSharing',
      odId: this.odId,
      groupCode
    });

    console.info(`[WebSocket] Stopped location sharing for ${groupCode}`);
  }

  /**
   * 检查位置共享是否过期
   * @param groupCode 群组代码
   * @returns true 如果共享已过期或不存在
   */
  isShareExpired(groupCode: string): boolean {
    const session = this.shareSessions.get(groupCode);
    if (!session || !session.isActive) {
      return true;
    }

    // expireTime 为 0 表示永不过期
    if (session.expireTime === 0) {
      return false;
    }

    return Date.now() > session.expireTime;
  }

  /**
   * 获取共享会话信息
   * @param groupCode 群组代码
   * @returns 共享会话信息或 null
   */
  getShareSession(groupCode: string): ShareSession | null {
    return this.shareSessions.get(groupCode) || null;
  }

  /**
   * 获取共享剩余时间（毫秒）
   * @param groupCode 群组代码
   * @returns 剩余时间毫秒数，0表示永不过期，-1表示已过期或不存在
   */
  getShareRemainingTime(groupCode: string): number {
    const session = this.shareSessions.get(groupCode);
    if (!session || !session.isActive) {
      return -1;
    }

    // 永不过期
    if (session.expireTime === 0) {
      return 0;
    }

    const remaining = session.expireTime - Date.now();
    return remaining > 0 ? remaining : -1;
  }

  /**
   * 启动共享过期检查定时器
   */
  private startShareExpiryCheck(): void {
    if (this.shareExpiryCheckTimer !== -1) {
      return; // 已经在运行
    }

    this.shareExpiryCheckTimer = setInterval(() => {
      this.checkShareExpiry();
    }, 10000); // 每10秒检查一次
  }

  /**
   * 停止共享过期检查定时器
   */
  private stopShareExpiryCheck(): void {
    if (this.shareExpiryCheckTimer !== -1) {
      clearInterval(this.shareExpiryCheckTimer);
      this.shareExpiryCheckTimer = -1;
    }
  }

  /**
   * 检查所有共享会话是否过期
   */
  private checkShareExpiry(): void {
    const now = Date.now();
    const expiredGroups: string[] = [];

    this.shareSessions.forEach((session, groupCode) => {
      if (session.isActive && session.expireTime > 0 && now > session.expireTime) {
        expiredGroups.push(groupCode);
      }
    });

    // 处理过期的共享
    for (const groupCode of expiredGroups) {
      console.info(`[WebSocket] Location sharing expired for ${groupCode}`);
      this.stopLocationSharing(groupCode);

      // 触发过期回调
      const callbacks = this.messageCallbacks.get('shareExpired');
      if (callbacks) {
        callbacks.forEach(cb => cb({
          type: 'shareExpired',
          groupCode
        }));
      }
    }

    // 如果没有活跃的共享会话，停止检查定时器
    if (this.shareSessions.size === 0) {
      this.stopShareExpiryCheck();
    }
  }

  /**
   * 更新位置（带过期检查）
   * 如果共享已过期，不会发送位置更新
   * @param groupCode 群组代码
   * @param latitude 纬度
   * @param longitude 经度
   * @returns true 如果位置更新已发送
   */
  updateLocationWithExpiryCheck(groupCode: string, latitude: number, longitude: number): boolean {
    // 检查共享是否过期
    if (this.isShareExpired(groupCode)) {
      console.info(`[WebSocket] Location update skipped - sharing expired for ${groupCode}`);
      return false;
    }

    const session = this.shareSessions.get(groupCode);
    const expireTime = session?.expireTime || 0;

    this.send({
      type: 'updateLocation',
      odId: this.odId,
      groupCode,
      latitude,
      longitude,
      battery: batteryInfo.batterySOC,
      signal: 4,
      shareExpireTime: expireTime
    });

    return true;
  }
}

export const wsService = WebSocketService.getInstance();
