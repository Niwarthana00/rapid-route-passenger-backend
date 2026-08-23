import { query } from '../../config/database.js';

// In-memory real-time bus location store
const activeBusLocations = new Map();

export class TrackingService {
  /**
   * Update live location for a trip/bus
   */
  static updateLocation({ tripId, latitude, longitude, speed = 0, heading = 0, currentStop = '', nextStop = '', etaMins = 0 }) {
    const data = {
      tripId,
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      speed: parseFloat(speed),
      heading: parseFloat(heading),
      currentStop,
      nextStop,
      etaMins: parseInt(etaMins, 10),
      updatedAt: new Date().toISOString(),
    };
    activeBusLocations.set(tripId, data);
    return data;
  }

  /**
   * Get latest live location for a trip
   */
  static async getLiveLocation(tripId) {
    if (activeBusLocations.has(tripId)) {
      return activeBusLocations.get(tripId);
    }

    // Default simulation position
    return {
      tripId,
      latitude: 6.9344,
      longitude: 79.8428,
      speed: 42.5,
      heading: 45,
      currentStop: 'Peliyagoda',
      nextStop: 'Kiribathgoda',
      etaMins: 8,
      updatedAt: new Date().toISOString(),
    };
  }

  /**
   * Get live locations of all active buses on a route
   */
  static async getRouteLiveBuses(routeId) {
    const list = [];
    for (const [_, location] of activeBusLocations.entries()) {
      list.push(location);
    }
    return list;
  }
}
