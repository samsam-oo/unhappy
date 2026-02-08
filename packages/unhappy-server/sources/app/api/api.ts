import { log, logger } from '@/utils/log';
import { onShutdown } from '@/utils/shutdown';
import fastify from 'fastify';
import {
  serializerCompiler,
  validatorCompiler,
  ZodTypeProvider,
} from 'fastify-type-provider-zod';
import { accessKeysRoutes } from './routes/accessKeysRoutes';
import { accountRoutes } from './routes/accountRoutes';
import { artifactsRoutes } from './routes/artifactsRoutes';
import { authRoutes } from './routes/authRoutes';
import { connectRoutes } from './routes/connectRoutes';
import { devRoutes } from './routes/devRoutes';
import { feedRoutes } from './routes/feedRoutes';
import { kvRoutes } from './routes/kvRoutes';
import { machinesRoutes } from './routes/machinesRoutes';
import { pushRoutes } from './routes/pushRoutes';
import { sessionRoutes } from './routes/sessionRoutes';
import { userRoutes } from './routes/userRoutes';
import { versionRoutes } from './routes/versionRoutes';
import { voiceRoutes } from './routes/voiceRoutes';
import { startSocket } from './socket';
import { Fastify } from './types';
import { enableAuthentication } from './utils/enableAuthentication';
import { enableErrorHandlers } from './utils/enableErrorHandlers';
import { enableMonitoring } from './utils/enableMonitoring';

export async function startApi() {
  // Configure
  log('Starting API...');

  // Start API
  const app = fastify({
    loggerInstance: logger,
    bodyLimit: 1024 * 1024 * 100, // 100MB
  });
  app.register(import('@fastify/cors'), {
    origin: '*',
    allowedHeaders: '*',
    methods: ['GET', 'POST', 'DELETE'],
  });
  app.get('/', function (request, reply) {
    reply.send('Welcome to Unhappy Server!');
  });

  // Create typed provider
  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);
  const typed = app.withTypeProvider<ZodTypeProvider>() as unknown as Fastify;

  // Enable features
  enableMonitoring(typed);
  enableErrorHandlers(typed);
  enableAuthentication(typed);

  // Routes
  authRoutes(typed);
  pushRoutes(typed);
  sessionRoutes(typed);
  accountRoutes(typed);
  connectRoutes(typed);
  machinesRoutes(typed);
  artifactsRoutes(typed);
  accessKeysRoutes(typed);
  devRoutes(typed);
  versionRoutes(typed);
  voiceRoutes(typed);
  userRoutes(typed);
  feedRoutes(typed);
  kvRoutes(typed);

  // Start HTTP
  const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 3005;
  await app.listen({ port, host: '0.0.0.0' });
  onShutdown('api', async () => {
    await app.close();
  });

  // Start Socket
  startSocket(typed);

  // End
  log('API ready on port http://localhost:' + port);
}
