// entry/src/main/ets/utils/GPXParser.ets
// GPX Parser for round-trip testing - parses GPX 1.1 format files

/**
 * Represents a parsed track point from GPX file
 */
export interface GPXTrackPoint {
  latitude: number;
  longitude: number;
  altitude: number;
  timestamp: number;
}

/**
 * Represents parsed GPX metadata
 */
export interface GPXMetadata {
  name: string;
  time: number;
}

/**
 * Represents the complete parsed GPX data
 */
export interface GPXData {
  metadata: GPXMetadata;
  trackName: string;
  points: GPXTrackPoint[];
}

/**
 * GPXParser class for parsing GPX 1.1 format XML files
 * Used primarily for round-trip testing of GPX export functionality
 */
export class GPXParser {
  /**
   * Parse GPX XML string and extract track points
   * @param gpxContent - The GPX XML content as string
   * @returns GPXData object containing metadata and track points
   */
  static parse(gpxContent: string): GPXData {
    const result: GPXData = {
      metadata: { name: '', time: 0 },
      trackName: '',
      points: []
    };

    if (!gpxContent || gpxContent.trim().length === 0) {
      return result;
    }

    // Parse metadata name
    result.metadata.name = GPXParser.extractTagContent(gpxContent, 'metadata', 'name');
    
    // Parse metadata time
    const metadataTimeStr = GPXParser.extractTagContent(gpxContent, 'metadata', 'time');
    if (metadataTimeStr) {
      result.metadata.time = new Date(metadataTimeStr).getTime();
    }

    // Parse track name
    result.trackName = GPXParser.extractFirstTagContent(gpxContent, 'trk', 'name');

    // Parse track points
    result.points = GPXParser.parseTrackPoints(gpxContent);

    return result;
  }

  /**
   * Extract content from a tag within a parent tag
   */
  private static extractTagContent(content: string, parentTag: string, childTag: string): string {
    // Find parent tag content first
    const parentRegex = new RegExp(`<${parentTag}[^>]*>([\\s\\S]*?)<\\/${parentTag}>`, 'i');
    const parentMatch = content.match(parentRegex);
    
    if (!parentMatch) {
      return '';
    }

    const parentContent = parentMatch[1];
    
    // Find child tag content within parent
    const childRegex = new RegExp(`<${childTag}[^>]*>([^<]*)<\\/${childTag}>`, 'i');
    const childMatch = parentContent.match(childRegex);
    
    return childMatch ? childMatch[1].trim() : '';
  }

  /**
   * Extract first occurrence of a tag content within a parent tag
   */
  private static extractFirstTagContent(content: string, parentTag: string, childTag: string): string {
    // Find parent tag content first
    const parentRegex = new RegExp(`<${parentTag}[^>]*>([\\s\\S]*?)<\\/${parentTag}>`, 'i');
    const parentMatch = content.match(parentRegex);
    
    if (!parentMatch) {
      return '';
    }

    const parentContent = parentMatch[1];
    
    // Find first child tag content (before any nested tags)
    const childRegex = new RegExp(`<${childTag}>([^<]*)<\\/${childTag}>`, 'i');
    const childMatch = parentContent.match(childRegex);
    
    return childMatch ? childMatch[1].trim() : '';
  }

  /**
   * Parse all track points from GPX content
   */
  private static parseTrackPoints(content: string): GPXTrackPoint[] {
    const points: GPXTrackPoint[] = [];
    
    // Match all trkpt elements
    const trkptRegex = /<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)"[^>]*>([\s\S]*?)<\/trkpt>/gi;
    let match: RegExpExecArray | null;

    while ((match = trkptRegex.exec(content)) !== null) {
      const lat = parseFloat(match[1]);
      const lon = parseFloat(match[2]);
      const pointContent = match[3];

      // Extract elevation
      const eleMatch = pointContent.match(/<ele>([^<]*)<\/ele>/i);
      const altitude = eleMatch ? parseFloat(eleMatch[1]) : 0;

      // Extract time
      const timeMatch = pointContent.match(/<time>([^<]*)<\/time>/i);
      const timestamp = timeMatch ? new Date(timeMatch[1]).getTime() : 0;

      // Validate coordinates are in valid range
      if (GPXParser.isValidCoordinate(lat, lon)) {
        points.push({
          latitude: lat,
          longitude: lon,
          altitude: isNaN(altitude) ? 0 : altitude,
          timestamp: isNaN(timestamp) ? 0 : timestamp
        });
      }
    }

    return points;
  }

  /**
   * Validate that coordinates are within valid ranges
   * Latitude: -90 to 90
   * Longitude: -180 to 180
   */
  private static isValidCoordinate(lat: number, lon: number): boolean {
    return !isNaN(lat) && !isNaN(lon) &&
           lat >= -90 && lat <= 90 &&
           lon >= -180 && lon <= 180;
  }

  /**
   * Compare two GPXTrackPoint arrays for equality (used in round-trip testing)
   * @param points1 - First array of track points
   * @param points2 - Second array of track points
   * @param tolerance - Tolerance for floating point comparison (default 0.000001)
   * @returns true if arrays are equal within tolerance
   */
  static compareTrackPoints(points1: GPXTrackPoint[], points2: GPXTrackPoint[], tolerance: number = 0.000001): boolean {
    if (points1.length !== points2.length) {
      return false;
    }

    for (let i = 0; i < points1.length; i++) {
      const p1 = points1[i];
      const p2 = points2[i];

      if (Math.abs(p1.latitude - p2.latitude) > tolerance ||
          Math.abs(p1.longitude - p2.longitude) > tolerance ||
          Math.abs(p1.altitude - p2.altitude) > tolerance ||
          p1.timestamp !== p2.timestamp) {
        return false;
      }
    }

    return true;
  }
}
