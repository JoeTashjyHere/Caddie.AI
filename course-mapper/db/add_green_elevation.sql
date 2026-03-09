-- Migration: Add green_elevation table for storing elevation grids and derived slope/aspect data
-- Run this migration after course_features table exists

-- Create green_elevation table
CREATE TABLE IF NOT EXISTS green_elevation (
    id SERIAL PRIMARY KEY,
    course_feature_id INTEGER NOT NULL,
    grid_rows INTEGER NOT NULL CHECK (grid_rows > 0),
    grid_cols INTEGER NOT NULL CHECK (grid_cols > 0),
    origin_lat DOUBLE PRECISION NOT NULL,
    origin_lon DOUBLE PRECISION NOT NULL,
    resolution_m DOUBLE PRECISION NOT NULL CHECK (resolution_m > 0),
    elevations BYTEA NOT NULL,  -- Packed float32 array (row-major order)
    slopes BYTEA,  -- Optional: slope magnitudes (percent) as float32 array
    aspects BYTEA,  -- Optional: aspect angles (radians, 0-2π) as float32 array
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Ensure course_feature_id references a green feature
    CONSTRAINT green_elevation_unique_feature UNIQUE (course_feature_id)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_green_elevation_feature_id 
    ON green_elevation(course_feature_id);

-- Add comment explaining storage format
COMMENT ON TABLE green_elevation IS 'Stores elevation grids and derived slope/aspect data for green features. Elevations stored as packed float32 BYTEA (row-major).';
COMMENT ON COLUMN green_elevation.elevations IS 'Packed float32 array in row-major order. Size = grid_rows * grid_cols * 4 bytes. Elevations in meters.';
COMMENT ON COLUMN green_elevation.slopes IS 'Optional slope magnitudes as percent (0-100). Packed float32 array, same dimensions as elevations.';
COMMENT ON COLUMN green_elevation.aspects IS 'Optional aspect angles in radians (0-2π), 0=north, π/2=east, π=south, 3π/2=west. Packed float32 array.';

-- Update timestamp trigger
CREATE TRIGGER update_green_elevation_updated_at 
    BEFORE UPDATE ON green_elevation
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Note: Foreign key constraint should reference course_features table
-- Uncomment if courses.id is INTEGER (adjust if UUID):
-- ALTER TABLE green_elevation ADD CONSTRAINT green_elevation_feature_fkey
--     FOREIGN KEY (course_feature_id) REFERENCES course_features(id) ON DELETE CASCADE;



