-- Migration: Add course_features table for storing segmented course geometries
-- Run this migration after the base schema.sql

-- Create course_features table
-- Note: course_id type depends on courses.id type (INTEGER or UUID)
-- If courses.id is UUID, change course_id type below to UUID
CREATE TABLE IF NOT EXISTS course_features (
    id SERIAL PRIMARY KEY,
    course_id INTEGER NOT NULL,
    hole_number INTEGER NULL,  -- NULL means course-level feature (not yet assigned to hole)
    feature_type TEXT NOT NULL CHECK (feature_type IN ('green', 'fairway', 'bunker', 'water', 'rough', 'tee_box')),
    geom GEOMETRY(MultiPolygon, 4326) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraint: hole_number must be between 1-18 if not NULL
    CONSTRAINT course_features_hole_number_range CHECK (
        hole_number IS NULL OR (hole_number >= 1 AND hole_number <= 18)
    )
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_course_features_course_id_type 
    ON course_features(course_id, feature_type);

CREATE INDEX IF NOT EXISTS idx_course_features_hole_number 
    ON course_features(hole_number) 
    WHERE hole_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_course_features_geom 
    ON course_features USING GIST(geom);

-- Foreign key constraint (commented out if courses.id is UUID)
-- Uncomment and adjust type if needed:
-- ALTER TABLE course_features ADD CONSTRAINT course_features_course_id_fkey 
--     FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE;

-- Update timestamp trigger
CREATE TRIGGER update_course_features_updated_at 
    BEFORE UPDATE ON course_features
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE course_features IS 'Stores segmented course features (greens, fairways, bunkers) extracted from satellite imagery';
COMMENT ON COLUMN course_features.hole_number IS 'NULL for course-level features, 1-18 for hole-specific features';
COMMENT ON COLUMN course_features.feature_type IS 'Type of feature: green, fairway, bunker, water, rough, or tee_box';

