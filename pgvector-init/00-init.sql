

-- Create databases for AI services
CREATE DATABASE surfsense;
CREATE DATABASE presenton;
CREATE DATABASE n8n;
CREATE DATABASE open_webui;

-- Enable pgvector extension for databases that need it
\c surfsense;
CREATE EXTENSION IF NOT EXISTS vector;

\c presenton;
CREATE EXTENSION IF NOT EXISTS vector;
