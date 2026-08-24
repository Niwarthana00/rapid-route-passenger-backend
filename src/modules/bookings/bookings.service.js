import { pool, query } from '../../config/database.js';

// In-memory temporary seat hold store (10 minute TTL)
const heldSeatsStore = new Map(); // key: `${tripId}_${seatNumber}`, value: { expiresAt, holdId }

export class BookingsService {
  /**
   * Get seat map and occupancy for a trip
   */
  static async getTripSeatMap(tripId) {
    try {
      // 1. Get vehicle and trip details
      const tripSql = `
        SELECT 
          t.id AS "tripId",
          t.trip_date AS "tripDate",
          t.status,
          t.schedule_id AS "scheduleId",
          v.id AS "vehicleId",
          v.registration_number AS "plateNumber",
          v.make,
          v.model,
          (v.model ILIKE '%AC%' OR v.make ILIKE '%Luxury%') AS "isAC",
          r.route_number AS "routeNumber",
          h_origin.name AS "from",
          h_dest.name AS "to",
          COALESCE(fr.base_fare, 500.00) AS "baseFare"
        FROM biz.trips t
        JOIN core.vehicles v ON t.vehicle_id = v.id
        JOIN biz.schedules s ON t.schedule_id = s.id
        JOIN core.routes r ON s.route_id = r.id
        JOIN core.halts h_origin ON r.origin_halt_id = h_origin.id
        JOIN core.halts h_dest ON r.destination_halt_id = h_dest.id
        LEFT JOIN fin.fare_rules fr ON fr.route_id = r.id AND (fr.effective_to IS NULL OR fr.effective_to >= CURRENT_DATE)
        WHERE t.id::text = $1
        LIMIT 1
      `;
      const tripRes = await query(tripSql, [tripId]);
      
      let tripInfo;
      if (tripRes.rows.length > 0) {
        tripInfo = tripRes.rows[0];
      } else {
        // Fallback for demonstration / mock trip ID
        tripInfo = {
          tripId: tripId || 'default-trip',
          plateNumber: 'ND-4521',
          routeNumber: '001',
          from: 'Colombo',
          to: 'Kandy',
          isAC: true,
          baseFare: 650.00,
        };
      }

      // 2. Query occupied / booked seats from database (biz.bookings)
      let bookedSeatNumbers = [];
      try {
        const bookedSql = `
          SELECT seat_number 
          FROM biz.bookings 
          WHERE trip_id::text = $1 AND booking_status <> 'CANCELLED'
        `;
        const bookedRes = await query(bookedSql, [tripId]);
        bookedSeatNumbers = bookedRes.rows.map((r) => r.seat_number);
      } catch (err) {
        console.warn('Booked seats query fallback:', err.message);
      }

      // 3. Add currently held seats (not expired)
      const now = Date.now();
      const currentlyHeldSeats = [];
      for (const [key, val] of heldSeatsStore.entries()) {
        if (key.startsWith(`${tripId}_`) && val.expiresAt > now) {
          const seatNum = parseInt(key.split('_')[1], 10);
          currentlyHeldSeats.push(seatNum);
        }
      }

      // Total seats (standard 40 seats layout: 10 rows x 4 seats)
      const totalSeats = 40;
      const occupiedSet = new Set([...bookedSeatNumbers, ...currentlyHeldSeats]);

      const seats = Array.from({ length: totalSeats }, (_, i) => {
        const seatNum = i + 1;
        const isOccupied = occupiedSet.has(seatNum);
        return {
          number: seatNum,
          seatNumber: seatNum,
          label: `${seatNum}`,
          status: isOccupied ? 'occupied' : 'available',
          isOccupied: isOccupied,
          isBooked: isOccupied,
          occupied: isOccupied,
          type: 'STANDARD',
        };
      });

      const availableCount = seats.filter((s) => s.status === 'available').length;

      return {
        trip: tripInfo,
        totalSeats,
        availableSeatsCount: availableCount,
        occupiedSeatsCount: totalSeats - availableCount,
        seats,
      };
    } catch (error) {
      console.error('Error fetching seat map:', error);
      throw error;
    }
  }

  /**
   * Temporarily hold seats for 10 minutes before checkout
   */
  static async holdSeats(tripId, seatNumbers, passengerId = null) {
    const holdDurationMs = 10 * 60 * 1000; // 10 minutes
    const expiresAt = Date.now() + holdDurationMs;
    const holdId = `hold_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

    // Check if any seat is already occupied or held
    const seatMap = await this.getTripSeatMap(tripId);
    const occupiedSeats = new Set(seatMap.seats.filter((s) => s.status === 'occupied').map((s) => s.number));

    for (const seatNum of seatNumbers) {
      if (occupiedSeats.has(seatNum)) {
        throw new Error(`Seat ${seatNum} is already taken or held by another passenger.`);
      }
    }

    // Save hold
    for (const seatNum of seatNumbers) {
      heldSeatsStore.set(`${tripId}_${seatNum}`, { expiresAt, holdId, passengerId });
    }

    return {
      holdId,
      tripId,
      seatNumbers,
      expiresAt: new Date(expiresAt).toISOString(),
      expiresInSeconds: 600,
    };
  }

  /**
   * Confirm booking and store in PostgreSQL database
   */
  static async confirmBooking({
    tripId,
    passengerId = null,
    passengerName = 'Passenger',
    passengerPhone = '0771234567',
    boardingHaltId = null,
    alightingHaltId = null,
    seatNumbers = [],
    paymentMethod = 'CARD',
  }) {
    if (!seatNumbers || seatNumbers.length === 0) {
      throw new Error('Please select at least one seat to book.');
    }

    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Get or create passenger
      let pId = passengerId;
      if (!pId) {
        const passRes = await client.query(
          `INSERT INTO core.passengers (full_name, phone) 
           VALUES ($1, $2) 
           ON CONFLICT DO NOTHING 
           RETURNING id`,
          [passengerName, passengerPhone]
        );
        if (passRes.rows.length > 0) {
          pId = passRes.rows[0].id;
        } else {
          const existing = await client.query('SELECT id FROM core.passengers LIMIT 1');
          pId = existing.rows.length > 0 ? existing.rows[0].id : '00000000-0000-0000-0000-000000000001';
        }
      }

      // 2. Fetch trip details & fare
      const tripSql = `
        SELECT 
          t.id,
          t.trip_date,
          r.route_number,
          r.origin_halt_id,
          r.destination_halt_id,
          h1.name AS origin_name,
          h2.name AS dest_name,
          v.registration_number,
          (v.model ILIKE '%AC%' OR v.make ILIKE '%Luxury%') AS is_ac,
          COALESCE(fr.base_fare, 650.00) AS base_fare
        FROM biz.trips t
        JOIN biz.schedules s ON t.schedule_id = s.id
        JOIN core.routes r ON s.route_id = r.id
        JOIN core.halts h1 ON r.origin_halt_id = h1.id
        JOIN core.halts h2 ON r.destination_halt_id = h2.id
        JOIN core.vehicles v ON t.vehicle_id = v.id
        LEFT JOIN fin.fare_rules fr ON fr.route_id = r.id AND (fr.effective_to IS NULL OR fr.effective_to >= CURRENT_DATE)
        WHERE t.id::text = $1
        LIMIT 1
      `;
      const tripRes = await client.query(tripSql, [tripId]);

      let tripData = tripRes.rows.length > 0 ? tripRes.rows[0] : null;

      const originId = boardingHaltId || (tripData ? tripData.origin_halt_id : null);
      const destId = alightingHaltId || (tripData ? tripData.destination_halt_id : null);
      const singleFare = tripData ? parseFloat(tripData.base_fare) : 650.00;
      const totalFare = singleFare * seatNumbers.length;

      const bookingRef = `RR-${Math.floor(10000 + Math.random() * 90000)}`;
      const bookedRecords = [];

      // 3. Insert each booked seat into biz.bookings
      for (const seatNum of seatNumbers) {
        const insertSql = `
          INSERT INTO biz.bookings (
            passenger_id,
            trip_id,
            boarding_halt_id,
            alighting_halt_id,
            seat_number,
            fare_amount,
            booking_status,
            booking_ref
          ) VALUES ($1, $2, $3, $4, $5, $6, 'CONFIRMED', $7)
          RETURNING id, booking_ref, seat_number, fare_amount, booked_at
        `;

        const insRes = await client.query(insertSql, [
          pId,
          tripId,
          originId,
          destId,
          seatNum,
          singleFare,
          `${bookingRef}-${seatNum}`,
        ]);

        bookedRecords.push(insRes.rows[0]);

        // Release in-memory hold
        heldSeatsStore.delete(`${tripId}_${seatNum}`);
      }

      await client.query('COMMIT');

      // Format response exactly as React Native BookingConfirmedView expects
      const confirmedDetails = {
        bookingId: bookingRef,
        routeNumber: tripData ? tripData.route_number : '001',
        from: tripData ? tripData.origin_name : 'Colombo',
        to: tripData ? tripData.dest_name : 'Kandy',
        busPlate: tripData ? tripData.registration_number : 'ND-4521',
        isAC: tripData ? tripData.is_ac : true,
        seatNumbers,
        totalFare,
        date: new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }),
        time: new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
        status: 'CONFIRMED',
        paymentMethod,
        qrCodePayload: JSON.stringify({
          ref: bookingRef,
          seats: seatNumbers,
          tripId,
          fare: totalFare,
          busPlate: tripData ? tripData.registration_number : 'ND-4521',
        }),
      };

      return confirmedDetails;
    } catch (err) {
      await client.query('ROLLBACK');
      console.error('Booking confirmation failed:', err);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Get all bookings for a passenger (My Trips)
   */
  static async getPassengerBookings(passengerId = null, limit = 20) {
    try {
      let sql = `
        SELECT 
          b.booking_ref AS "bookingId",
          b.booking_status AS "status",
          b.fare_amount AS "fare",
          b.seat_number AS "seatNumber",
          b.booked_at AS "bookedAt",
          r.route_number AS "routeNumber",
          h1.name AS "from",
          h2.name AS "to",
          v.registration_number AS "busPlate",
          (v.model ILIKE '%AC%' OR v.make ILIKE '%Luxury%') AS "isAC",
          t.trip_date AS "tripDate",
          b.trip_id AS "tripId"
        FROM biz.bookings b
        JOIN biz.trips t ON b.trip_id = t.id
        JOIN biz.schedules s ON t.schedule_id = s.id
        JOIN core.routes r ON s.route_id = r.id
        JOIN core.halts h1 ON b.boarding_halt_id = h1.id
        JOIN core.halts h2 ON b.alighting_halt_id = h2.id
        JOIN core.vehicles v ON t.vehicle_id = v.id
      `;
      const params = [];
      if (passengerId) {
        sql += ` WHERE b.passenger_id = $1`;
        params.push(passengerId);
      }
      params.push(limit);
      sql += ` ORDER BY b.booked_at DESC LIMIT $` + params.length;

      const res = await query(sql, params);
      return res.rows.map((row) => ({
        id: row.bookingId,
        bookingId: row.bookingId,
        bookingRef: row.bookingId,
        routeNumber: row.routeNumber,
        from: row.from,
        to: row.to,
        busPlate: row.busPlate,
        isAC: row.isAC,
        seatNumber: row.seatNumber,
        seatNumbers: [row.seatNumber],
        fare: parseFloat(row.fare),
        totalFare: parseFloat(row.fare),
        date: row.bookedAt ? new Date(row.bookedAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : 'Today',
        time: row.bookedAt ? new Date(row.bookedAt).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '08:30 AM',
        status: row.status || 'CONFIRMED',
        tripId: row.tripId,
      }));
    } catch (err) {
      console.warn('Passenger bookings query fallback:', err.message);
      return [];
    }
  }
}
