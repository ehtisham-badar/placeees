import { notifyOpenedCapsules } from './capsules.js';
import { returnOverdueRelays, warnRelayDeadlines } from './relays.js';

/** Minute-tick background work. Each job claims rows atomically, so extra replicas are safe. */
export function startJobs(log: { error: (o: unknown, m: string) => void }, everyMs = 60_000) {
  const jobs = { notifyOpenedCapsules, returnOverdueRelays, warnRelayDeadlines };
  const tick = () => {
    for (const [name, job] of Object.entries(jobs)) job().catch((err) => log.error(err, `${name} failed`));
  };
  const timer = setInterval(tick, everyMs);
  timer.unref();
  return () => clearInterval(timer);
}
