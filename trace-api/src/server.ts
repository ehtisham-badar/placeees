import { buildApp } from './app.js';
import { config } from './config.js';
import { startCapsuleJob } from './jobs/capsules.js';

const app = buildApp();
if (config.RUN_JOBS) startCapsuleJob(app.log);
app.listen({ port: config.PORT, host: '0.0.0.0' }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
