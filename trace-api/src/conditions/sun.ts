import { getTimes, type SunTimes } from 'suncalc';
import type { SunPhase } from './schema.js';

/** Epoch ms, or null when the event doesn't happen that day (polar day/night). */
const ms = (d: Date | null): number | null => (d && !Number.isNaN(d.getTime()) ? d.getTime() : null);

const within = (t: number, from: number | null, to: number | null) => from != null && to != null && t >= from && t <= to;

/** Whether `now` falls in the given sun phase at this place. */
export function inSunPhase(phase: SunPhase, now: Date, lat: number, lng: number, windowMinutes: number): boolean {
  const t = now.getTime();
  const w = windowMinutes * 60_000;
  // Yesterday, today and tomorrow, so phases near midnight UTC are not missed.
  const days: SunTimes[] = [-1, 0, 1].map((d) => getTimes(new Date(t + d * 86_400_000), lat, lng));

  switch (phase) {
    case 'sunrise':
      return days.some((s) => {
        const at = ms(s.sunrise);
        return at != null && Math.abs(t - at) <= w;
      });
    case 'sunset':
      return days.some((s) => {
        const at = ms(s.sunset);
        return at != null && Math.abs(t - at) <= w;
      });
    case 'goldenHour':
      return days.some(
        (s) => within(t, ms(s.sunrise), ms(s.goldenHourEnd)) || within(t, ms(s.goldenHour), ms(s.sunset)),
      );
    case 'night':
      // Between civil dusk and the next civil dawn.
      return days.slice(0, -1).some((s, i) => {
        const dusk = ms(s.dusk);
        const dawn = ms(days[i + 1]!.dawn);
        return dusk != null && dawn != null && t >= dusk && t < dawn;
      });
  }
}
