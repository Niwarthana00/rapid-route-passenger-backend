import { Router } from 'express';
import { AuthController } from './auth.controller.js';
import { authenticateToken } from './auth.middleware.js';

const router = Router();

// Public Authentication Endpoints
router.post('/register', AuthController.registerPassenger);
router.post('/register-driver', AuthController.registerDriver);
router.post('/login', AuthController.login);

// Protected Authentication Endpoints
router.get('/profile', authenticateToken, AuthController.getProfile);

export default router;
