# iOS Green Reading Integration Example

This folder contains a SwiftUI example demonstrating how to integrate with the green reading API.

## Files

- `GreenReadingView.swift` - Complete SwiftUI view with:
  - Input fields for green ID, ball position, and hole position
  - API integration using URLSession
  - Visualization of aim line and fall line using Canvas

## Usage

1. **Ensure the FastAPI server is running**:
   ```bash
   cd course-mapper
   uvicorn course_mapper.api.server:app --host 0.0.0.0 --port 8081
   ```

2. **Open in Xcode**:
   - Create a new iOS app project or add to existing project
   - Copy `GreenReadingView.swift` into your project
   - Ensure iOS 15+ deployment target (for Canvas API)

3. **Configure API URL**:
   - For Simulator: Use `http://localhost:8081`
   - For physical device: Use `http://YOUR_MAC_IP:8081`

4. **Run the view**:
   - Enter a green feature ID (must have processed elevation data)
   - Enter ball and hole coordinates
   - Tap "Get Green Read" to fetch and visualize

## API Endpoint

**POST** `/greens/{course_feature_id}/read`

**Request Body**:
```json
{
  "ball_lat": 36.568,
  "ball_lon": -121.95,
  "hole_lat": 36.5681,
  "hole_lon": -121.949
}
```

**Response**:
```json
{
  "aim_line": [{"lat": 36.568, "lon": -121.95}, ...],
  "fall_line_from_hole": [{"lat": 36.5681, "lon": -121.949}, ...],
  "aim_offset_feet": 2.5,
  "ball_slope_percent": 1.2,
  "hole_slope_percent": 0.8,
  "max_slope_along_line": 2.1
}
```

## Visualization

The view displays:
- **Blue line**: Aim line (break path from ball to hole)
- **Orange line**: Fall line (downhill path from hole)
- **Gray dashed line**: Direct line (straight path)
- **White circle**: Ball position
- **Black circle**: Hole position

## Notes

- This is an example/reference implementation, not production-grade code
- Error handling is basic - add more robust error handling for production
- Coordinate transformations are simplified - for production, use proper map projections
- Canvas visualization is a simple 2D overlay - for production, integrate with MapKit



