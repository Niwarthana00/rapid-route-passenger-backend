import { Router } from 'express';
import routesRouter from '../modules/routes/routes.routes.js';
import bookingsRouter from '../modules/bookings/bookings.routes.js';
import trackingRouter from '../modules/tracking/tracking.routes.js';

const apiRouter = Router();

// API Health Check
apiRouter.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    service: 'Rapid Route Passenger Backend API',
    version: '1.0.0',
  });
});

// Feature Modules
apiRouter.use('/routes', routesRouter);
apiRouter.use('/bookings', bookingsRouter);
apiRouter.use('/tracking', trackingRouter);

export default apiRouter;
