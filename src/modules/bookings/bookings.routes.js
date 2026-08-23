import { Router } from 'express';
import { BookingsController } from './bookings.controller.js';

const router = Router();

// GET /api/v1/bookings/trips/:tripId/seats - Get seat layout & occupancy
router.get('/trips/:tripId/seats', BookingsController.getTripSeatMap);

// POST /api/v1/bookings/hold - Temporarily lock seats
router.post('/hold', BookingsController.holdSeats);

// POST /api/v1/bookings/confirm - Confirm booking & generate QR ticket
router.post('/confirm', BookingsController.confirmBooking);

// GET /api/v1/bookings/my-trips - List passenger booked trips
router.get('/my-trips', BookingsController.getMyTrips);

export default router;
