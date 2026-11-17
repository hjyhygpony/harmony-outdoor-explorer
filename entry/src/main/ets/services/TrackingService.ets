// entry/src/main/ets/services/TrackingService.ets
import geoLocationManager from '@ohos.geoLocationManager';
import { BusinessError } from '@ohos.base';
import { databaseService, TrackPoint, Track, ActivityType } from './DatabaseService';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';

export interface TrackingStatus {
  isRecording: boolean;
  isPaused: boolean;
  currentTrackId: number;
  distance: number;
  duration: number;
  pointCount: number;
  startTime: number;
  activityType: ActivityType;
}

export class TrackingService {
  private static instance: TrackingService;
  private callback: ((loc: geoLocationManager.Location) => void) | null = null;
  private currentTrackId: number = -1;
  private isRecording: boolean = false;
  private isPaused: boolean = false;
  private lastPoint: TrackPoint | null = null;
  private totalDistance: number = 0;
  private startTime: number = 0;
  private pointCount: number = 0;
  private statusCallback: ((status: TrackingStatus) => void) | null = null;
  // 暂停相关
  private pauseStartTime: number = 0; // 暂停开始时间
  private totalPausedTime: number = 0; // 总暂停时长
  private pausedDuration: number = 0; // 暂停时刻的已记录时长
  private activityType: ActivityType = ActivityType.OTHER;

  static getInstance(): TrackingService {
    if (!TrackingService.instance) {
      TrackingService.instance = new TrackingService();
    }
    return TrackingService.instance;
  }

  getStatus(): TrackingStatus {
    // 暂停时返回暂停时刻的时长，否则返回实时时长
    let duration = 0;
    if (this.startTime > 0) {
      if (this.isPaused && this.pausedDuration > 0) {
        duration = this.pausedDuration;
      } else {
        duration = Date.now() - this.startTime - this.totalPausedTime;
      }
    }
    return {
      isRecording: this.isRecording,
      isPaused: this.isPaused,
      currentTrackId: this.currentTrackId,
      distance: this.totalDistance,
      duration: duration,
      pointCount: this.pointCount,
      startTime: this.startTime,
      activityType: this.activityType
    };
  }

  setStatusCallback(cb: ((status: TrackingStatus) => void) | null) {
    this.statusCallback = cb;
  }

  private notifyStatus() {
    if (this.statusCallback) {
      this.statusCallback(this.getStatus());
    }
  }

  async startRecording(trackName: string): Promise<number> {
    if (this.isRecording) {
      return this.currentTrackId;
    }

    this.currentTrackId = await databaseService.createTrack(trackName);
    if (this.currentTrackId < 0) {
      console.error('[TrackingService] Failed to create track');
      return -1;
    }

    this.isRecording = true;
    this.isPaused = false;
    this.totalDistance = 0;
    this.startTime = Date.now();
    this.pointCount = 0;
    this.lastPoint = null;
    // 重置暂停相关变量
    this.pauseStartTime = 0;
    this.totalPausedTime = 0;
    this.pausedDuration = 0;

    this.startLocationListener();
    this.notifyStatus();
    console.info(`[TrackingService] Started recording track: ${this.currentTrackId}`);
    return this.currentTrackId;
  }

  pauseRecording() {
    if (!this.isRecording || this.isPaused) {
      return;
    }
    this.isPaused = true;
    // 记录暂停开始时间和当前已记录时长
    this.pauseStartTime = Date.now();
    this.pausedDuration = Date.now() - this.startTime - this.totalPausedTime;
    this.stopLocationListener();
    this.notifyStatus();
    console.info(`[TrackingService] Paused recording, pausedDuration: ${this.pausedDuration}ms`);
  }

  resumeRecording() {
    if (!this.isRecording || !this.isPaused) {
      return;
    }
    // 计算本次暂停时长并累加到总暂停时长
    const thisPauseDuration = Date.now() - this.pauseStartTime;
    this.totalPausedTime += thisPauseDuration;
    this.pauseStartTime = 0;
    this.pausedDuration = 0;
    this.isPaused = false;
    this.startLocationListener();
    this.notifyStatus();
    console.info(`[TrackingService] Resumed recording, totalPausedTime: ${this.totalPausedTime}ms`);
  }


  async stopRecording(): Promise<Track | null> {
    if (!this.isRecording) {
      return null;
    }

    this.stopLocationListener();
    const endTime = Date.now();
    // 计算实际记录时长（排除暂停时间）
    let duration = endTime - this.startTime - this.totalPausedTime;
    // 如果当前是暂停状态，使用暂停时刻的时长
    if (this.isPaused && this.pausedDuration > 0) {
      duration = this.pausedDuration;
    }

    await databaseService.updateTrack(this.currentTrackId, {
      endTime: endTime,
      distance: this.totalDistance,
      duration: duration,
      status: 1
    });

    const tracks = await databaseService.getTracks();
    const track = tracks.find(t => t.id === this.currentTrackId);

    this.isRecording = false;
    this.isPaused = false;
    this.currentTrackId = -1;
    this.lastPoint = null;
    this.totalDistance = 0;
    this.startTime = 0;
    this.pointCount = 0;
    // 重置暂停相关变量
    this.pauseStartTime = 0;
    this.totalPausedTime = 0;
    this.pausedDuration = 0;
    this.notifyStatus();

    console.info('[TrackingService] Stopped recording');
    return track || null;
  }

  private startLocationListener() {
    if (this.callback) {
      return;
    }

    const request: geoLocationManager.LocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      scenario: geoLocationManager.LocationRequestScenario.NAVIGATION,
      timeInterval: 2,
      distanceInterval: 0,
      maxAccuracy: 0
    };

    this.callback = async (loc: geoLocationManager.Location) => {
      if (this.isPaused || !this.isRecording) {
        return;
      }

      const point: TrackPoint = {
        trackId: this.currentTrackId,
        latitude: loc.latitude,
        longitude: loc.longitude,
        altitude: loc.altitude || 0,
        speed: loc.speed || 0,
        timestamp: Date.now()
      };

      // 计算距离
      if (this.lastPoint) {
        const dist = this.calculateDistance(
          this.lastPoint.latitude, this.lastPoint.longitude,
          point.latitude, point.longitude
        );
        // 过滤掉GPS漂移（大于100km/次的移动视为异常）
        // 放宽条件，任何有效移动都记录
        if (dist > 0 && dist < 100) {
          this.totalDistance += dist;
        }
        console.info(`[TrackingService] Distance: ${dist.toFixed(4)} km, Total: ${this.totalDistance.toFixed(4)} km`);
      }

      await databaseService.addTrackPoint(point);
      this.lastPoint = point;
      this.pointCount++;
      console.info(`[TrackingService] Point added: ${point.latitude}, ${point.longitude}, count: ${this.pointCount}`);
      this.notifyStatus();
    };

    try {
      console.info('[TrackingService] Starting location listener with request:', JSON.stringify(request));
      geoLocationManager.on('locationChange', request, this.callback);
      console.info('[TrackingService] Location listener started successfully');
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[TrackingService] Start listener error: ${err.code} - ${err.message}`);
    }
  }

  private stopLocationListener() {
    if (this.callback) {
      try {
        geoLocationManager.off('locationChange', this.callback);
        this.callback = null;
        console.info('[TrackingService] Location listener stopped');
      } catch (e) {
        const err = e as BusinessError;
        console.error(`[TrackingService] Stop listener error: ${err.message}`);
      }
    }
  }

  private calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371; // km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2)**2 +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2)**2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  // ========== GPX/KML 导出 ==========
  async exportToGPX(trackId: number, context: common.Context): Promise<string> {
    const tracks = await databaseService.getTracks();
    const track = tracks.find(t => t.id === trackId);
    if (!track) {
      return '';
    }

    const points = await databaseService.getTrackPoints(trackId);
    if (points.length === 0) {
      return '';
    }

    let gpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="OutdoorApp">
  <metadata>
    <name>${track.name}</name>
    <time>${new Date(track.startTime).toISOString()}</time>
  </metadata>
  <trk>
    <name>${track.name}</name>
    <trkseg>
`;
    for (const p of points) {
      gpx += `      <trkpt lat="${p.latitude}" lon="${p.longitude}">
        <ele>${p.altitude}</ele>
        <time>${new Date(p.timestamp).toISOString()}</time>
      </trkpt>
`;
    }
    gpx += `    </trkseg>
  </trk>
</gpx>`;

    const fileName = `track_${trackId}_${Date.now()}.gpx`;
    const filePath = `${context.filesDir}/${fileName}`;

    try {
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, gpx);
      fs.closeSync(file);
      console.info(`[TrackingService] GPX exported: ${filePath}`);
      return filePath;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[TrackingService] Export GPX error: ${err.message}`);
      return '';
    }
  }

  async exportToKML(trackId: number, context: common.Context): Promise<string> {
    const tracks = await databaseService.getTracks();
    const track = tracks.find(t => t.id === trackId);
    if (!track) {
      return '';
    }

    const points = await databaseService.getTrackPoints(trackId);
    if (points.length === 0) {
      return '';
    }

    const coordinates = points.map(p => `${p.longitude},${p.latitude},${p.altitude}`).join(' ');

    const kml = `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${track.name}</name>
    <Placemark>
      <name>${track.name}</name>
      <LineString>
        <coordinates>${coordinates}</coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>`;

    const fileName = `track_${trackId}_${Date.now()}.kml`;
    const filePath = `${context.filesDir}/${fileName}`;

    try {
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, kml);
      fs.closeSync(file);
      console.info(`[TrackingService] KML exported: ${filePath}`);
      return filePath;
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[TrackingService] Export KML error: ${err.message}`);
      return '';
    }
  }

  // 获取最近几分钟的轨迹点
  async getRecentTrackPoints(minutes: number): Promise<TrackPoint[]> {
    if (!this.isRecording || this.currentTrackId < 0) {
      return [];
    }

    const currentTime = Date.now();
    const timeThreshold = currentTime - (minutes * 60 * 1000);

    const allPoints = await databaseService.getTrackPoints(this.currentTrackId);
    return allPoints.filter(point => point.timestamp >= timeThreshold);
  }
}

export const trackingService = TrackingService.getInstance();
