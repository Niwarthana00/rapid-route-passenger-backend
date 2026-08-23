import { Router } from 'express';
import { TrackingController } from './tracking.controller.js';

const router = Router();

// GET /api/v1/tracking/trips/:tripId - Get live location of a bus trip
router.get('/trips/:tripId', TrackingController.getLiveLocation);

// POST /api/v1/tracking/update - Driver/GPS device location push
router.post('/update', TrackingController.updateLocation);

export default router;
