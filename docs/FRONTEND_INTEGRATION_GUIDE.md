# Frontend Integration Guide - Session ID Fix

## What Changed?

We fixed the "Access denied to this scan" error that occurred when anonymous users tried to view scan results in real-time.

### The Problem
Previously, the backend generated a new `session_id` for each scan, which didn't match the `session_id` from the Socket.io connection. This caused access control to fail when trying to join scan rooms.

### The Solution
The backend now accepts a `X-Session-ID` header when creating scans, allowing the frontend to use the same session ID from Socket.io authentication.

---

## Required Frontend Changes

### 1. Update the Scan Creation API Call

**Add `X-Session-ID` header to POST `/api/scans` requests for anonymous users.**

#### Before (Broken)
```typescript
async function createScan(url: string) {
  const response = await fetch(`${API_BASE_URL}/api/scans`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ url })
  });

  return await response.json();
}
```

#### After (Fixed)
```typescript
async function createScan(url: string, sessionId: string | null) {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json'
  };

  // Add session ID for anonymous users
  if (sessionId) {
    headers['X-Session-ID'] = sessionId;
  }

  const response = await fetch(`${API_BASE_URL}/api/scans`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ url })
  });

  return await response.json();
}
```

---

## Complete Integration Example

Here's a complete example showing how to integrate Socket.io authentication with scan creation:

```typescript
import { io, Socket } from 'socket.io-client';

// 1. Initialize Socket.io connection
const socket: Socket = io(API_BASE_URL, {
  transports: ['websocket', 'polling'],
  reconnection: true,
  reconnectionDelay: 1000,
  reconnectionAttempts: 5
});

// 2. Store the session ID received from authentication
let currentSessionId: string | null = null;

// 3. Listen for auth response to get session ID
socket.on('auth_response', (data) => {
  console.log('Auth response:', data);

  if (data.authenticated) {
    console.log('Authenticated as user:', data.user_id);
    currentSessionId = null; // Authenticated users don't need session ID
  } else {
    console.log('Anonymous session created:', data.session_id);
    currentSessionId = data.session_id; // Store this!
  }
});

// 4. Send auth event on connection
socket.on('connect', () => {
  console.log('Socket.io connected');

  // Send auth event (with token if authenticated, null if anonymous)
  socket.emit('auth', {
    token: null, // or getToken() for authenticated users
    session_id: currentSessionId // Send existing session_id if reconnecting
  });
});

// 5. Create scan with the session ID
async function createScanWithSession(url: string) {
  // Wait for auth to complete if needed
  if (currentSessionId === null && !socket.connected) {
    await new Promise((resolve) => {
      socket.once('auth_response', resolve);
    });
  }

  const headers: Record<string, string> = {
    'Content-Type': 'application/json'
  };

  // Add session ID header for anonymous users
  if (currentSessionId) {
    headers['X-Session-ID'] = currentSessionId;
  }

  const response = await fetch(`${API_BASE_URL}/api/scans`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ url })
  });

  if (!response.ok) {
    throw new Error(`API request failed: ${response.status}`);
  }

  const scanData = await response.json();
  console.log('Scan created:', scanData);

  // 6. Join the scan room to receive updates
  socket.emit('join', { scan_id: scanData.scan_id });

  return scanData;
}

// 7. Listen for scan updates
socket.on('scan:progress', (data) => {
  console.log(`Scan ${data.scan_id}: ${data.percent}% - ${data.message}`);
});

socket.on('scan:completed', (data) => {
  console.log('Scan completed:', data);
});

socket.on('scan:failed', (data) => {
  console.error('Scan failed:', data.error);
});

socket.on('error', (data) => {
  console.error('Socket.io error:', data.message);
});
```

---

## Step-by-Step Integration Guide

### Step 1: Initialize Socket.io Connection

```typescript
import { io } from 'socket.io-client';

const API_BASE_URL = process.env.NEXT_PUBLIC_BACKEND_URL!;
const socket = io(API_BASE_URL);
```

### Step 2: Handle Socket.io Authentication

```typescript
let sessionId: string | null = null;

socket.on('connect', () => {
  // Send auth event when connected
  socket.emit('auth', {
    token: null,  // For anonymous users
    session_id: sessionId  // null for first connection, reuse for reconnections
  });
});

socket.on('auth_response', (data) => {
  if (!data.authenticated) {
    // Store session ID for anonymous users
    sessionId = data.session_id;
    console.log('Session ID:', sessionId);
  }
});
```

### Step 3: Create Scan with Session ID

```typescript
async function createScan(url: string) {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json'
  };

  if (sessionId) {
    headers['X-Session-ID'] = sessionId;
  }

  const response = await fetch(`${API_BASE_URL}/api/scans`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ url })
  });

  return await response.json();
}
```

### Step 4: Join Scan Room

```typescript
const scan = await createScan('https://example.com');

// Join room to receive real-time updates
socket.emit('join', { scan_id: scan.scan_id });
```

### Step 5: Listen for Updates

```typescript
socket.on('scan:progress', (data) => {
  // Update UI with progress
  updateProgress(data.percent, data.message);
});

socket.on('scan:completed', (data) => {
  // Show results
  displayResults(data.results);
});
```

### Step 6: Fetching Scan Results (GET Request)

⚠️ **CRITICAL**: When fetching scan data via GET request, anonymous users **MUST** include the `X-Session-ID` header!

```typescript
async function getScan(scanId: string) {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json'
  };

  // IMPORTANT: Include session ID for anonymous users
  if (sessionId) {
    headers['X-Session-ID'] = sessionId;
  }

  const response = await fetch(`${API_BASE_URL}/api/scans/${scanId}`, {
    method: 'GET',
    headers
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch scan: ${response.status}`);
  }

  return await response.json();
}
```

**Why this is needed**: The backend verifies access control on ALL requests, not just when creating scans. Without the session ID, the backend returns `404 Not Found` because it can't verify you own the scan.

---

## React Hook Example

Here's a React hook that handles everything:

```typescript
import { useEffect, useState, useRef } from 'react';
import { io, Socket } from 'socket.io-client';

export function useScanWebSocket() {
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const socketRef = useRef<Socket | null>(null);

  useEffect(() => {
    const API_BASE_URL = process.env.NEXT_PUBLIC_BACKEND_URL!;
    const socket = io(API_BASE_URL);
    socketRef.current = socket;

    socket.on('connect', () => {
      setIsConnected(true);
      socket.emit('auth', {
        token: null,
        session_id: sessionId
      });
    });

    socket.on('disconnect', () => {
      setIsConnected(false);
    });

    socket.on('auth_response', (data) => {
      if (!data.authenticated && data.session_id) {
        setSessionId(data.session_id);
      }
    });

    return () => {
      socket.disconnect();
    };
  }, []);

  const createScan = async (url: string) => {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    if (sessionId) {
      headers['X-Session-ID'] = sessionId;
    }

    const response = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/scans`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ url })
    });

    if (!response.ok) {
      throw new Error(`Scan creation failed: ${response.status}`);
    }

    const scan = await response.json();

    // Join scan room
    socketRef.current?.emit('join', { scan_id: scan.scan_id });

    return scan;
  };

  const getScan = async (scanId: string) => {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    // IMPORTANT: Include session ID for anonymous users
    if (sessionId) {
      headers['X-Session-ID'] = sessionId;
    }

    const response = await fetch(`${process.env.NEXT_PUBLIC_BACKEND_URL}/api/scans/${scanId}`, {
      method: 'GET',
      headers
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch scan: ${response.status}`);
    }

    return await response.json();
  };

  const subscribeScanUpdates = (callbacks: {
    onProgress?: (data: any) => void;
    onCompleted?: (data: any) => void;
    onFailed?: (data: any) => void;
  }) => {
    const socket = socketRef.current;
    if (!socket) return;

    if (callbacks.onProgress) {
      socket.on('scan:progress', callbacks.onProgress);
    }
    if (callbacks.onCompleted) {
      socket.on('scan:completed', callbacks.onCompleted);
    }
    if (callbacks.onFailed) {
      socket.on('scan:failed', callbacks.onFailed);
    }

    return () => {
      if (callbacks.onProgress) socket.off('scan:progress', callbacks.onProgress);
      if (callbacks.onCompleted) socket.off('scan:completed', callbacks.onCompleted);
      if (callbacks.onFailed) socket.off('scan:failed', callbacks.onFailed);
    };
  };

  return {
    isConnected,
    sessionId,
    createScan,
    getScan,
    subscribeScanUpdates,
    socket: socketRef.current
  };
}
```

### Usage in Component

```typescript
function ScanPage() {
  const { createScan, subscribeScanUpdates } = useScanWebSocket();
  const [scanProgress, setScanProgress] = useState(0);
  const [scanResults, setScanResults] = useState(null);

  useEffect(() => {
    const cleanup = subscribeScanUpdates({
      onProgress: (data) => {
        setScanProgress(data.percent);
      },
      onCompleted: (data) => {
        setScanResults(data.results);
      },
      onFailed: (data) => {
        console.error('Scan failed:', data.error);
      }
    });

    return cleanup;
  }, [subscribeScanUpdates]);

  const handleSubmit = async (url: string) => {
    try {
      const scan = await createScan(url);
      console.log('Scan started:', scan.scan_id);
    } catch (error) {
      console.error('Failed to create scan:', error);
    }
  };

  return (
    <div>
      <input type="url" onSubmit={(e) => handleSubmit(e.target.value)} />
      {scanProgress > 0 && <Progress value={scanProgress} />}
      {scanResults && <Results data={scanResults} />}
    </div>
  );
}
```

---

## Testing the Fix

### 1. Test Anonymous User Flow

```typescript
// 1. Open browser console
// 2. Connect to Socket.io
const socket = io('https://api-prod.roboad.ai');

// 3. Listen for auth response
socket.on('auth_response', (data) => {
  console.log('Session ID:', data.session_id);
  window.testSessionId = data.session_id;
});

// 4. Send auth
socket.emit('auth', { token: null, session_id: null });

// 5. Wait for auth_response, then create scan with session ID
await fetch('https://api-prod.roboad.ai/api/scans', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Session-ID': window.testSessionId
  },
  body: JSON.stringify({ url: 'https://example.com' })
}).then(r => r.json()).then(console.log);

// 6. Join scan room (should work without errors!)
socket.emit('join', { scan_id: '<scan_id_from_step_5>' });

// 7. Test GET request (MUST include session ID!)
await fetch(`https://api-prod.roboad.ai/api/scans/<scan_id_from_step_5>`, {
  headers: {
    'X-Session-ID': window.testSessionId  // ← Without this, you get 404!
  }
}).then(r => r.json()).then(console.log);
```

### 2. Verify No Access Denied Error

You should **NOT** see:
```
Socket.io error: { message: "Access denied to this scan" }
```

You **SHOULD** see:
```
{ scan_id: "...", room: "scan_..." }  // Joined successfully!
```

---

## API Endpoints Reference

### Production
- **Base URL**: `https://api-prod.roboad.ai`
- **Socket.io**: `wss://api-prod.roboad.ai/socket.io/`

### Environment Variable
```bash
NEXT_PUBLIC_BACKEND_URL=https://api-prod.roboad.ai
```

---

## Common Issues & Solutions

### Issue: Getting 404 "Scan not found or access denied" on GET requests

**Symptom**:
```
GET /api/scans/5b3b9f19-3a73-472b-9d4a-ba57a07c21a1
{"detail":"Scan not found or access denied"}
```

**Root Cause**: Missing `X-Session-ID` header in GET request.

**Solution**: Include session ID header on **ALL** API requests for anonymous users:
```typescript
// Both POST and GET need the header!
const headers = {
  'Content-Type': 'application/json',
  'X-Session-ID': sessionId  // ← Required for GET too!
};

// Creating scan
await fetch('/api/scans', { method: 'POST', headers, body: ... });

// Fetching scan - ALSO needs session ID!
await fetch(`/api/scans/${scanId}`, { headers });
```

### Issue: Still getting "Access denied to this scan" on Socket.io

**Solution**: Make sure you're sending the `X-Session-ID` header when creating the scan:
```typescript
headers: {
  'X-Session-ID': sessionId  // ← Must match Socket.io session_id!
}
```

### Issue: Session ID is `null` or `undefined`

**Solution**: Wait for `auth_response` event before creating scans:
```typescript
await new Promise((resolve) => {
  socket.once('auth_response', (data) => {
    sessionId = data.session_id;
    resolve();
  });
});
```

### Issue: Not receiving scan updates

**Solution**: Make sure to call `socket.emit('join', { scan_id })` after creating the scan:
```typescript
const scan = await createScan(url);
socket.emit('join', { scan_id: scan.scan_id });  // ← Don't forget this!
```

---

## Summary of Changes

### What the Frontend MUST Do:

1. ✅ Get `session_id` from Socket.io `auth_response` event
2. ✅ Send `X-Session-ID` header when calling `POST /api/scans`
3. ✅ Use the SAME session_id for both Socket.io and API calls

### What Happens Now:

1. ✅ Scan is created with the correct `session_id`
2. ✅ Frontend can join the scan room (no more "Access denied")
3. ✅ Frontend receives real-time progress updates
4. ✅ Frontend gets scan completion notifications

---

## Questions?

If you encounter any issues during integration, please check:

1. Is `X-Session-ID` header being sent? (Check Network tab)
2. Is the session_id the same in Socket.io and API call? (Check console logs)
3. Are you calling `socket.emit('join')` after creating the scan?

For additional help, contact the backend team or refer to:
- `/docs/API_DOCUMENTATION.md` - Full API documentation
- `/docs/AUTH_STRATEGY.md` - Authentication architecture
