import { TrackingService } from './tracking.service.js';

/**
 * Socket.IO real-time tracking handler
 */
export const registerTrackingSocketHandlers = (io) => {
  io.on('connection', (socket) => {
    // Passenger joins a route channel to receive all bus positions on that route
    socket.on('join_route', (routeId) => {
      socket.join(`route_${routeId}`);
      console.log(`📡 Passenger ${socket.id} joined live tracking for route: ${routeId}`);
    });

    socket.on('leave_route', (routeId) => {
      socket.leave(`route_${routeId}`);
      console.log(`Passenger ${socket.id} left route: ${routeId}`);
    });

    // Passenger joins specific trip channel (for in-trip alerts and destination distance)
    socket.on('join_trip', (tripId) => {
      socket.join(`trip_${tripId}`);
      console.log(`📡 Passenger ${socket.id} joined live tracking for trip: ${tripId}`);
    });

    // Driver App / GPS Device sends live coordinates update
    socket.on('driver_location_update', (data) => {
      const { tripId, routeId, latitude, longitude, speed, heading, currentStop, nextStop, etaMins } = data;
      
      const updatedLocation = TrackingService.updateLocation({
        tripId,
        latitude,
        longitude,
        speed,
        heading,
        currentStop,
        nextStop,
        etaMins,
      });

      // Broadcast to passengers tracking this specific trip
      io.to(`trip_${tripId}`).emit('bus_location_update', updatedLocation);

      // Broadcast to passengers viewing the route map
      if (routeId) {
        io.to(`route_${routeId}`).emit('route_bus_update', updatedLocation);
      }
    });
  });
};
