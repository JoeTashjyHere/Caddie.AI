-- Caddie.AI Course Mapper Database Schema
-- PostgreSQL + PostGIS Extension

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Courses table
CREATE TABLE IF NOT EXISTS courses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    country TEXT,
    city TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    raw_osm_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Indexes
    CONSTRAINT courses_name_not_empty CHECK (char_length(trim(name)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_courses_location ON courses USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_courses_osm_id ON courses(raw_osm_id) WHERE raw_osm_id IS NOT NULL;

-- Holes table
CREATE TABLE IF NOT EXISTS holes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    number INTEGER NOT NULL CHECK (number > 0 AND number <= 18),
    par INTEGER CHECK (par >= 3 AND par <= 6),
    handicap INTEGER CHECK (handicap >= 1 AND handicap <= 18),
    tee_yardages JSONB, -- {"white": 450, "blue": 470, "red": 420}
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT holes_unique_course_number UNIQUE (course_id, number)
);

CREATE INDEX IF NOT EXISTS idx_holes_course_id ON holes(course_id);
CREATE INDEX IF NOT EXISTS idx_holes_number ON holes(number);

-- Hole geometries table
CREATE TABLE IF NOT EXISTS hole_geometries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hole_id UUID NOT NULL REFERENCES holes(id) ON DELETE CASCADE,
    geom_type TEXT NOT NULL CHECK (geom_type IN ('green', 'fairway', 'tee_box', 'bunker', 'water', 'rough')),
    geometry GEOMETRY(POLYGON, 4326), -- Can be MULTIPOLYGON via PostGIS functions
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_hole_geometries_hole_id ON hole_geometries(hole_id);
CREATE INDEX IF NOT EXISTS idx_hole_geometries_type ON hole_geometries(geom_type);
CREATE INDEX IF NOT EXISTS idx_hole_geometries_geometry ON hole_geometries USING GIST(geometry);

-- Green contours table
CREATE TABLE IF NOT EXISTS green_contours (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hole_id UUID NOT NULL REFERENCES holes(id) ON DELETE CASCADE,
    contour_raster_url TEXT, -- URL to stored raster file
    metadata JSONB, -- {"max_slope": 3.5, "avg_slope": 2.1, "max_elevation": 125.5, "min_elevation": 124.2}
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT green_contours_unique_hole UNIQUE (hole_id)
);

CREATE INDEX IF NOT EXISTS idx_green_contours_hole_id ON green_contours(hole_id);

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers
CREATE TRIGGER update_courses_updated_at BEFORE UPDATE ON courses
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_holes_updated_at BEFORE UPDATE ON holes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_hole_geometries_updated_at BEFORE UPDATE ON hole_geometries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_green_contours_updated_at BEFORE UPDATE ON green_contours
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();



