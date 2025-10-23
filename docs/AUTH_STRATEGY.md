# Authentication Strategy: Clerk + Supabase Integration

## Overview

Our application uses **Clerk** for frontend authentication and **Supabase** for backend database operations. Clerk is configured to sync user data with Supabase, creating a seamless auth flow.

## Architecture

```
┌─────────────────┐
│  Vercel Frontend│
│   (Clerk Auth)  │
└────────┬────────┘
         │
         │ HTTP Request + Authorization Header
         │
         ▼
┌─────────────────┐
│   AWS ALB       │
│  (Load Balancer)│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   FastAPI       │
│   Backend       │
│ (Token Verify)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Supabase DB   │
│  (auth.users)   │
└─────────────────┘
```

## Authentication Flow

### 1. User Login Flow (Frontend)

```javascript
// User logs in via Clerk
const { userId } = useAuth(); // Clerk hook

// Get session token
const token = await getToken({ template: "supabase" });

// Send request to backend
fetch(`${BACKEND_URL}/api/scans`, {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  // ... rest of request
});
```

### 2. Token Verification Flow (Backend)

```
1. Frontend sends request with Authorization header
2. Backend extracts Bearer token
3. Backend verifies Clerk JWT token
4. Extract user_id from token claims
5. Use user_id for database operations
```

### 3. Anonymous User Flow

For users who haven't logged in:

```
1. Frontend generates a unique session_id (stored in localStorage/cookie)
2. Send requests without Authorization header, but with X-Session-ID header
3. Backend creates scans with user_id=NULL, session_id=<value>
4. When user logs in, frontend calls /api/scans/claim with session_id
5. Backend links all anonymous scans to the authenticated user
```

## Implementation Details

### Frontend Requirements

**Authenticated Requests**:
```javascript
const token = await getToken({ template: "supabase" });

const headers = {
  'Authorization': `Bearer ${token}`,
  'Content-Type': 'application/json'
};
```

**Anonymous Requests**:
```javascript
// Generate session_id once and persist
const sessionId = localStorage.getItem('sessionId') || crypto.randomUUID();
localStorage.setItem('sessionId', sessionId);

const headers = {
  'X-Session-ID': sessionId,
  'Content-Type': 'application/json'
};
```

### Backend Implementation

**Token Verification**:
```python
from clerk_backend_api import Clerk

clerk = Clerk(bearer_auth=CLERK_SECRET_KEY)

def verify_clerk_token(token: str) -> Optional[str]:
    """Verify Clerk token and return user_id"""
    try:
        # Verify the JWT token
        session = clerk.sessions.verify_token(token)
        return session.user_id
    except Exception as e:
        return None
```

**Request Handler**:
```python
def get_user_id_from_request(request: Request) -> Optional[str]:
    """Extract user_id from Authorization header"""
    auth_header = request.headers.get('Authorization')

    if not auth_header or not auth_header.startswith('Bearer '):
        return None

    token = auth_header.replace('Bearer ', '')
    return verify_clerk_token(token)
```

## Clerk + Supabase Sync

When Clerk is linked to Supabase:
- Clerk automatically syncs users to `auth.users` table
- The `user_id` from Clerk matches the `id` in Supabase's `auth.users`
- No additional mapping needed

## Security Considerations

1. **Token Verification**: Always verify Clerk tokens on backend
2. **Service Role Key**: Use Supabase service role key on backend (bypasses RLS)
3. **RLS Policies**: Keep RLS enabled for direct client access (if needed)
4. **CORS**: Configure ALB/FastAPI to accept requests from Vercel domain only
5. **Rate Limiting**: Implement rate limiting for anonymous requests

## Environment Variables

### Backend (.env)
```bash
# Clerk
CLERK_SECRET_KEY=sk_live_...
CLERK_PUBLISHABLE_KEY=pk_live_...

# Supabase
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # Use service role, not anon key

# AWS S3
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
S3_BUCKET_NAME=...
```

### Frontend (.env)
```bash
# Provided by Vercel integration
NEXT_PUBLIC_BACKEND_URL=https://your-alb-url.elb.amazonaws.com

# Clerk (already configured)
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_...
```

## Workflow Examples

### Example 1: Anonymous Scan → Login → Claim

```javascript
// 1. Anonymous user creates scan
const sessionId = getOrCreateSessionId();
const scan = await fetch(`${API_URL}/api/scans`, {
  method: 'POST',
  headers: {
    'X-Session-ID': sessionId,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ url: 'https://example.com' })
});

// 2. User logs in
const { userId } = await signIn();
const token = await getToken({ template: "supabase" });

// 3. Claim previous scans
await fetch(`${API_URL}/api/scans/claim`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ session_id: sessionId })
});
```

### Example 2: Authenticated Scan

```javascript
const { userId } = useAuth();
const token = await getToken({ template: "supabase" });

const scan = await fetch(`${API_URL}/api/scans`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ url: 'https://example.com' })
});
```

## Error Handling

**401 Unauthorized**: Token is invalid or expired
```json
{
  "error": "Unauthorized",
  "message": "Invalid or expired token"
}
```

**403 Forbidden**: User doesn't have permission
```json
{
  "error": "Forbidden",
  "message": "You don't have permission to access this resource"
}
```

## Session Management

### Frontend Session ID Generation
```javascript
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

### Clear Session on Login
```javascript
// After successful login and claim
async function onLoginSuccess() {
  const sessionId = localStorage.getItem('roboad_session_id');

  if (sessionId) {
    // Claim anonymous scans
    await claimScans(sessionId);

    // Clear session ID
    localStorage.removeItem('roboad_session_id');
  }
}
```

## Testing

### Test Anonymous Request
```bash
curl -X POST https://your-alb-url/api/scans \
  -H "X-Session-ID: test-session-123" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

### Test Authenticated Request
```bash
curl -X POST https://your-alb-url/api/scans \
  -H "Authorization: Bearer <clerk-token>" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```