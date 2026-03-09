# Caddie.AI

An intelligent golf caddie app for iOS that uses AI to provide club recommendations, course strategy, and putting analysis.

## Project Structure

```
Caddie.AI/
├── ios/                    # iOS/Xcode project
│   ├── Caddie.ai.xcodeproj
│   └── Caddie.ai/          # Swift source files
│
├── backend/                # Node.js backend API
│   ├── index.js           # Express server
│   ├── package.json       # Node dependencies
│   └── node_modules/      # npm packages
│
├── .gitignore
└── README.md
```

## Getting Started

### Prerequisites

- **iOS Development**: Xcode 15+ with iOS 17+ SDK
- **Backend**: Node.js 16+ and npm

### iOS App Setup

1. Open the iOS project:
   ```bash
   cd ios
   open Caddie.ai.xcodeproj
   ```

2. Build and run in Xcode:
   - Select a simulator or device
   - Press Cmd+R to build and run

### Backend API Setup

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Install dependencies (if needed):
   ```bash
   npm install
   ```

3. Set up environment variables:
   ```bash
   export OPENAI_API_KEY="your-openai-api-key-here"
   ```

4. Start the server:
   ```bash
   node index.js
   ```

   The API will run on `http://localhost:8080`

### API Endpoints

- `GET /api/courses?lat=<lat>&lon=<lon>&query=<query>` - Fetch nearby golf courses
- `POST /api/openai/complete` - Get AI caddie recommendations
- `POST /api/feedback/caddie` - Submit feedback on AI suggestions

## Development

### iOS Development

The iOS app is built with SwiftUI and requires iOS 17+. Key features:

- Course selection and GPS-based course detection
- Round tracking with hole-by-hole scoring
- AI-powered club recommendations
- Player profile with per-club shot preferences
- Onboarding flow for new users

### Backend Development

The backend is a Node.js/Express server that:

- Serves course data (hybrid: local list + external API fallback)
- Integrates with OpenAI API for AI recommendations
- Handles feedback collection for learning

## Configuration

### iOS App Configuration

The app uses build settings for Info.plist keys (location, camera, photo library permissions). Configuration is in `ios/Caddie.ai.xcodeproj/project.pbxproj`.

### Backend Configuration

Create a `.env` file in the `backend/` directory (or use environment variables):

```
OPENAI_API_KEY=your-key-here
```

## Building & Running

### iOS
```bash
cd ios
xcodebuild -project Caddie.ai.xcodeproj -scheme Caddie.ai -sdk iphonesimulator
```

### Backend
```bash
cd backend
node index.js
```

## Testing

### Verify iOS Build
```bash
cd ios
xcodebuild -project Caddie.ai.xcodeproj -scheme Caddie.ai -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Verify Backend
```bash
cd backend
node index.js
# In another terminal:
curl http://localhost:8080/api/courses?lat=37.7749&lon=-122.4194
```

## License

ISC

