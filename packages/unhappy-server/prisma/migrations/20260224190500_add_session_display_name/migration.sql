-- Add optional user-facing display name for sessions.
ALTER TABLE "Session"
ADD COLUMN "displayName" TEXT;
