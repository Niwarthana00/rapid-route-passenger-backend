import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import app from './app.js';
import { env } from './config/env.js';
import { testDbConnection } from './config/database.js';

const server = http.createServer(app);

import { registerTrackingSocketHandlers } from './modules/tracking/tracking.socket.js';

// Socket.io for Real-time GPS bus tracking
export const io = new SocketIOServer(server, {
  cors: {
    origin: env.CORS_ORIGIN === '*' ? '*' : env.CORS_ORIGIN.split(','),
    methods: ['GET', 'POST'],
  },
});

// Register real-time tracking handlers
registerTrackingSocketHandlers(io);

const startServer = async () => {
  // Test PostgreSQL database connection
  await testDbConnection();

  server.listen(env.PORT, () => {
    console.log(`=========================================`);
    console.log(`🚀 Rapid Route Backend Server Running!`);
    console.log(`📡 URL: http://localhost:${env.PORT}`);
    console.log(`🩺 Health: http://localhost:${env.PORT}/api/v1/health`);
    console.log(`🚌 Routes API: http://localhost:${env.PORT}/api/v1/routes`);
    console.log(`⚡ Environment: ${env.NODE_ENV}`);
    console.log(`=========================================`);
  });
};

// Handle unhandled promise rejections
process.on('unhandledRejection', (err) => {
  console.error('Unhandled Promise Rejection:', err);
});

// Handle uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
});

// Rapid Route Server Entry Point - Updated 2026-08-22
startServer();
