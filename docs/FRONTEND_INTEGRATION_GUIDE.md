# Frontend Integration Guide
## Backend API & WebSocket Documentation

**Last Updated:** 2025-01-28
**Backend URL:** `https://api-prod.roboad.ai`

---

## Table of Contents

1. [System Architecture Overview](#system-architecture-overview)
2. [Authentication](#authentication)
3. [REST API Endpoints](#rest-api-endpoints)
4. [WebSocket Events](#websocket-events)
5. [Progressive Screenshot Loading](#progressive-screenshot-loading)
6. [Complete Integration Example](#complete-integration-example)
7. [Error Handling](#error-handling)
8. [Best Practices](#best-practices)

---

## System Architecture Overview

### How It Works

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   Frontend  │         │   Backend   │         │     S3      │
│             │         │   (API +    │         │  (Storage)  │
│             │         │  WebSocket) │         │             │
└─────────────┘         └─────────────┘         └─────────────┘
       │                       │                       │
       │ 1. Connect WS         │                       │
       ├──────────────────────>│                       │
       │    (auth event)       │                       │
       │                       │                       │
       │ 2. Create Scan        │                       │
       ├──────────────────────>│                       │
       │  POST /api/scans      │                       │
       │                       │                       │
       │<──────────────────────┤                       │
       │   {scan_id, status}   │                       │
       │                       │                       │
       │ 3. Join Scan Room     │                       │
       ├──────────────────────>│                       │
       │   (join event)        │                       │
       │                       │                       │
       │<──────────────────────┤                       │
       │  scan:progress (15%)  │                       │
       │                       │                       │
       │<──────────────────────┤                       │
       │ scan:screenshot_loading│                      │
       │                       │                       │
       │<──────────────────────┤                       │
       │ scan:progress (30%)   │                       │
       │                       │                       │
       │<──────────────────────┤ 4. Upload             │
       │ scan:screenshot       │──────────────────────>│
       │  (compressed JPEG)    │   screenshot.png      │
       │                       │                       │
       │<──────────────────────┤                       │
       │ scan:progress (60%)   │                       │
       │                       │                       │
       │<──────────────────────┤                       │
       │ scan:completed        │                       │
       │  {screenshot_url,     │                       │
       │   analysis, seo}      │                       │
       │                       │                       │
       │ 5. Display Results    │                       │
       │                       │                       │
```

### Key Components

1. **REST API**: Create scans, fetch scan details, get screenshot URLs
2. **WebSocket (Socket.io)**: Real-time progress updates, progressive screenshot loading
3. **S3 Storage**: Full-quality screenshots stored at `scans/{scan_id}/screenshot.png`

---

## Authentication

The backend supports **two authentication modes**:

### 1. Authenticated Users (Clerk JWT)

For logged-in users, provide the Clerk JWT token in the `Authorization` header:

```javascript
// REST API
fetch('https://api-prod.roboad.ai/api/scans', {
  headers: {
    'Authorization': `Bearer ${clerkToken}`,
    'Content-Type': 'application/json'
  }
})

// Socket.io
socket.emit('auth', {
  token: clerkToken,
  session_id: null  // Optional: can be null for authenticated users
})
```

### 2. Anonymous Users (Session ID)

For anonymous users, use a session ID in the `X-Session-ID` header:

```javascript
// Generate session ID once per browser session
const sessionId = localStorage.getItem('session_id') || crypto.randomUUID();
localStorage.setItem('session_id', sessionId);

// REST API
fetch('https://api-prod.roboad.ai/api/scans', {
  headers: {
    'X-Session-ID': sessionId,
    'Content-Type': 'application/json'
  }
})

// Socket.io
socket.emit('auth', {
  token: null,
  session_id: sessionId
})
```

### Session ID Management

**IMPORTANT**: The session ID must be consistent across REST API and WebSocket calls:

```javascript
// ✅ CORRECT - Same session ID everywhere
const sessionId = getOrCreateSessionId();

// Use in REST API
headers: { 'X-Session-ID': sessionId }

// Use in Socket.io
socket.emit('auth', { session_id: sessionId })

// ❌ WRONG - Different session IDs
// REST API uses session_id_1
// Socket.io uses session_id_2
// → Access denied! Backend sees them as different users
```

---

## REST API Endpoints

### 1. Create Scan

**Endpoint:** `POST /api/scans`

Creates a new scan and starts processing in the background.

**Request:**
```javascript
POST /api/scans
Headers:
  - Authorization: Bearer {clerk_token}  (for authenticated users)
  - X-Session-ID: {session_id}          (for anonymous users)
  - Content-Type: application/json

Body:
{
  "url": "https://example.com"
}
```

**Response:**
```json
{
  "scan_id": "aeeeb548-e1de-400c-9431-3847a8894327",
  "website_id": "12345678-abcd-efgh-ijkl-123456789abc",
  "url": "https://example.com",
  "domain": "example.com",
  "status": "pending",
  "user_id": "user_2X...",
  "session_id": "25d26ad3-a452-40ed-8fa1-57e9ca9e7209",
  "created_at": "2025-01-28T12:34:56.789Z"
}
```

---

### 2. Get Scan Details

**Endpoint:** `GET /api/scans/{scan_id}`

Retrieves current scan status and results (if completed).

**Response (Completed):**
```json
{
  "scan_id": "aeeeb548-e1de-400c-9431-3847a8894327",
  "url": "https://example.com",
  "status": "completed",
  "scan_data": {
    "analysis": { ... },
    "seo": { ... }
  },
  "screenshot_url": "https://s3.amazonaws.com/.../screenshot.png?X-Amz-...",
  "processing_time_ms": 12456,
  "created_at": "2025-01-28T12:34:56.789Z",
  "completed_at": "2025-01-28T12:35:09.245Z"
}
```

**Key Field:** `screenshot_url` - Presigned S3 URL (valid for 1 hour)

---

## WebSocket Events

### Connection Setup

```javascript
import { io } from 'socket.io-client';

const socket = io('https://api-prod.roboad.ai', {
  transports: ['websocket', 'polling'],
  reconnection: true
});

socket.on('connect', () => {
  socket.emit('auth', {
    token: clerkToken || null,
    session_id: sessionId || null
  });
});

socket.on('auth_response', (data) => {
  console.log('Authenticated:', data);
});
```

---

### Event: `scan:progress`

**Purpose:** Update progress bar and status message

**Timeline:**
- `10%` - "Starting scan..."
- `15%` - "Capturing screenshot..."
- `30%` - "Screenshot captured successfully"
- `60%` - "Website analysis complete"
- `80%` - "Analyzing SEO..."
- `100%` - "Scan complete!"

```javascript
socket.on('scan:progress', (data) => {
  // data = { scan_id, percent, message }
  updateProgressBar(data.percent);
  updateStatusMessage(data.message);
});
```

---

### Event: `scan:screenshot_loading` ⭐

**Purpose:** Show loading skeleton for screenshot (~15% progress)

```javascript
socket.on('scan:screenshot_loading', (data) => {
  // data = { scan_id }
  setScreenshotLoading(true);
});
```

---

### Event: `scan:screenshot` ⭐ CRITICAL

**Purpose:** Progressive loading - show compressed preview immediately (~30% progress)

```javascript
socket.on('scan:screenshot', (data) => {
  // data = {
  //   scan_id: string,
  //   screenshot: string  // "data:image/jpeg;base64,/9j/4AAQ..."
  // }

  // Display compressed preview immediately
  setScreenshotPreview(data.screenshot);
  setScreenshotLoading(false);
});
```

**Image Quality:**
- Format: JPEG (compressed from PNG)
- Max width: 800px (maintains aspect ratio)
- Quality: 65% (optimized for fast transmission)
- **Use case: Show to user while waiting for analysis results**

---

### Event: `scan:completed` ⭐ CRITICAL

**Purpose:** Deliver final results and full-quality screenshot URL (100% progress)

```javascript
socket.on('scan:completed', (data) => {
  // data = {
  //   scan_id: string,
  //   results: {
  //     screenshot_url: string,  // Presigned S3 URL
  //     analysis: { ... },
  //     seo: { ... }
  //   }
  // }

  // Replace preview with full-quality screenshot
  setScreenshotUrl(data.results.screenshot_url);
  setAnalysis(data.results.analysis);
  setSeo(data.results.seo);
});
```

---

## Progressive Screenshot Loading

### The Problem

Users want to see **something visual** while waiting for analysis results. The scan takes 10-15 seconds, and showing just a progress bar is boring.

### The Solution

**Progressive Loading in 3 Stages:**

```
Stage 1: Loading Skeleton (0-30%)
  ┌─────────────────────┐
  │   ░░░░░░░░░░░░░░░   │  ← Animated skeleton
  │   ░░░░░░░░░░░░░░░   │
  └─────────────────────┘

Stage 2: Compressed Preview (30-100%)
  ┌─────────────────────┐
  │ [Compressed JPEG]   │  ← Fast to load, lower quality
  │  800px max width    │     Good enough to see the site
  │  Quality: 65%       │
  └─────────────────────┘

Stage 3: Full Quality (After 100%)
  ┌─────────────────────┐
  │ [Full PNG from S3]  │  ← Original quality
  │  Original size      │     Perfect quality
  └─────────────────────┘
```

---

### React Implementation

```jsx
import { useState, useEffect } from 'react';
import { io } from 'socket.io-client';

function ScanResults({ scanId }) {
  // State management
  const [progress, setProgress] = useState(0);
  const [message, setMessage] = useState('');

  // Screenshot stages
  const [screenshotLoading, setScreenshotLoading] = useState(false);
  const [screenshotPreview, setScreenshotPreview] = useState(null);  // Compressed JPEG
  const [screenshotUrl, setScreenshotUrl] = useState(null);          // Full quality S3 URL

  // Results
  const [analysis, setAnalysis] = useState(null);
  const [seo, setSeo] = useState(null);

  useEffect(() => {
    const socket = io('https://api-prod.roboad.ai');

    // Authenticate
    socket.on('connect', () => {
      socket.emit('auth', {
        token: clerkToken || null,
        session_id: sessionId || null
      });
    });

    // Join scan room
    socket.on('auth_response', () => {
      socket.emit('join', { scan_id: scanId });
    });

    // Listen for progress updates
    socket.on('scan:progress', (data) => {
      setProgress(data.percent);
      setMessage(data.message);
    });

    // Stage 1: Show loading skeleton
    socket.on('scan:screenshot_loading', () => {
      setScreenshotLoading(true);
    });

    // Stage 2: Show compressed preview ASAP
    socket.on('scan:screenshot', (data) => {
      setScreenshotPreview(data.screenshot);  // Base64 JPEG
      setScreenshotLoading(false);
    });

    // Stage 3: Replace with full quality when done
    socket.on('scan:completed', (data) => {
      setScreenshotUrl(data.results.screenshot_url);  // S3 URL
      setAnalysis(data.results.analysis);
      setSeo(data.results.seo);
      setProgress(100);
    });

    return () => socket.disconnect();
  }, [scanId]);

  return (
    <div className="scan-results">
      {/* Progress Bar */}
      <ProgressBar value={progress} message={message} />

      {/* Screenshot Display */}
      <div className="screenshot-container">
        {screenshotLoading && <ScreenshotSkeleton />}

        {screenshotPreview && !screenshotUrl && (
          <img
            src={screenshotPreview}  // Stage 2: Compressed preview
            alt="Website Preview"
            className="screenshot-preview"
          />
        )}

        {screenshotUrl && (
          <img
            src={screenshotUrl}  // Stage 3: Full quality
            alt="Website Screenshot"
            className="screenshot-full"
          />
        )}
      </div>

      {/* Results */}
      {analysis && <AnalysisResults data={analysis} />}
      {seo && <SeoResults data={seo} />}
    </div>
  );
}
```

---

### Why 3 Stages?

**Stage 1: Loading Skeleton (0-30%)**
- User knows something is happening
- Size: 0 bytes (CSS animation)
- Event: `scan:screenshot_loading`

**Stage 2: Compressed Preview (30-100%)**
- User can see the website while waiting
- Size: ~50-100 KB (JPEG, 800px, 65% quality)
- Event: `scan:screenshot`
- **Benefit: Fast WebSocket transmission, good enough quality**

**Stage 3: Full Quality (100%+)**
- Professional quality for final results
- Size: ~200-500 KB (PNG, original dimensions)
- Event: `scan:completed`
- **Benefit: Perfect quality, loaded from S3 CDN**

---

## Complete Integration Example

### Full Flow: Create Scan → Progressive Loading → Display Results

```javascript
import { io } from 'socket.io-client';

class ScanManager {
  constructor() {
    this.socket = null;
    this.sessionId = this.getOrCreateSessionId();
  }

  getOrCreateSessionId() {
    let sessionId = localStorage.getItem('session_id');
    if (!sessionId) {
      sessionId = crypto.randomUUID();
      localStorage.setItem('session_id', sessionId);
    }
    return sessionId;
  }

  getAuthHeaders(clerkToken) {
    if (clerkToken) {
      return { 'Authorization': `Bearer ${clerkToken}` };
    } else {
      return { 'X-Session-ID': this.sessionId };
    }
  }

  async connectWebSocket(clerkToken) {
    return new Promise((resolve, reject) => {
      this.socket = io('https://api-prod.roboad.ai', {
        transports: ['websocket', 'polling'],
        reconnection: true
      });

      this.socket.on('connect', () => {
        this.socket.emit('auth', {
          token: clerkToken || null,
          session_id: this.sessionId
        });
      });

      this.socket.on('auth_response', (data) => {
        console.log('WebSocket authenticated:', data);
        resolve(data);
      });

      this.socket.on('connect_error', reject);
    });
  }

  async createScan(url, clerkToken) {
    const response = await fetch('https://api-prod.roboad.ai/api/scans', {
      method: 'POST',
      headers: {
        ...this.getAuthHeaders(clerkToken),
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ url })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.detail || 'Failed to create scan');
    }

    return await response.json();
  }

  async joinScanRoom(scanId) {
    return new Promise((resolve) => {
      this.socket.emit('join', { scan_id: scanId });
      this.socket.once('joined', resolve);
    });
  }

  listenForScanEvents(callbacks) {
    this.socket.on('scan:progress', (data) => {
      callbacks.onProgress?.(data.percent, data.message);
    });

    this.socket.on('scan:screenshot_loading', () => {
      callbacks.onScreenshotLoading?.();
    });

    this.socket.on('scan:screenshot', (data) => {
      callbacks.onScreenshotPreview?.(data.screenshot);
    });

    this.socket.on('scan:completed', (data) => {
      callbacks.onCompleted?.(data.results);
    });

    this.socket.on('scan:failed', (data) => {
      callbacks.onFailed?.(data.error);
    });
  }

  async startScan(url, clerkToken, callbacks) {
    try {
      await this.connectWebSocket(clerkToken);
      const scan = await this.createScan(url, clerkToken);
      await this.joinScanRoom(scan.scan_id);
      this.listenForScanEvents(callbacks);
      return scan.scan_id;
    } catch (error) {
      console.error('Error starting scan:', error);
      callbacks.onError?.(error.message);
      throw error;
    }
  }

  disconnect() {
    if (this.socket) this.socket.disconnect();
  }
}

// Usage
const scanManager = new ScanManager();

async function scanWebsite(url) {
  const clerkToken = await clerk.session?.getToken();

  const scanId = await scanManager.startScan(url, clerkToken, {
    onProgress: (percent, message) => {
      updateProgressBar(percent);
      updateStatusMessage(message);
    },

    onScreenshotLoading: () => {
      showScreenshotSkeleton();
    },

    onScreenshotPreview: (screenshot) => {
      displayScreenshotPreview(screenshot);  // Base64 JPEG
    },

    onCompleted: (results) => {
      displayScreenshotFull(results.screenshot_url);  // S3 presigned URL
      displayAnalysisResults(results.analysis);
      displaySeoResults(results.seo);
    },

    onFailed: (error) => {
      showErrorMessage(error);
    }
  });

  console.log('Scan started:', scanId);
}
```

---

## Error Handling

### Common Errors

#### 1. Session Mismatch (403)

```javascript
// ✅ CORRECT
const sessionId = localStorage.getItem('session_id') || crypto.randomUUID();
localStorage.setItem('session_id', sessionId);

// Use everywhere
socket.emit('auth', { session_id: sessionId });
fetch('/api/scans', { headers: { 'X-Session-ID': sessionId } });
```

#### 2. Expired Presigned URL

Presigned URLs expire after 1 hour. Refresh by calling:

```javascript
GET /api/scans/{scan_id}/screenshot-url
```

---

## Best Practices

### ✅ DO

1. **Store session ID persistently**
```javascript
const sessionId = localStorage.getItem('session_id') || crypto.randomUUID();
localStorage.setItem('session_id', sessionId);
```

2. **Show all 3 stages**
```javascript
// Loading skeleton → Compressed preview → Full quality
```

3. **Handle all errors**
```javascript
socket.on('scan:failed', handleError);
socket.on('error', handleError);
socket.on('connect_error', handleConnectionError);
```

4. **Clean up WebSocket connections**
```javascript
useEffect(() => {
  const socket = io('...');
  return () => socket.disconnect();
}, []);
```

### ❌ DON'T

1. **Generate new session ID every time**
```javascript
const sessionId = crypto.randomUUID();  // ❌ No persistence!
```

2. **Wait for full quality only**
```javascript
// ❌ Leaves users staring at blank space for 30 seconds
```

3. **Ignore errors**
```javascript
socket.on('scan:failed', () => {});  // ❌ User sees nothing!
```

---

## Summary

### Quick Start Checklist

- [ ] Connect to WebSocket: `io('https://api-prod.roboad.ai')`
- [ ] Authenticate: `socket.emit('auth', { token, session_id })`
- [ ] Create scan: `POST /api/scans { url }`
- [ ] Join scan room: `socket.emit('join', { scan_id })`
- [ ] Listen for events: `scan:screenshot_loading`, `scan:screenshot`, `scan:completed`
- [ ] Display 3 stages: skeleton → preview → full quality
- [ ] Handle errors: `scan:failed`, `error`
- [ ] Clean up: `socket.disconnect()`

### Key Takeaways

1. **Use WebSocket for real-time updates** (don't poll!)
2. **Progressive loading = better UX** (3 stages: skeleton → preview → full)
3. **Session ID must be consistent** across REST and WebSocket
4. **Presigned URLs expire** after 1 hour (refresh when needed)
5. **Always handle errors** gracefully

---

**Questions?** Contact the backend team.

**Last Updated:** 2025-01-28
