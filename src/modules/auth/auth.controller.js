import { AuthService } from './auth.service.js';
import { successResponse, errorResponse } from '../../utils/apiResponse.js';

export class AuthController {
  /**
   * Register a new passenger account
   */
  static async registerPassenger(req, res, next) {
    try {
      const { fullName, phone, email, password, nicNumber, gender } = req.body;
      const data = await AuthService.registerPassenger({
        fullName,
        phone,
        email,
        password,
        nicNumber,
        gender,
      });
      return successResponse(res, data, 'Passenger account registered successfully.', 201);
    } catch (err) {
      if (err.message.includes('already exists')) {
        return errorResponse(res, err.message, 400);
      }
      next(err);
    }
  }

  /**
   * Register a new driver account
   */
  static async registerDriver(req, res, next) {
    try {
      const { fullName, phone, nicNumber, licenseNumber, licenseExpiry, licenseClass, email, password } = req.body;
      const data = await AuthService.registerDriver({
        fullName,
        phone,
        nicNumber,
        licenseNumber,
        licenseExpiry,
        licenseClass,
        email,
        password,
      });
      return successResponse(res, data, 'Driver account registered successfully.', 201);
    } catch (err) {
      if (err.message.includes('already exists')) {
        return errorResponse(res, err.message, 400);
      }
      next(err);
    }
  }

  /**
   * Unified login for Passengers and Drivers
   */
  static async login(req, res, next) {
    try {
      const { identifier, phone, email, password } = req.body;
      const loginId = identifier || phone || email;
      const data = await AuthService.login({
        identifier: loginId,
        password,
      });
      return successResponse(res, data, 'Login successful.', 200);
    } catch (err) {
      if (err.message.includes('Invalid') || err.message.includes('deactivated')) {
        return errorResponse(res, err.message, 401);
      }
      next(err);
    }
  }

  /**
   * Get logged-in user profile
   */
  static async getProfile(req, res, next) {
    try {
      const userId = req.user.userId;
      const data = await AuthService.getProfile(userId);
      return successResponse(res, data, 'Profile fetched successfully.', 200);
    } catch (err) {
      next(err);
    }
  }
}
