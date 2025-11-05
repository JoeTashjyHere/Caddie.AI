const express = require("express");
const fetch = require("node-fetch"); // v2

const app = express();
app.use(express.json());

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

// Local in-memory courses (starter list)
const localCourses = [
  { id: "pebble", name: "Pebble Beach Golf Links", par: 72, lat: 36.568, lon: -121.95 },
  { id: "augusta", name: "Augusta National Golf Club", par: 72, lat: 33.502, lon: -82.021 },
  { id: "st-andrews", name: "St. Andrews Links", par: 72, lat: 56.340, lon: -2.818 },
  { id: "local-muni", name: "Local Public Course", par: 70, lat: 37.7749, lon: -122.4194 },
  { id: "country-club", name: "Country Club Course", par: 71, lat: 37.7849, lon: -122.4094 },
  { id: "riverside", name: "Riverside Golf Club", par: 72, lat: 37.7649, lon: -122.4294 },
  { id: "mountain-view", name: "Mountain View Golf Course", par: 69, lat: 37.7549, lon: -122.4394 }
];

// Helper function to fetch external courses (stub for now)
async function fetchExternalCourses(lat, lon, query) {
  // TODO: Replace with real external API call
  // Examples:
  // - Google Places API: https://developers.google.com/maps/documentation/places/web-service/search
  // - Mapbox Geocoding API: https://docs.mapbox.com/api/search/geocoding/
  // - OpenStreetMap Nominatim: https://nominatim.org/release-docs/develop/api/Search/
  
  // For now, return empty array to trigger fallback
  return [];
  
  // Example implementation structure:
  // try {
  //   const apiKey = process.env.GOOGLE_PLACES_API_KEY;
  //   const response = await fetch(
  //     `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(query || 'golf course')}&location=${lat},${lon}&radius=50000&key=${apiKey}`
  //   );
  //   const data = await response.json();
  //   return data.results.map(result => ({
  //     id: result.place_id,
  //     name: result.name,
  //     par: 72, // Would need to fetch from golf course database
  //     lat: result.geometry.location.lat,
  //     lon: result.geometry.location.lng
  //   }));
  // } catch (error) {
  //   console.error("External API error:", error);
  //   return [];
  // }
}

app.post("/api/openai/complete", async (req, res) => {
  try {
    const { system, user } = req.body;

    if (!OPENAI_API_KEY) {
      return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
    }

    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        // if this model isn't available to your account,
        // OpenAI will return an error object instead of choices[]
        model: "gpt-4o-mini",
        // you can comment this out if your account doesn't like it:
        // response_format: { type: "json_object" },
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      })
    });

    const data = await r.json();

    // log whatever we got so we can see the real shape
    console.log("OpenAI raw response:", JSON.stringify(data, null, 2));

    // handle OpenAI error shape
    if (data.error) {
      return res.status(500).json({ error: "OpenAI call failed", detail: data.error });
    }

    // handle normal shape
    if (Array.isArray(data.choices) && data.choices.length > 0) {
      const content = data.choices[0].message.content;
      return res.json({ resultJSON: content });
    }

    // fallback
    return res.status(500).json({ error: "Unexpected OpenAI response shape", detail: data });
  } catch (err) {
    console.error("Server error:", err);
    res.status(500).json({ error: "OpenAI call failed", detail: String(err) });
  }
});

// Courses endpoint - hybrid approach
app.get("/api/courses", async (req, res) => {
  try {
    const { lat, lon, query } = req.query;

    // 1) Try local in-memory courses first (filtered by query if provided)
    if (query) {
      const filtered = localCourses.filter(c =>
        c.name.toLowerCase().includes(query.toLowerCase())
      );
      if (filtered.length > 0) {
        return res.json({ source: "local", courses: filtered });
      }
    }

    // 2) Try external places API (stub for now)
    try {
      const externalCourses = await fetchExternalCourses(lat, lon, query);
      if (externalCourses.length > 0) {
        return res.json({ source: "external", courses: externalCourses });
      }
    } catch (err) {
      console.error("External course lookup failed:", err);
    }

    // 3) Final fallback: return local list so iOS app always has something to render
    // If we have lat/lon, filter by proximity (optional enhancement)
    let coursesToReturn = localCourses;
    
    if (lat && lon) {
      // Optional: Sort by distance (simple implementation)
      const userLat = parseFloat(lat);
      const userLon = parseFloat(lon);
      
      coursesToReturn = localCourses
        .filter(c => c.lat && c.lon)
        .map(course => ({
          ...course,
          distance: Math.sqrt(
            Math.pow(course.lat - userLat, 2) + Math.pow(course.lon - userLon, 2)
          )
        }))
        .sort((a, b) => a.distance - b.distance)
        .map(({ distance, ...course }) => course);
    }

    return res.json({ source: "fallback-local", courses: coursesToReturn });
  } catch (err) {
    console.error("Error in /api/courses:", err);
    // Even on error, return local courses as fallback
    return res.json({ source: "error-fallback", courses: localCourses });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`API running on ${PORT}`));