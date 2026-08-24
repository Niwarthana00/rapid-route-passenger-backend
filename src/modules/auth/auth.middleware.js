import { verifyToken } from '../../utils/authUtils.js';
import { errorResponse } from '../../utils/apiResponse.js';

/**
 * Middleware to authenticate requests using JWT Bearer Token
 */
export const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : req.headers['x-access-token'];

  if (!token) {
    return errorResponse(res, 'Access denied. Authorization token is missing.', 401);
  }

  try {
    const decoded = verifyToken(token);
    req.user = decoded;
    console.log('[AUTH] Decoded JWT Payload:', decoded);
    next();
  } catch (err) {
    return errorResponse(res, 'Invalid or expired authorization token.', 401);
  }
};

/**
 * Middleware to restrict route to specific roles (e.g. PASSENGER, DRIVER, ADMIN)
 */
export const authorizeRoles = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return errorResponse(res, 'Access forbidden. You do not have permission to access this resource.', 403);
    }
    next();
  };
};

/**
 * Middleware to optionally extract user token without throwing 401 error if missing
 */
export const optionalAuthenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : req.headers['x-access-token'];

  if (token) {
    try {
      const decoded = verifyToken(token);
      req.user = decoded;
    } catch (err) {
      // Ignore invalid token in optional auth mode
    }
  }
  next();
};
