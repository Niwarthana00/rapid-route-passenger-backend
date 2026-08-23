import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

/**
 * Hash a plain-text password using bcrypt
 */
export const hashPassword = async (password) => {
  const salt = await bcrypt.genSalt(10);
  return await bcrypt.hash(password, salt);
};

/**
 * Compare plain-text password with hashed password
 */
export const comparePassword = async (password, hash) => {
  return await bcrypt.compare(password, hash);
};

/**
 * Generate a JWT token
 */
export const generateToken = (payload, expiresIn = '30d') => {
  return jwt.sign(payload, env.JWT_SECRET || 'super_secret_rapid_route_jwt_key_2026', {
    expiresIn,
  });
};

/**
 * Verify a JWT token
 */
export const verifyToken = (token) => {
  return jwt.verify(token, env.JWT_SECRET || 'super_secret_rapid_route_jwt_key_2026');
};
