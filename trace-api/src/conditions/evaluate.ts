import type { Condition, Conditions, WeatherKind } from './schema.js';
import { inSunPhase } from './sun.js';

export interface ConditionContext {
  now: Date;
  lat: number;
  lng: number;
  /** Fetched lazily, only if a weather condition is present. */
  weather: () => Promise<WeatherKind | null>;
}

function localParts(now: Date, tz: string) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return { date: `${get('year')}-${get('month')}-${get('day')}`, time: `${get('hour')}:${get('minute')}` };
}

/** `from` inclusive, `to` exclusive; ranges where from > to wrap past midnight. */
export function inTimeRange(time: string, from: string, to: string): boolean {
  return from <= to ? time >= from && time < to : time >= from || time < to;
}

async function holds(c: Condition, ctx: ConditionContext): Promise<boolean> {
  switch (c.type) {
    case 'sun':
      return inSunPhase(c.phase, ctx.now, ctx.lat, ctx.lng, c.windowMinutes);
    case 'weather':
      return (await ctx.weather()) === c.is;
    case 'timeRange':
      return inTimeRange(localParts(ctx.now, c.tz).time, c.from, c.to);
    case 'dateRange': {
      const today = localParts(ctx.now, c.tz).date;
      return today >= c.from && today <= c.to;
    }
  }
}

export async function conditionsMet(conditions: Conditions, ctx: ConditionContext): Promise<boolean> {
  // Cheap, local checks first so the weather API is only hit when it could matter.
  const ordered = [...conditions.all].sort((a, b) => Number(a.type === 'weather') - Number(b.type === 'weather'));
  for (const c of ordered) if (!(await holds(c, ctx))) return false;
  return true;
}
