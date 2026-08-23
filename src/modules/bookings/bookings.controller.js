import { BookingsService } from './bookings.service.js';
import { successResponse, errorResponse } from '../../utils/apiResponse.js';

export class BookingsController {
  /**
   * GET /api/v1/bookings/trips/:tripId/seats
   */
  static async getTripSeatMap(req, res, next) {
    try {
      const { tripId } = req.params;
      const seatMap = await BookingsService.getTripSeatMap(tripId);
      return successResponse(res, seatMap, 'Seat map fetched successfully');
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /api/v1/bookings/hold
   * Body: { tripId, seatNumbers, passengerId }
   */
  static async holdSeats(req, res, next) {
    try {
      const { tripId, seatNumbers, passengerId } = req.body;
      if (!tripId || !seatNumbers || !Array.isArray(seatNumbers) || seatNumbers.length === 0) {
        return errorResponse(res, 'tripId and non-empty seatNumbers array are required', 400);
      }
      const holdInfo = await BookingsService.holdSeats(tripId, seatNumbers, passengerId);
      return successResponse(res, holdInfo, 'Seats held successfully for 10 minutes', 201);
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }

  /**
   * POST /api/v1/bookings/confirm
   * Body: { tripId, seatNumbers, passengerName, passengerPhone, paymentMethod }
   */
  static async confirmBooking(req, res, next) {
    try {
      const { tripId, seatNumbers, passengerName, passengerPhone, boardingHaltId, alightingHaltId, paymentMethod } = req.body;
      if (!tripId || !seatNumbers || !Array.isArray(seatNumbers) || seatNumbers.length === 0) {
        return errorResponse(res, 'tripId and non-empty seatNumbers array are required', 400);
      }

      const passengerId = req.body.passengerId || req.user?.passengerId;

      const booking = await BookingsService.confirmBooking({
        tripId,
        passengerId,
        seatNumbers,
        passengerName,
        passengerPhone,
        boardingHaltId,
        alightingHaltId,
        paymentMethod,
      });

      return successResponse(res, booking, 'Booking confirmed successfully', 201);
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }

  /**
   * GET /api/v1/bookings/my-trips
   */
  static async getMyTrips(req, res, next) {
    try {
      const { limit = 20 } = req.query;
      const passengerId = req.user?.passengerId || req.query.passengerId || req.query.passenger_id;
      const bookings = await BookingsService.getPassengerBookings(passengerId, parseInt(limit, 10));
      return successResponse(res, bookings, 'My trips fetched successfully');
    } catch (error) {
      next(error);
    }
  }
}
