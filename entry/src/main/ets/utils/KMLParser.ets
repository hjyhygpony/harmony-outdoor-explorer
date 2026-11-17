// entry/src/main/ets/utils/KMLParser.ets
// KML Parser for round-trip testing - parses KML 2.2 format files

/**
 * Represents a parsed coordinate point from KML file
 * KML format: longitude,latitude,altitude (note: lon comes before lat)
 */
export interface KMLCoordinate {
  longitude: number;
  latitude: number;
  altitude: number;
}

/**
 * Represents the complete parsed KML data
 */
export interface KMLData {
  documentName: string;
  placemarkName: string;
  coordinates: KMLCoordinate[];
}

/**
 * KMLParser class for parsing KML 2.2 format XML files
 * Used primarily for round-trip testing of KML export functionality
 */
export class KMLParser {
  /**
   * Parse KML XML string and extract coordinates
   * @param kmlContent - The KML XML content as string
   * @returns KMLData object containing document info and coordinates
   */
  static parse(kmlContent: string): KMLData {
    const result: KMLData = {
      documentName: '',
      placemarkName: '',
      coordinates: []
    };

    if (!kmlContent || kmlContent.trim().length === 0) {
      return result;
    }

    // Parse Document name
    result.documentName = KMLParser.extractTagContent(kmlContent, 'Document', 'name');

    // Parse Placemark name
    result.placemarkName = KMLParser.extractTagContent(kmlContent, 'Placemark', 'name');

    // Parse coordinates from LineString
    result.coordinates = KMLParser.parseCoordinates(kmlContent);

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
    
    // Find first child tag content (direct child, not nested)
    const childRegex = new RegExp(`<${childTag}>([^<]*)<\\/${childTag}>`, 'i');
    const childMatch = parentContent.match(childRegex);
    
    return childMatch ? childMatch[1].trim() : '';
  }

  /**
   * Parse coordinates from KML LineString element
   * KML coordinate format: longitude,latitude,altitude (space-separated tuples)
   */
  private static parseCoordinates(content: string): KMLCoordinate[] {
    const coordinates: KMLCoordinate[] = [];
    
    // Find coordinates element within LineString
    const lineStringRegex = /<LineString[^>]*>([\s\S]*?)<\/LineString>/i;
    const lineStringMatch = content.match(lineStringRegex);
    
    if (!lineStringMatch) {
      return coordinates;
    }

    const lineStringContent = lineStringMatch[1];
    
    // Extract coordinates content
    const coordsRegex = /<coordinates>([^<]*)<\/coordinates>/i;
    const coordsMatch = lineStringContent.match(coordsRegex);
    
    if (!coordsMatch) {
      return coordinates;
    }

    const coordsString = coordsMatch[1].trim();
    
    // Split by whitespace to get individual coordinate tuples
    const tuples = coordsString.split(/\s+/).filter(t => t.length > 0);
    
    for (const tuple of tuples) {
      const parts = tuple.split(',');
      
      if (parts.length >= 2) {
        const lon = parseFloat(parts[0]);
        const lat = parseFloat(parts[1]);
        const alt = parts.length >= 3 ? parseFloat(parts[2]) : 0;

        // Validate coordinates are in valid range
        if (KMLParser.isValidCoordinate(lat, lon)) {
          coordinates.push({
            longitude: lon,
            latitude: lat,
            altitude: isNaN(alt) ? 0 : alt
          });
        }
      }
    }

    return coordinates;
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
   * Compare two KMLCoordinate arrays for equality (used in round-trip testing)
   * @param coords1 - First array of coordinates
   * @param coords2 - Second array of coordinates
   * @param tolerance - Tolerance for floating point comparison (default 0.000001)
   * @returns true if arrays are equal within tolerance
   */
  static compareCoordinates(coords1: KMLCoordinate[], coords2: KMLCoordinate[], tolerance: number = 0.000001): boolean {
    if (coords1.length !== coords2.length) {
      return false;
    }

    for (let i = 0; i < coords1.length; i++) {
      const c1 = coords1[i];
      const c2 = coords2[i];

      if (Math.abs(c1.latitude - c2.latitude) > tolerance ||
          Math.abs(c1.longitude - c2.longitude) > tolerance ||
          Math.abs(c1.altitude - c2.altitude) > tolerance) {
        return false;
      }
    }

    return true;
  }
}
