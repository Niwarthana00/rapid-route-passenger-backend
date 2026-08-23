import { Router } from 'express';
import { RoutesController } from './routes.controller.js';

const router = Router();

// GET /api/v1/routes - List & Search routes
router.get('/', RoutesController.getAllRoutes);

// GET /api/v1/routes/:id - Single route details
router.get('/:id', RoutesController.getRouteById);

// GET /api/v1/routes/:id/halts - Halts / stops along the route
router.get('/:id/halts', RoutesController.getRouteHalts);

// GET /api/v1/routes/:id/buses - Active buses & live positions on this route
router.get('/:id/buses', RoutesController.getActiveBuses);

export default router;
