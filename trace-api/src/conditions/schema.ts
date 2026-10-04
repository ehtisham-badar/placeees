import { z } from 'zod';

const hhmm = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const ymd = z.iso.date();

function isTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}
const timeZone = z.string().refine(isTimeZone, 'invalid time zone');

export const SunPhase = z.enum(['sunrise', 'sunset', 'goldenHour', 'night']);
export const WeatherKind = z.enum(['rain', 'clear', 'cloudy', 'fog', 'snow']);
export type SunPhase = z.infer<typeof SunPhase>;
export type WeatherKind = z.infer<typeof WeatherKind>;

export const Condition = z.discriminatedUnion('type', [
  z.object({ type: z.literal('sun'), phase: SunPhase, windowMinutes: z.number().int().min(10).max(180).default(45) }),
  z.object({ type: z.literal('weather'), is: WeatherKind }),
  z.object({ type: z.literal('timeRange'), from: hhmm, to: hhmm, tz: timeZone }),
  z.object({ type: z.literal('dateRange'), from: ymd, to: ymd, tz: timeZone }).refine((c) => c.from <= c.to, {
    message: 'from must not be after to',
  }),
]);
export type Condition = z.infer<typeof Condition>;

/** Every condition must hold at unlock time (spec F-08). */
export const Conditions = z.object({ all: z.array(Condition).min(1).max(4) });
export type Conditions = z.infer<typeof Conditions>;

/** What the map may show for an unrevealed rule: just the kinds, as icons. */
export function conditionKinds(c: Conditions): string[] {
  return [...new Set(c.all.map((x) => (x.type === 'sun' && x.phase === 'night' ? 'night' : x.type)))];
}
