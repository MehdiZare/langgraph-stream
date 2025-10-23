-- Create websites table
CREATE TABLE websites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url TEXT UNIQUE NOT NULL,
  domain TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_scanned_at TIMESTAMP WITH TIME ZONE,

  -- Metadata about the website
  metadata JSONB DEFAULT '{}'::JSONB
);

-- Indexes for faster lookups on websites
CREATE INDEX idx_websites_url ON websites(url);
CREATE INDEX idx_websites_domain ON websites(domain);
CREATE INDEX idx_websites_last_scanned ON websites(last_scanned_at DESC);

-- Create scans table
CREATE TABLE scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- User ID is nullable to support anonymous scans
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  website_id UUID NOT NULL REFERENCES websites(id) ON DELETE CASCADE,

  -- Track anonymous sessions for later claiming
  session_id TEXT,

  -- Status of the scan
  status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed

  -- All scan results in JSONB for flexibility
  -- S3 files are stored at: scans/{scan_id}/screenshot.png, scans/{scan_id}/page.html, etc.
  -- Store filenames and metadata in scan_data if needed
  scan_data JSONB DEFAULT '{}'::JSONB,

  -- Error information if scan failed
  error_message TEXT,

  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,

  -- Useful for analytics
  processing_time_ms INTEGER
);

-- Indexes for common queries on scans
CREATE INDEX idx_scans_user_id ON scans(user_id);
CREATE INDEX idx_scans_session_id ON scans(session_id);
CREATE INDEX idx_scans_website_id ON scans(website_id);
CREATE INDEX idx_scans_status ON scans(status);
CREATE INDEX idx_scans_created_at ON scans(created_at DESC);
CREATE INDEX idx_scans_user_created ON scans(user_id, created_at DESC);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tables
CREATE TRIGGER update_websites_updated_at BEFORE UPDATE ON websites
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_scans_updated_at BEFORE UPDATE ON scans
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to claim scans by session_id when user logs in
CREATE OR REPLACE FUNCTION claim_anonymous_scans(
  p_session_id TEXT,
  p_user_id UUID
)
RETURNS INTEGER AS $$
DECLARE
  claimed_count INTEGER;
BEGIN
  UPDATE scans
  SET user_id = p_user_id,
      updated_at = NOW()
  WHERE session_id = p_session_id
    AND user_id IS NULL;

  GET DIAGNOSTICS claimed_count = ROW_COUNT;
  RETURN claimed_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enable Row Level Security
ALTER TABLE websites ENABLE ROW LEVEL SECURITY;
ALTER TABLE scans ENABLE ROW LEVEL SECURITY;

-- RLS Policies for websites
CREATE POLICY "Anyone can view websites"
  ON websites FOR SELECT
  USING (true);

CREATE POLICY "Anyone can insert websites"
  ON websites FOR INSERT
  WITH CHECK (true);

-- RLS Policies for scans
CREATE POLICY "Anyone can view scans"
  ON scans FOR SELECT
  USING (true);

CREATE POLICY "Anyone can insert scans"
  ON scans FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Users can update own scans"
  ON scans FOR UPDATE
  USING (auth.uid() = user_id);

-- Grant execute permission on claim function to authenticated users
GRANT EXECUTE ON FUNCTION claim_anonymous_scans(TEXT, UUID) TO authenticated;