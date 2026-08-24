import { Router } from 'express';
import { BookingsController } from './bookings.controller.js';
import { optionalAuthenticateToken } from '../auth/auth.middleware.js';

const router = Router();

// GET /api/v1/bookings/trips/:tripId/seats - Get seat layout & occupancy
router.get('/trips/:tripId/seats', BookingsController.getTripSeatMap);

// POST /api/v1/bookings/hold - Temporarily lock seats
router.post('/hold', BookingsController.holdSeats);

// POST /api/v1/bookings/confirm - Confirm booking & generate QR ticket
router.post('/confirm', optionalAuthenticateToken, BookingsController.confirmBooking);

// GET /api/v1/bookings/my-trips - List passenger booked trips
router.get('/my-trips', optionalAuthenticateToken, BookingsController.getMyTrips);

// POST & PUT /api/v1/bookings/:bookingId/cancel - Cancel booking & release seats
router.post('/:bookingId/cancel', optionalAuthenticateToken, BookingsController.cancelBooking);
router.post('/cancel', optionalAuthenticateToken, BookingsController.cancelBooking);
router.put('/:bookingId/cancel', optionalAuthenticateToken, BookingsController.cancelBooking);

export default router;
