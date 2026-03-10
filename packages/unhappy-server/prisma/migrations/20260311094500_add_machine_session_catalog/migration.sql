-- CreateTable
CREATE TABLE "MachineProjectCatalogEntry" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "machineId" TEXT NOT NULL,
    "projectPath" TEXT NOT NULL,
    "displayPath" TEXT,
    "openedExplicitly" BOOLEAN NOT NULL DEFAULT true,
    "latestUpdatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastObservedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MachineProjectCatalogEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MachineSessionCatalogEntry" (
    "id" TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "machineId" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "projectPath" TEXT NOT NULL,
    "providerSessionId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "preview" TEXT,
    "cwd" TEXT,
    "transcriptPath" TEXT,
    "model" TEXT,
    "archived" BOOLEAN NOT NULL DEFAULT false,
    "providerCreatedAt" TIMESTAMP(3),
    "providerUpdatedAt" TIMESTAMP(3) NOT NULL,
    "lastObservedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MachineSessionCatalogEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "MachineProjectCatalogEntry_accountId_machineId_projectPath_key" ON "MachineProjectCatalogEntry"("accountId", "machineId", "projectPath");

-- CreateIndex
CREATE INDEX "MachineProjectCatalogEntry_accountId_latestUpdatedAt_idx" ON "MachineProjectCatalogEntry"("accountId", "latestUpdatedAt" DESC);

-- CreateIndex
CREATE INDEX "MachineProjectCatalogEntry_accountId_machineId_latestUpdatedAt_idx" ON "MachineProjectCatalogEntry"("accountId", "machineId", "latestUpdatedAt" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "MachineSessionCatalogEntry_accountId_machineId_provider_projectPa_key" ON "MachineSessionCatalogEntry"("accountId", "machineId", "provider", "projectPath", "providerSessionId");

-- CreateIndex
CREATE INDEX "MachineSessionCatalogEntry_accountId_machineId_projectPath_provider_idx" ON "MachineSessionCatalogEntry"("accountId", "machineId", "projectPath", "providerUpdatedAt" DESC);

-- CreateIndex
CREATE INDEX "MachineSessionCatalogEntry_accountId_providerUpdatedAt_idx" ON "MachineSessionCatalogEntry"("accountId", "providerUpdatedAt" DESC);

-- AddForeignKey
ALTER TABLE "MachineProjectCatalogEntry" ADD CONSTRAINT "MachineProjectCatalogEntry_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "Account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MachineProjectCatalogEntry" ADD CONSTRAINT "MachineProjectCatalogEntry_accountId_machineId_fkey" FOREIGN KEY ("accountId", "machineId") REFERENCES "Machine"("accountId", "id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MachineSessionCatalogEntry" ADD CONSTRAINT "MachineSessionCatalogEntry_accountId_fkey" FOREIGN KEY ("accountId") REFERENCES "Account"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MachineSessionCatalogEntry" ADD CONSTRAINT "MachineSessionCatalogEntry_accountId_machineId_fkey" FOREIGN KEY ("accountId", "machineId") REFERENCES "Machine"("accountId", "id") ON DELETE CASCADE ON UPDATE CASCADE;
