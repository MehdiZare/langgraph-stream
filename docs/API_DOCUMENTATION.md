# API Documentation - Website Scanner Backend

## Base URL

The backend API is hosted on AWS and the URL is injected into Vercel as an environment variable:

```javascript
const API_BASE_URL = process.env.NEXT_PUBLIC_BACKEND_URL;
// Example: https://roboad-backend-alb-xxxxx.us-east-2.elb.amazonaws.com
```

## Authentication

### Authenticated Requests

Include the Clerk JWT token in the `Authorization` header:

```javascript
const token = await getToken({ template: "supabase" });

const response = await fetch(`${API_BASE_URL}/api/scans`, {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  }
});
```

### Anonymous Requests

Include a session ID in the `X-Session-ID` header:

```javascript
const sessionId = getOrCreateSessionId(); // Generate once and persist

const response = await fetch(`${API_BASE_URL}/api/scans`, {
  headers: {
    'X-Session-ID': sessionId,
    'Content-Type': 'application/json'
  }
});
```

## Endpoints

### 1. Create Scan

Create a new website scan request.

**Endpoint**: `POST /api/scans`

**Headers**:
- `Authorization: Bearer <token>` (optional - for authenticated users)
- `X-Session-ID: <session_id>` (optional - for anonymous users)
- `Content-Type: application/json`

**Request Body**:
```json
{
  "url": "https://example.com"
}
```

**Response**: `201 Created`
```json
{
  "scan_id": "550e8400-e29b-41d4-a716-446655440000",
  "website_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "url": "https://example.com",
  "domain": "example.com",
  "status": "pending",
  "user_id": "user_2xxxxx",  // null for anonymous
  "session_id": "abc123",     // null for authenticated
  "created_at": "2025-10-23T15:30:00Z"
}
```

**Error Response**: `400 Bad Request`
```json
{
  "error": "Invalid URL",
  "message": "Please provide a valid URL"
}
```

**Example Usage**:
```javascript
async function createScan(url: string) {
  const token = await getToken({ template: "supabase" });

  const response = await fetch(`${API_BASE_URL}/api/scans`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ url })
  });

  if (!response.ok) {
    throw new Error('Failed to create scan');
  }

  return await response.json();
}
```

---

### 2. Get Scan Status

Retrieve the status and results of a scan.

**Endpoint**: `GET /api/scans/{scan_id}`

**Headers**:
- `Authorization: Bearer <token>` (optional)
- `X-Session-ID: <session_id>` (optional)

**Response**: `200 OK`
```json
{
  "scan_id": "550e8400-e29b-41d4-a716-446655440000",
  "website_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "url": "https://example.com",
  "domain": "example.com",
  "status": "completed",
  "scan_data": {
    "screenshot_url": "https://s3.amazonaws.com/bucket/scans/550e8400.../screenshot.png?presigned=...",
    "page_title": "Example Domain",
    "meta_description": "Example website description",
    "analysis": {
      "summary": "This is a simple example website...",
      "key_features": ["Clean design", "Simple layout"],
      "technologies_detected": ["HTML", "CSS"]
    }
  },
  "processing_time_ms": 3450,
  "created_at": "2025-10-23T15:30:00Z",
  "completed_at": "2025-10-23T15:30:03Z"
}
```

**Status Values**:
- `pending`: Scan has been created but not started
- `processing`: Scan is currently in progress
- `completed`: Scan finished successfully
- `failed`: Scan encountered an error

**Error Response**: `404 Not Found`
```json
{
  "error": "Not Found",
  "message": "Scan not found"
}
```

**Example Usage**:
```javascript
async function getScanStatus(scanId: string, sessionId?: string) {
  const headers: Record<string, string> = {};

  // IMPORTANT: Include session ID for anonymous users
  if (sessionId) {
    headers['X-Session-ID'] = sessionId;
  }

  const response = await fetch(`${API_BASE_URL}/api/scans/${scanId}`, {
    headers
  });

  if (!response.ok) {
    throw new Error('Failed to fetch scan status');
  }

  return await response.json();
}
```

**⚠️ Important for Anonymous Users**: The `X-Session-ID` header is **REQUIRED** for anonymous users to access scans they created. Without it, you'll get a `404 Not Found` response even if the scan exists.

---

### 3. List User Scans

Get all scans for the authenticated user.

**Endpoint**: `GET /api/scans`

**Headers**:
- `Authorization: Bearer <token>` (required)

**Query Parameters**:
- `limit` (optional): Number of results to return (default: 20, max: 100)
- `offset` (optional): Number of results to skip (default: 0)
- `status` (optional): Filter by status (pending, processing, completed, failed)

**Response**: `200 OK`
```json
{
  "scans": [
    {
      "scan_id": "550e8400-e29b-41d4-a716-446655440000",
      "website_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "url": "https://example.com",
      "domain": "example.com",
      "status": "completed",
      "created_at": "2025-10-23T15:30:00Z",
      "completed_at": "2025-10-23T15:30:03Z"
    }
  ],
  "total": 42,
  "limit": 20,
  "offset": 0
}
```

**Error Response**: `401 Unauthorized`
```json
{
  "error": "Unauthorized",
  "message": "Authentication required"
}
```

**Example Usage**:
```javascript
async function getUserScans(limit = 20, offset = 0) {
  const token = await getToken({ template: "supabase" });

  const response = await fetch(
    `${API_BASE_URL}/api/scans?limit=${limit}&offset=${offset}`,
    {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    }
  );

  if (!response.ok) {
    throw new Error('Failed to fetch scans');
  }

  return await response.json();
}
```

---

### 4. Claim Anonymous Scans

Link anonymous scans to an authenticated user account.

**Endpoint**: `POST /api/scans/claim`

**Headers**:
- `Authorization: Bearer <token>` (required)
- `Content-Type: application/json`

**Request Body**:
```json
{
  "session_id": "abc123"
}
```

**Response**: `200 OK`
```json
{
  "claimed_count": 3,
  "message": "Successfully claimed 3 scans"
}
```

**Error Response**: `401 Unauthorized`
```json
{
  "error": "Unauthorized",
  "message": "Authentication required"
}
```

**Example Usage**:
```javascript
async function claimAnonymousScans(sessionId: string) {
  const token = await getToken({ template: "supabase" });

  const response = await fetch(`${API_BASE_URL}/api/scans/claim`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ session_id: sessionId })
  });

  if (!response.ok) {
    throw new Error('Failed to claim scans');
  }

  return await response.json();
}
```

---

### 5. Get Scan Assets

Retrieve presigned URLs for scan assets (screenshots, HTML, etc.).

**Endpoint**: `GET /api/scans/{scan_id}/assets`

**Headers**:
- `Authorization: Bearer <token>` (optional)
- `X-Session-ID: <session_id>` (optional)

**Response**: `200 OK`
```json
{
  "scan_id": "550e8400-e29b-41d4-a716-446655440000",
  "assets": {
    "screenshot": {
      "url": "https://s3.amazonaws.com/bucket/scans/550e8400.../screenshot.png?presigned=...",
      "filename": "screenshot.png",
      "size_bytes": 245678,
      "expires_at": "2025-10-23T16:30:00Z"
    },
    "html": {
      "url": "https://s3.amazonaws.com/bucket/scans/550e8400.../page.html?presigned=...",
      "filename": "page.html",
      "size_bytes": 15678,
      "expires_at": "2025-10-23T16:30:00Z"
    },
    "raw_data": {
      "url": "https://s3.amazonaws.com/bucket/scans/550e8400.../raw_data.json?presigned=...",
      "filename": "raw_data.json",
      "size_bytes": 5432,
      "expires_at": "2025-10-23T16:30:00Z"
    }
  }
}
```

**Example Usage**:
```javascript
async function getScanAssets(scanId: string) {
  const response = await fetch(`${API_BASE_URL}/api/scans/${scanId}/assets`);

  if (!response.ok) {
    throw new Error('Failed to fetch scan assets');
  }

  return await response.json();
}
```

---

## WebSocket Connection (Existing)

For real-time scan progress updates (if needed):

**Endpoint**: `ws://{API_BASE_URL}/ws`

**Connection**:
```javascript
const ws = new WebSocket(`ws://${API_BASE_URL.replace('https://', '')}/ws`);

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Scan update:', data);
};
```

---

## Error Codes

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 201 | Created |
| 400 | Bad Request - Invalid input |
| 401 | Unauthorized - Missing or invalid token |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource doesn't exist |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error |

---

## Rate Limiting

- **Anonymous requests**: 10 requests per minute per IP
- **Authenticated requests**: 60 requests per minute per user

**Rate Limit Headers**:
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1635360000
```

---

## Complete Frontend Integration Example

### React/Next.js Hook

```typescript
// hooks/useScans.ts
import { useAuth } from '@clerk/nextjs';
import { useState, useEffect } from 'react';

const API_BASE_URL = process.env.NEXT_PUBLIC_BACKEND_URL;

interface Scan {
  scan_id: string;
  url: string;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  scan_data?: any;
  created_at: string;
  completed_at?: string;
}

export function useScans() {
  const { getToken, userId } = useAuth();
  const [scans, setScans] = useState<Scan[]>([]);
  const [loading, setLoading] = useState(false);

  // Create a new scan
  const createScan = async (url: string) => {
    setLoading(true);
    try {
      const headers: HeadersInit = {
        'Content-Type': 'application/json'
      };

      if (userId) {
        const token = await getToken({ template: 'supabase' });
        headers['Authorization'] = `Bearer ${token}`;
      } else {
        const sessionId = getOrCreateSessionId();
        headers['X-Session-ID'] = sessionId;
      }

      const response = await fetch(`${API_BASE_URL}/api/scans`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ url })
      });

      if (!response.ok) {
        throw new Error('Failed to create scan');
      }

      const scan = await response.json();
      setScans(prev => [scan, ...prev]);
      return scan;
    } finally {
      setLoading(false);
    }
  };

  // Fetch user's scans
  const fetchScans = async () => {
    if (!userId) return;

    setLoading(true);
    try {
      const token = await getToken({ template: 'supabase' });
      const response = await fetch(`${API_BASE_URL}/api/scans`, {
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      if (response.ok) {
        const data = await response.json();
        setScans(data.scans);
      }
    } finally {
      setLoading(false);
    }
  };

  // Claim anonymous scans on login
  const claimScans = async () => {
    if (!userId) return;

    const sessionId = localStorage.getItem('roboad_session_id');
    if (!sessionId) return;

    try {
      const token = await getToken({ template: 'supabase' });
      const response = await fetch(`${API_BASE_URL}/api/scans/claim`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ session_id: sessionId })
      });

      if (response.ok) {
        localStorage.removeItem('roboad_session_id');
        await fetchScans();
      }
    } catch (error) {
      console.error('Failed to claim scans:', error);
    }
  };

  // Get a specific scan by ID
  const getScan = async (scanId: string) => {
    const headers: HeadersInit = {
      'Content-Type': 'application/json'
    };

    if (userId) {
      const token = await getToken({ template: 'supabase' });
      headers['Authorization'] = `Bearer ${token}`;
    } else {
      const sessionId = getOrCreateSessionId();
      headers['X-Session-ID'] = sessionId;
    }

    const response = await fetch(`${API_BASE_URL}/api/scans/${scanId}`, {
      headers
    });

    if (!response.ok) {
      throw new Error('Failed to fetch scan');
    }

    return await response.json();
  };

  useEffect(() => {
    if (userId) {
      claimScans();
      fetchScans();
    }
  }, [userId]);

  return {
    scans,
    loading,
    createScan,
    getScan,
    fetchScans
  };
}

// Helper function
function getOrCreateSessionId(): string {
  const SESSION_KEY = 'roboad_session_id';
  let sessionId = localStorage.getItem(SESSION_KEY);

  if (!sessionId) {
    sessionId = crypto.randomUUID();
    localStorage.setItem(SESSION_KEY, sessionId);
  }

  return sessionId;
}
```

### Usage in Component

```typescript
// components/ScanForm.tsx
'use client';

import { useState } from 'react';
import { useScans } from '@/hooks/useScans';

export function ScanForm() {
  const [url, setUrl] = useState('');
  const { createScan, loading } = useScans();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      const scan = await createScan(url);
      console.log('Scan created:', scan);
      setUrl('');

      // Poll for status or use WebSocket
      pollScanStatus(scan.scan_id);
    } catch (error) {
      console.error('Failed to create scan:', error);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input
        type="url"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
        placeholder="https://example.com"
        required
      />
      <button type="submit" disabled={loading}>
        {loading ? 'Creating...' : 'Scan Website'}
      </button>
    </form>
  );
}
```

---

## Testing

### Test with cURL

**Anonymous Scan**:
```bash
curl -X POST https://your-alb-url.elb.amazonaws.com/api/scans \
  -H "X-Session-ID: test-session-123" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

**Authenticated Scan**:
```bash
curl -X POST https://your-alb-url.elb.amazonaws.com/api/scans \
  -H "Authorization: Bearer <your-clerk-token>" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

**Get Scan Status**:
```bash
curl https://your-alb-url.elb.amazonaws.com/api/scans/{scan_id}
```

---

## Support

For issues or questions, contact the backend team or check:
- **Auth Strategy**: `docs/AUTH_STRATEGY.md`
- **Infrastructure**: `infra/README.md`