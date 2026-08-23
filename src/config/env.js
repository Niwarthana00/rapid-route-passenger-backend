import dotenv from 'dotenv';
dotenv.config();

export const env = {
  PORT: process.env.PORT || 5000,
  NODE_ENV: process.env.NODE_ENV || 'development',
  DB: {
    HOST: process.env.DB_HOST || 'localhost',
    PORT: parseInt(process.env.DB_PORT || '5432', 10),
    USER: process.env.DB_USER || 'postgres',
    PASSWORD: process.env.DB_PASSWORD || 'postgres',
    DATABASE: process.env.DB_NAME || 'rapid_route',
    URL: process.env.DATABASE_URL,
  },
  JWT_SECRET: process.env.JWT_SECRET || 'rapid_route_jwt_secret_default_key',
  CORS_ORIGIN: process.env.CORS_ORIGIN || '*',
};
