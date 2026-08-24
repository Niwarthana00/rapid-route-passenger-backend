import { pool, query } from '../../config/database.js';
import { hashPassword, comparePassword, generateToken } from '../../utils/authUtils.js';

export class AuthService {
  /**
   * Register a new Passenger
   */
  static async registerPassenger({ fullName, phone, email = null, password, nicNumber = null, gender = null }) {
    if (!phone || !password || !fullName) {
      throw new Error('Full name, phone, and password are required.');
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Check if user account already exists with phone or email
      const existingUser = await client.query(
        'SELECT id FROM core.user_accounts WHERE phone = $1 OR (email IS NOT NULL AND email = $2)',
        [phone, email]
      );
      if (existingUser.rows.length > 0) {
        throw new Error('A user account with this phone number or email already exists.');
      }

      // 2. Create passenger profile in core.passengers
      const passSql = `
        INSERT INTO core.passengers (full_name, phone, email, nic_number, gender)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, full_name, phone, email, nic_number, gender, created_at
      `;
      const passRes = await client.query(passSql, [fullName, phone, email, nicNumber, gender]);
      const passengerProfile = passRes.rows[0];

      // 3. Hash password and insert into core.user_accounts
      const hashedPassword = await hashPassword(password);
      const userSql = `
        INSERT INTO core.user_accounts (phone, email, password_hash, user_type, passenger_id)
        VALUES ($1, $2, $3, 'PASSENGER', $4)
        RETURNING id, phone, email, photo_url AS "photoUrl", user_type, passenger_id, created_at
      `;
      const userRes = await client.query(userSql, [phone, email, hashedPassword, passengerProfile.id]);
      const userAccount = userRes.rows[0];

      await client.query('COMMIT');

      // 4. Generate JWT Token
      const token = generateToken({
        userId: userAccount.id,
        role: 'PASSENGER',
        passengerId: passengerProfile.id,
        phone: userAccount.phone,
      });

      return {
        user: {
          id: userAccount.id,
          phone: userAccount.phone,
          email: userAccount.email,
          photoUrl: userAccount.photoUrl || null,
          userType: 'PASSENGER',
        },
        profile: passengerProfile,
        token,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Register a new Driver (for future Driver App)
   */
  static async registerDriver({
    fullName,
    phone,
    nicNumber,
    licenseNumber,
    licenseExpiry = '2028-12-31',
    licenseClass = 'D',
    email = null,
    password,
  }) {
    if (!phone || !password || !fullName || !nicNumber || !licenseNumber) {
      throw new Error('Full name, phone, NIC, license number, and password are required.');
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Check if user account exists
      const existingUser = await client.query(
        'SELECT id FROM core.user_accounts WHERE phone = $1 OR (email IS NOT NULL AND email = $2)',
        [phone, email]
      );
      if (existingUser.rows.length > 0) {
        throw new Error('A user account with this phone number or email already exists.');
      }

      // 2. Create driver profile in core.drivers
      const driverSql = `
        INSERT INTO core.drivers (full_name, phone, nic_number, license_number, license_expiry, license_class)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, full_name, phone, nic_number, license_number, license_expiry, license_class, created_at
      `;
      const driverRes = await client.query(driverSql, [
        fullName,
        phone,
        nicNumber,
        licenseNumber,
        licenseExpiry,
        licenseClass,
      ]);
      const driverProfile = driverRes.rows[0];

      // 3. Hash password and insert into core.user_accounts
      const hashedPassword = await hashPassword(password);
      const userSql = `
        INSERT INTO core.user_accounts (phone, email, password_hash, user_type, driver_id)
        VALUES ($1, $2, $3, 'DRIVER', $4)
        RETURNING id, phone, email, photo_url AS "photoUrl", user_type, driver_id, created_at
      `;
      const userRes = await client.query(userSql, [phone, email, hashedPassword, driverProfile.id]);
      const userAccount = userRes.rows[0];

      await client.query('COMMIT');

      // 4. Generate JWT Token
      const token = generateToken({
        userId: userAccount.id,
        role: 'DRIVER',
        driverId: driverProfile.id,
        phone: userAccount.phone,
      });

      return {
        user: {
          id: userAccount.id,
          phone: userAccount.phone,
          email: userAccount.email,
          photoUrl: userAccount.photoUrl || null,
          userType: 'DRIVER',
        },
        profile: driverProfile,
        token,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Unified Login for Passengers and Drivers
   */
  static async login({ identifier, password }) {
    if (!identifier || !password) {
      throw new Error('Phone number or email, and password are required.');
    }

    const cleanIdentifier = identifier.trim().toLowerCase();

    // 1. Find user account in core.user_accounts
    const userSql = `
      SELECT id, phone, email, photo_url AS "photoUrl", password_hash, user_type, passenger_id, driver_id, is_active
      FROM core.user_accounts
      WHERE LOWER(phone) = $1 OR LOWER(email) = $1
    `;
    const userRes = await query(userSql, [cleanIdentifier]);
    if (userRes.rows.length === 0) {
      throw new Error('Invalid phone number/email or password.');
    }

    const user = userRes.rows[0];
    if (!user.is_active) {
      throw new Error('Your account has been deactivated. Please contact support.');
    }

    // 2. Verify password with bcrypt
    const isPasswordValid = await comparePassword(password, user.password_hash);
    if (!isPasswordValid) {
      throw new Error('Invalid phone number/email or password.');
    }

    // 3. Fetch profile details according to user_type
    let profile = null;
    if (user.user_type === 'PASSENGER' && user.passenger_id) {
      const passRes = await query('SELECT * FROM core.passengers WHERE id = $1', [user.passenger_id]);
      profile = passRes.rows.length > 0 ? passRes.rows[0] : null;
    } else if (user.user_type === 'DRIVER' && user.driver_id) {
      const driverRes = await query('SELECT * FROM core.drivers WHERE id = $1', [user.driver_id]);
      profile = driverRes.rows.length > 0 ? driverRes.rows[0] : null;
    }

    // 4. Update last_login_at
    await query('UPDATE core.user_accounts SET last_login_at = NOW() WHERE id = $1', [user.id]);

    // 5. Generate JWT Token
    const token = generateToken({
      userId: user.id,
      role: user.user_type,
      passengerId: user.passenger_id,
      driverId: user.driver_id,
      phone: user.phone,
    });

    return {
      user: {
        id: user.id,
        phone: user.phone,
        email: user.email,
        photoUrl: user.photoUrl || null,
        userType: user.user_type,
      },
      profile,
      token,
    };
  }

  /**
   * Get user profile by user account ID
   */
  static async getProfile(userId) {
    const userRes = await query(
      'SELECT id, phone, email, photo_url AS "photoUrl", user_type, passenger_id, driver_id, is_active, created_at, last_login_at FROM core.user_accounts WHERE id = $1',
      [userId]
    );

    if (userRes.rows.length === 0) {
      throw new Error('User not found.');
    }

    const user = userRes.rows[0];
    let profile = null;

    if (user.user_type === 'PASSENGER' && user.passenger_id) {
      const passRes = await query('SELECT * FROM core.passengers WHERE id = $1', [user.passenger_id]);
      profile = passRes.rows.length > 0 ? passRes.rows[0] : null;
    } else if (user.user_type === 'DRIVER' && user.driver_id) {
      const driverRes = await query('SELECT * FROM core.drivers WHERE id = $1', [user.driver_id]);
      profile = driverRes.rows.length > 0 ? driverRes.rows[0] : null;
    }

    return {
      user,
      profile,
    };
  }

  /**
   * Update passenger profile details in core.passengers and core.user_accounts
   */
  static async updateProfile({ userId, passengerId, fullName, phone, email, photoUrl }) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Get current user_account
      const userRes = await client.query(
        'SELECT id, phone, email, photo_url, passenger_id FROM core.user_accounts WHERE id = $1',
        [userId]
      );
      if (userRes.rows.length === 0) {
        throw new Error('User account not found.');
      }
      const currentUser = userRes.rows[0];
      const pId = passengerId || currentUser.passenger_id;

      // 2. Check if phone or email is already taken by ANOTHER user_account
      if (phone || email) {
        const checkSql = `
          SELECT id FROM core.user_accounts 
          WHERE id <> $1 AND (
            ($2::text IS NOT NULL AND phone = $2) OR 
            ($3::text IS NOT NULL AND email IS NOT NULL AND email = $3)
          )
        `;
        const checkRes = await client.query(checkSql, [userId, phone || null, email || null]);
        if (checkRes.rows.length > 0) {
          throw new Error('Another user account with this phone number or email already exists.');
        }
      }

      // 3. Update core.passengers if passengerId exists
      let updatedPassenger = null;
      if (pId) {
        const passUpdateSql = `
          UPDATE core.passengers
          SET 
            full_name = COALESCE($1, full_name),
            phone = COALESCE($2, phone),
            email = COALESCE($3, email),
            updated_at = NOW()
          WHERE id = $4
          RETURNING id, full_name AS "fullName", phone, email
        `;
        const passRes = await client.query(passUpdateSql, [fullName || null, phone || null, email || null, pId]);
        if (passRes.rows.length > 0) {
          updatedPassenger = passRes.rows[0];
        }
      }

      // 4. Update core.user_accounts
      const userUpdateSql = `
        UPDATE core.user_accounts
        SET 
          phone = COALESCE($1, phone),
          email = COALESCE($2, email),
          photo_url = COALESCE($3, photo_url),
          updated_at = NOW()
        WHERE id = $4
        RETURNING id, phone, email, photo_url AS "photoUrl"
      `;
      const updatedUserRes = await client.query(userUpdateSql, [phone || null, email || null, photoUrl !== undefined ? photoUrl : null, userId]);
      const updatedUser = updatedUserRes.rows[0];

      await client.query('COMMIT');

      return {
        user: {
          id: updatedUser.id,
          phone: updatedUser.phone,
          email: updatedUser.email,
          photoUrl: updatedUser.photoUrl,
        },
        profile: updatedPassenger ? {
          id: updatedPassenger.id,
          fullName: updatedPassenger.fullName,
          phone: updatedPassenger.phone,
          email: updatedPassenger.email,
        } : null,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Save / Update push notification token for user account
   */
  static async savePushToken({ userId, pushToken }) {
    if (!pushToken) {
      throw new Error('Push token is required.');
    }

    const sql = `
      UPDATE core.user_accounts
      SET push_token = $1, updated_at = NOW()
      WHERE id = $2
      RETURNING id, phone, email, push_token AS "pushToken"
    `;
    const res = await query(sql, [pushToken, userId]);
    if (res.rows.length === 0) {
      throw new Error('User account not found.');
    }
    return res.rows[0];
  }
}
