// entry/src/main/ets/services/DatabaseService.ets
import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';

// 轨迹点
export interface TrackPoint {
  id?: number;
  trackId: number;
  latitude: number;
  longitude: number;
  altitude: number;
  speed: number;
  timestamp: number;
}

// 轨迹记录
export interface Track {
  id?: number;
  name: string;
  startTime: number;
  endTime: number;
  distance: number;
  duration: number;
  status: number; // 0-recording, 1-completed, 2-paused
}

// 地图标记
export interface MapMarker {
  id?: number;
  name: string;
  description: string;
  latitude: number;
  longitude: number;
  type: string; // water, rest, danger, camp, custom
  createTime: number;
}

// 电子围栏
export interface Geofence {
  id?: number;
  name: string;
  latitude: number;
  longitude: number;
  radius: number;
  type: string; // safe, warning
  enabled: number;
  createTime: number;
}

// 群组电子围栏
export interface GroupGeofence {
  id?: string;
  groupCode: string;
  name: string;
  latitude: number;
  longitude: number;
  radius: number;
  type: string; // safe, warning
  creatorId: string;
  createTime: number;
}

// 群组成员
export interface GroupMember {
  id?: number;
  groupId: number;
  name: string;
  avatar: string;
  role: number; // 0-admin, 1-member
  latitude: number;
  longitude: number;
  battery: number;
  signal: number;
  lastUpdate: number;
  shareExpireTime: number;
}

// 群组
export interface Group {
  id?: number;
  name: string;
  code: string;
  createTime: number;
  isOwner: number;
}

// 活动类型
export enum ActivityType {
  WALKING = 'walking',
  RUNNING = 'running',
  CYCLING = 'cycling',
  DRIVING = 'driving',
  OTHER = 'other'
}

// SOS记录（本地保存）
export interface SOSRecord {
  id?: number;
  latitude: number;
  longitude: number;
  altitude: number;
  battery: number;
  message: string;
  recentTrack: string; // JSON字符串存储轨迹点数组
  timestamp: number;
  sentToGroup: number; // 0-未发送到群组, 1-已发送
  groupCode: string; // 发送到的群组代码，空字符串表示未发送
}

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'outdoor_app.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const SQL_CREATE_TRACKS = `
  CREATE TABLE IF NOT EXISTS tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    startTime INTEGER NOT NULL,
    endTime INTEGER DEFAULT 0,
    distance REAL DEFAULT 0,
    duration INTEGER DEFAULT 0,
    status INTEGER DEFAULT 0
  )`;

const SQL_CREATE_TRACK_POINTS = `
  CREATE TABLE IF NOT EXISTS track_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    trackId INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude REAL DEFAULT 0,
    speed REAL DEFAULT 0,
    timestamp INTEGER NOT NULL
  )`;


const SQL_CREATE_MARKERS = `
  CREATE TABLE IF NOT EXISTS markers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    type TEXT DEFAULT 'custom',
    createTime INTEGER NOT NULL
  )`;

const SQL_CREATE_GEOFENCES = `
  CREATE TABLE IF NOT EXISTS geofences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    radius REAL NOT NULL,
    type TEXT DEFAULT 'safe',
    enabled INTEGER DEFAULT 1,
    createTime INTEGER NOT NULL
  )`;

const SQL_CREATE_GROUPS = `
  CREATE TABLE IF NOT EXISTS groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    createTime INTEGER NOT NULL,
    isOwner INTEGER DEFAULT 0
  )`;

const SQL_CREATE_MEMBERS = `
  CREATE TABLE IF NOT EXISTS group_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    groupId INTEGER NOT NULL,
    name TEXT NOT NULL,
    avatar TEXT,
    role INTEGER DEFAULT 1,
    latitude REAL DEFAULT 0,
    longitude REAL DEFAULT 0,
    battery INTEGER DEFAULT 100,
    signal INTEGER DEFAULT 4,
    lastUpdate INTEGER DEFAULT 0,
    shareExpireTime INTEGER DEFAULT 0
  )`;

const SQL_CREATE_GROUP_GEOFENCES = `
  CREATE TABLE IF NOT EXISTS group_geofences (
    id TEXT PRIMARY KEY,
    groupCode TEXT NOT NULL,
    name TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    radius REAL NOT NULL,
    type TEXT DEFAULT 'safe',
    creatorId TEXT NOT NULL,
    createTime INTEGER NOT NULL
  )`;

const SQL_CREATE_SOS_RECORDS = `
  CREATE TABLE IF NOT EXISTS sos_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude REAL DEFAULT 0,
    battery INTEGER NOT NULL,
    message TEXT,
    recentTrack TEXT,
    timestamp INTEGER NOT NULL,
    sentToGroup INTEGER DEFAULT 0,
    groupCode TEXT DEFAULT ''
  )`;

export class DatabaseService {
  private static instance: DatabaseService;
  private rdbStore: relationalStore.RdbStore | null = null;
  private isInitialized: boolean = false;

  static getInstance(): DatabaseService {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  async init(context: common.Context): Promise<boolean> {
    if (this.isInitialized && this.rdbStore) {
      return true;
    }

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
      await this.rdbStore.executeSql(SQL_CREATE_TRACKS);
      await this.rdbStore.executeSql(SQL_CREATE_TRACK_POINTS);
      await this.rdbStore.executeSql(SQL_CREATE_MARKERS);
      await this.rdbStore.executeSql(SQL_CREATE_GEOFENCES);
      await this.rdbStore.executeSql(SQL_CREATE_GROUPS);
      await this.rdbStore.executeSql(SQL_CREATE_MEMBERS);
      await this.rdbStore.executeSql(SQL_CREATE_GROUP_GEOFENCES);
      await this.rdbStore.executeSql(SQL_CREATE_SOS_RECORDS);
      this.isInitialized = true;
      console.info('[DatabaseService] initialized');
      return true;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[DatabaseService] init error: ${err.message}`);
      return false;
    }
  }

  // ========== 轨迹相关 ==========
  async createTrack(name: string): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      name: name,
      startTime: Date.now(),
      endTime: 0,
      distance: 0,
      duration: 0,
      status: 0
    };
    return await this.rdbStore.insert('tracks', bucket);
  }

  async updateTrack(id: number, data: Partial<Track>): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = {};
    if (data.endTime !== undefined) {
      bucket['endTime'] = data.endTime;
    }
    if (data.distance !== undefined) {
      bucket['distance'] = data.distance;
    }
    if (data.duration !== undefined) {
      bucket['duration'] = data.duration;
    }
    if (data.status !== undefined) {
      bucket['status'] = data.status;
    }

    const predicates = new relationalStore.RdbPredicates('tracks');
    predicates.equalTo('id', id);
    await this.rdbStore.update(bucket, predicates);
  }

  async getTracks(): Promise<Track[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('tracks');
    predicates.orderByDesc('startTime');
    const result = await this.rdbStore.query(predicates);
    const tracks: Track[] = [];
    while (result.goToNextRow()) {
      tracks.push({
        id: result.getLong(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        startTime: result.getLong(result.getColumnIndex('startTime')),
        endTime: result.getLong(result.getColumnIndex('endTime')),
        distance: result.getDouble(result.getColumnIndex('distance')),
        duration: result.getLong(result.getColumnIndex('duration')),
        status: result.getLong(result.getColumnIndex('status'))
      });
    }
    result.close();
    return tracks;
  }

  async deleteTrack(id: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('tracks');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
    // 同时删除轨迹点
    const pointPredicates = new relationalStore.RdbPredicates('track_points');
    pointPredicates.equalTo('trackId', id);
    await this.rdbStore.delete(pointPredicates);
  }


  // ========== 轨迹点相关 ==========
  async addTrackPoint(point: TrackPoint): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      trackId: point.trackId,
      latitude: point.latitude,
      longitude: point.longitude,
      altitude: point.altitude,
      speed: point.speed,
      timestamp: point.timestamp
    };
    return await this.rdbStore.insert('track_points', bucket);
  }

  async getTrackPoints(trackId: number): Promise<TrackPoint[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('track_points');
    predicates.equalTo('trackId', trackId).orderByAsc('timestamp');
    const result = await this.rdbStore.query(predicates);
    const points: TrackPoint[] = [];
    while (result.goToNextRow()) {
      points.push({
        id: result.getLong(result.getColumnIndex('id')),
        trackId: result.getLong(result.getColumnIndex('trackId')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        altitude: result.getDouble(result.getColumnIndex('altitude')),
        speed: result.getDouble(result.getColumnIndex('speed')),
        timestamp: result.getLong(result.getColumnIndex('timestamp'))
      });
    }
    result.close();
    return points;
  }

  // ========== 标记点相关 ==========
  async addMarker(marker: MapMarker): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      name: marker.name,
      description: marker.description,
      latitude: marker.latitude,
      longitude: marker.longitude,
      type: marker.type,
      createTime: marker.createTime || Date.now()
    };
    return await this.rdbStore.insert('markers', bucket);
  }

  async getMarkers(): Promise<MapMarker[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('markers');
    predicates.orderByDesc('createTime');
    const result = await this.rdbStore.query(predicates);
    const markers: MapMarker[] = [];
    while (result.goToNextRow()) {
      markers.push({
        id: result.getLong(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        description: result.getString(result.getColumnIndex('description')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        type: result.getString(result.getColumnIndex('type')),
        createTime: result.getLong(result.getColumnIndex('createTime'))
      });
    }
    result.close();
    return markers;
  }

  async deleteMarker(id: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('markers');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
  }

  // ========== 围栏相关 ==========
  async addGeofence(fence: Geofence): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      name: fence.name,
      latitude: fence.latitude,
      longitude: fence.longitude,
      radius: fence.radius,
      type: fence.type,
      enabled: fence.enabled,
      createTime: fence.createTime || Date.now()
    };
    return await this.rdbStore.insert('geofences', bucket);
  }

  async getGeofences(): Promise<Geofence[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('geofences');
    const result = await this.rdbStore.query(predicates);
    const fences: Geofence[] = [];
    while (result.goToNextRow()) {
      fences.push({
        id: result.getLong(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        radius: result.getDouble(result.getColumnIndex('radius')),
        type: result.getString(result.getColumnIndex('type')),
        enabled: result.getLong(result.getColumnIndex('enabled')),
        createTime: result.getLong(result.getColumnIndex('createTime'))
      });
    }
    result.close();
    return fences;
  }

  async updateGeofence(id: number, enabled: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = { enabled: enabled };
    const predicates = new relationalStore.RdbPredicates('geofences');
    predicates.equalTo('id', id);
    await this.rdbStore.update(bucket, predicates);
  }

  async deleteGeofence(id: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('geofences');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
  }


  // ========== 群组相关 ==========
  async createGroup(name: string, code: string, isOwner: number = 1): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      name: name,
      code: code,
      createTime: Date.now(),
      isOwner: isOwner
    };
    return await this.rdbStore.insert('groups', bucket);
  }

  async getGroups(): Promise<Group[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('groups');
    const result = await this.rdbStore.query(predicates);
    const groups: Group[] = [];
    while (result.goToNextRow()) {
      groups.push({
        id: result.getLong(result.getColumnIndex('id')),
        name: result.getString(result.getColumnIndex('name')),
        code: result.getString(result.getColumnIndex('code')),
        createTime: result.getLong(result.getColumnIndex('createTime')),
        isOwner: result.getLong(result.getColumnIndex('isOwner'))
      });
    }
    result.close();
    return groups;
  }

  async deleteGroup(id: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('groups');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
    // 同时删除成员
    const memberPredicates = new relationalStore.RdbPredicates('group_members');
    memberPredicates.equalTo('groupId', id);
    await this.rdbStore.delete(memberPredicates);
  }

  // ========== 群组成员相关 ==========
  async addMember(member: GroupMember): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      groupId: member.groupId,
      name: member.name,
      avatar: member.avatar,
      role: member.role,
      latitude: member.latitude,
      longitude: member.longitude,
      battery: member.battery,
      signal: member.signal,
      lastUpdate: member.lastUpdate || Date.now(),
      shareExpireTime: member.shareExpireTime
    };
    return await this.rdbStore.insert('group_members', bucket);
  }

  async getMembers(groupId: number): Promise<GroupMember[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('group_members');
    predicates.equalTo('groupId', groupId);
    const result = await this.rdbStore.query(predicates);
    const members: GroupMember[] = [];
    while (result.goToNextRow()) {
      members.push({
        id: result.getLong(result.getColumnIndex('id')),
        groupId: result.getLong(result.getColumnIndex('groupId')),
        name: result.getString(result.getColumnIndex('name')),
        avatar: result.getString(result.getColumnIndex('avatar')),
        role: result.getLong(result.getColumnIndex('role')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        battery: result.getLong(result.getColumnIndex('battery')),
        signal: result.getLong(result.getColumnIndex('signal')),
        lastUpdate: result.getLong(result.getColumnIndex('lastUpdate')),
        shareExpireTime: result.getLong(result.getColumnIndex('shareExpireTime'))
      });
    }
    result.close();
    return members;
  }

  async updateMemberLocation(id: number, lat: number, lon: number, battery: number, signal: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = {
      latitude: lat,
      longitude: lon,
      battery: battery,
      signal: signal,
      lastUpdate: Date.now()
    };
    const predicates = new relationalStore.RdbPredicates('group_members');
    predicates.equalTo('id', id);
    await this.rdbStore.update(bucket, predicates);
  }

  async deleteMember(id: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('group_members');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
  }

  // ========== 群组围栏相关 ==========
  async addGroupGeofence(fence: GroupGeofence): Promise<string> {
    if (!this.rdbStore) {
      return '';
    }
    const id = fence.id || `gf_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const bucket: relationalStore.ValuesBucket = {
      id: id,
      groupCode: fence.groupCode,
      name: fence.name,
      latitude: fence.latitude,
      longitude: fence.longitude,
      radius: fence.radius,
      type: fence.type || 'safe',
      creatorId: fence.creatorId,
      createTime: fence.createTime || Date.now()
    };
    await this.rdbStore.insert('group_geofences', bucket);
    return id;
  }

  async getGroupGeofences(groupCode: string): Promise<GroupGeofence[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('group_geofences');
    predicates.equalTo('groupCode', groupCode);
    const result = await this.rdbStore.query(predicates);
    const fences: GroupGeofence[] = [];
    while (result.goToNextRow()) {
      fences.push({
        id: result.getString(result.getColumnIndex('id')),
        groupCode: result.getString(result.getColumnIndex('groupCode')),
        name: result.getString(result.getColumnIndex('name')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        radius: result.getDouble(result.getColumnIndex('radius')),
        type: result.getString(result.getColumnIndex('type')),
        creatorId: result.getString(result.getColumnIndex('creatorId')),
        createTime: result.getLong(result.getColumnIndex('createTime'))
      });
    }
    result.close();
    return fences;
  }

  async getGroupGeofenceById(id: string): Promise<GroupGeofence | null> {
    if (!this.rdbStore) {
      return null;
    }
    const predicates = new relationalStore.RdbPredicates('group_geofences');
    predicates.equalTo('id', id);
    const result = await this.rdbStore.query(predicates);
    if (result.goToNextRow()) {
      const fence: GroupGeofence = {
        id: result.getString(result.getColumnIndex('id')),
        groupCode: result.getString(result.getColumnIndex('groupCode')),
        name: result.getString(result.getColumnIndex('name')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        radius: result.getDouble(result.getColumnIndex('radius')),
        type: result.getString(result.getColumnIndex('type')),
        creatorId: result.getString(result.getColumnIndex('creatorId')),
        createTime: result.getLong(result.getColumnIndex('createTime'))
      };
      result.close();
      return fence;
    }
    result.close();
    return null;
  }

  async updateGroupGeofence(id: string, data: Partial<GroupGeofence>): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = {};
    if (data.name !== undefined) {
      bucket['name'] = data.name;
    }
    if (data.latitude !== undefined) {
      bucket['latitude'] = data.latitude;
    }
    if (data.longitude !== undefined) {
      bucket['longitude'] = data.longitude;
    }
    if (data.radius !== undefined) {
      bucket['radius'] = data.radius;
    }
    if (data.type !== undefined) {
      bucket['type'] = data.type;
    }

    const predicates = new relationalStore.RdbPredicates('group_geofences');
    predicates.equalTo('id', id);
    await this.rdbStore.update(bucket, predicates);
  }

  async deleteGroupGeofence(id: string): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('group_geofences');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
  }

  async deleteGroupGeofencesByGroupCode(groupCode: string): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('group_geofences');
    predicates.equalTo('groupCode', groupCode);
    await this.rdbStore.delete(predicates);
  }

  // ========== SOS记录相关 ==========
  async addSOSRecord(record: SOSRecord): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    const bucket: relationalStore.ValuesBucket = {
      latitude: record.latitude,
      longitude: record.longitude,
      altitude: record.altitude,
      battery: record.battery,
      message: record.message,
      recentTrack: record.recentTrack,
      timestamp: record.timestamp,
      sentToGroup: record.sentToGroup,
      groupCode: record.groupCode
    };
    return await this.rdbStore.insert('sos_records', bucket);
  }

  async getSOSRecords(): Promise<SOSRecord[]> {
    if (!this.rdbStore) {
      return [];
    }
    const predicates = new relationalStore.RdbPredicates('sos_records');
    predicates.orderByDesc('timestamp');
    const result = await this.rdbStore.query(predicates);
    const records: SOSRecord[] = [];
    while (result.goToNextRow()) {
      records.push({
        id: result.getLong(result.getColumnIndex('id')),
        latitude: result.getDouble(result.getColumnIndex('latitude')),
        longitude: result.getDouble(result.getColumnIndex('longitude')),
        altitude: result.getDouble(result.getColumnIndex('altitude')),
        battery: result.getLong(result.getColumnIndex('battery')),
        message: result.getString(result.getColumnIndex('message')),
        recentTrack: result.getString(result.getColumnIndex('recentTrack')),
        timestamp: result.getLong(result.getColumnIndex('timestamp')),
        sentToGroup: result.getLong(result.getColumnIndex('sentToGroup')),
        groupCode: result.getString(result.getColumnIndex('groupCode'))
      });
    }
    result.close();
    return records;
  }

  async deleteSOSRecord(id: number): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates('sos_records');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
  }
}

export const databaseService = DatabaseService.getInstance();
