-- Generated from generator/demo_specs/aws-vietnam-renewable-grid.json
-- Regenerate with: python3 generator/gen_repo_docs.py aws-vietnam-renewable-grid
-- This is the schema that is actually deployed for VIETNAM_RENEWABLE_GRID.

-- VIETNAM_RENEWABLE_GRID  (Grid Integration)
-- generated from generator/demo_specs/aws-vietnam-renewable-grid.json - do not hand-edit
CREATE DATABASE IF NOT EXISTS VIETNAM_RENEWABLE_GRID;
CREATE SCHEMA IF NOT EXISTS VIETNAM_RENEWABLE_GRID.RAW;
CREATE SCHEMA IF NOT EXISTS VIETNAM_RENEWABLE_GRID.CURATED;
CREATE SCHEMA IF NOT EXISTS VIETNAM_RENEWABLE_GRID.APP;
USE DATABASE VIETNAM_RENEWABLE_GRID;

-- 5 real regions; entity names carry their region so the two always agree
