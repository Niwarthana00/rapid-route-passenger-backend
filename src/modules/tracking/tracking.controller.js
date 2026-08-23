import { TrackingService } from './tracking.service.js';
import { successResponse, errorResponse } from '../../utils/apiResponse.js';

export class TrackingController {
  /**
   * GET /api/v1/tracking/trips/:tripId
   */
  static async getLiveLocation(req, res, next) {
    try {
      const { tripId } = req.params;
      const location = await TrackingService.getLiveLocation(tripId);
      return successResponse(res, location, 'Live bus location fetched successfully');
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /api/v1/tracking/update
   * Driver GPS location push endpoint
   */
  static async updateLocation(req, res, next) {
    try {
      const { tripId, latitude, longitude, speed, heading, currentStop, nextStop, etaMins } = req.body;
      if (!tripId || latitude === undefined || longitude === undefined) {
        return errorResponse(res, 'tripId, latitude, and longitude are required', 400);
      }

      const updated = TrackingService.updateLocation({
        tripId,
        latitude,
        longitude,
        speed,
        heading,
        currentStop,
        nextStop,
        etaMins,
      });

      return successResponse(res, updated, 'Location updated successfully');
    } catch (error) {
      next(error);
    }
  }
}
