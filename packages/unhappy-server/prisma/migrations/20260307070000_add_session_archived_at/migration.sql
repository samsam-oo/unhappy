-- Add soft-archive support for sessions.
ALTER TABLE "Session"
ADD COLUMN "archivedAt" TIMESTAMP(3);
