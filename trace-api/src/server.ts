import { buildApp } from './app.js';
import { config } from './config.js';
import { startJobs } from './jobs/index.js';

const app = buildApp();
if (config.RUN_JOBS) startJobs(app.log);
app.listen({ port: config.PORT, host: '0.0.0.0' }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
