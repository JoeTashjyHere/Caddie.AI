#!/usr/bin/env python3
"""
Helper script to run database migrations.

Usage:
    python scripts/run_migration.py db/schema.sql
    python scripts/run_migration.py db/add_course_features.sql
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from course_mapper.db import db

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scripts/run_migration.py <migration_file.sql>")
        sys.exit(1)
    
    migration_file = sys.argv[1]
    if not os.path.exists(migration_file):
        print(f"Error: Migration file not found: {migration_file}")
        sys.exit(1)
    
    print(f"Running migration: {migration_file}")
    success = db.run_migration(migration_file)
    
    if success:
        print("✅ Migration completed successfully")
    else:
        print("❌ Migration failed")
        sys.exit(1)



