import pkg from 'pg';
const { Pool } = pkg;
import { env } from './env.js';

let poolConfig;

if (env.DB.URL) {
  poolConfig = {
    connectionString: env.DB.URL,
  };
} else {
  poolConfig = {
    host: env.DB.HOST,
    port: env.DB.PORT,
    user: env.DB.USER,
    password: env.DB.PASSWORD,
    database: env.DB.DATABASE,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  };
}

export const pool = new Pool(poolConfig);

pool.on('error', (err) => {
  console.error('Unexpected error on idle PostgreSQL client', err);
});

export const query = async (text, params) => {
  const start = Date.now();
  const res = await pool.query(text, params);
  const duration = Date.now() - start;
  if (env.NODE_ENV === 'development') {
    console.log('Executed query', { text: text.substring(0, 100), duration: `${duration}ms`, rows: res.rowCount });
  }
  return res;
};

export const testDbConnection = async () => {
  try {
    const res = await pool.query('SELECT NOW() AS current_time');
    console.log('✅ PostgreSQL Database connected successfully at:', res.rows[0].current_time);
    return true;
  } catch (error) {
    console.warn('⚠️  PostgreSQL Database connection failed:', error.message);
    console.warn('👉 Please verify PostgreSQL is running with credentials in .env');
    return false;
  }
};
