import { RoutesService } from './routes.service.js';
import { successResponse, errorResponse } from '../../utils/apiResponse.js';

export class RoutesController {
  /**
   * GET /api/v1/routes
   * Query params: search, from, to
   */
  static async getAllRoutes(req, res, next) {
    try {
      const { search = '', from = '', to = '', page = 1, limit = 50 } = req.query;
      const routes = await RoutesService.getAllRoutes(search, from, to, page, limit);
      return successResponse(res, routes, 'Routes fetched successfully');
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /api/v1/routes/:id
   */
  static async getRouteById(req, res, next) {
    try {
      const { id } = req.params;
      const route = await RoutesService.getRouteById(id);
      if (!route) {
        return errorResponse(res, `Route '${id}' not found`, 404);
      }
      return successResponse(res, route, 'Route details fetched successfully');
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /api/v1/routes/:id/halts
   */
  static async getRouteHalts(req, res, next) {
    try {
      const { id } = req.params;
      const halts = await RoutesService.getRouteHalts(id);
      return successResponse(res, halts, 'Route halts fetched successfully');
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /api/v1/routes/:id/buses
   */
  static async getActiveBuses(req, res, next) {
    try {
      const { id } = req.params;
      const buses = await RoutesService.getActiveBusesOnRoute(id);
      return successResponse(res, buses, 'Active buses fetched successfully');
    } catch (error) {
      next(error);
    }
  }
}
