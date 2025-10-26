-- =====================================================================
-- pgvector-init/00-init.sql
-- Initializes shared AI Postgres with required databases and extensions.
-- Databases: surfsense, presenton
-- Extension: vector (pgvector)
-- Run automatically by Docker entrypoint on first initialization only.
-- =====================================================================

-- Create application databases (owned by superuser 'postgres')
CREATE DATABASE surfsense WITH OWNER postgres TEMPLATE template0 ENCODING 'UTF8';
CREATE DATABASE presenton WITH OWNER postgres TEMPLATE template0 ENCODING 'UTF8';

-- Enable pgvector extension in each database
\connect surfsense
CREATE EXTENSION IF NOT EXISTS vector;

\connect presenton
CREATE EXTENSION IF NOT EXISTS vector;

-- Optional: grant privileges to owner (postgres)
-- (Default owner already has full privileges)