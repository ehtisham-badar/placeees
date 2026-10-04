import { getTimes } from 'suncalc';
import { describe, expect, it } from 'vitest';
import { conditionsMet, inTimeRange } from '../src/conditions/evaluate.js';
import { Conditions, conditionKinds } from '../src/conditions/schema.js';
import { inSunPhase } from '../src/conditions/sun.js';
import { weatherKindFromCode } from '../src/conditions/weather.js';

const LAHORE = { lat: 31.5204, lng: 74.3587 };
const TZ = 'Asia/Karachi'; // UTC+5, no DST

const ctx = (iso: string, weather: string | null = 'clear') => ({
  now: new Date(iso),
  ...LAHORE,
  weather: async () => weather as never,
});

describe('schema', () => {
  it('accepts the spec example', () => {
    const parsed = Conditions.parse({
      all: [
        { type: 'sun', phase: 'sunset', windowMinutes: 45 },
        { type: 'weather', is: 'rain' },
        { type: 'timeRange', from: '20:00', to: '04:00', tz: TZ },
        { type: 'dateRange', from: '2026-12-01', to: '2026-12-31', tz: TZ },
      ],
    });
    expect(conditionKinds(parsed)).toEqual(['sun', 'weather', 'timeRange', 'dateRange']);
  });

  it('rejects bad input', () => {
    expect(() => Conditions.parse({ all: [] })).toThrow();
    expect(() => Conditions.parse({ all: [{ type: 'timeRange', from: '25:00', to: '04:00', tz: TZ }] })).toThrow();
    expect(() => Conditions.parse({ all: [{ type: 'timeRange', from: '20:00', to: '04:00', tz: 'Mars/Base' }] })).toThrow();
    expect(() =>
      Conditions.parse({ all: [{ type: 'dateRange', from: '2026-12-31', to: '2026-12-01', tz: TZ }] }),
    ).toThrow();
  });

  it('reports night as its own kind', () => {
    expect(conditionKinds(Conditions.parse({ all: [{ type: 'sun', phase: 'night' }] }))).toEqual(['night']);
  });
});

describe('timeRange', () => {
  it('handles same-day and overnight windows', () => {
    expect(inTimeRange('10:30', '09:00', '17:00')).toBe(true);
    expect(inTimeRange('17:00', '09:00', '17:00')).toBe(false);
    expect(inTimeRange('23:15', '20:00', '04:00')).toBe(true);
    expect(inTimeRange('03:59', '20:00', '04:00')).toBe(true);
    expect(inTimeRange('12:00', '20:00', '04:00')).toBe(false);
  });

  it('evaluates in the drop time zone', async () => {
    const c = Conditions.parse({ all: [{ type: 'timeRange', from: '20:00', to: '04:00', tz: TZ }] });
    expect(await conditionsMet(c, ctx('2026-10-04T16:00:00Z'))).toBe(true); // 21:00 in Lahore
    expect(await conditionsMet(c, ctx('2026-10-04T10:00:00Z'))).toBe(false); // 15:00 in Lahore
  });
});

describe('dateRange', () => {
  it('is inclusive and uses the local date', async () => {
    const c = Conditions.parse({ all: [{ type: 'dateRange', from: '2026-12-01', to: '2026-12-31', tz: TZ }] });
    expect(await conditionsMet(c, ctx('2026-11-30T20:00:00Z'))).toBe(true); // already Dec 1 in Lahore
    expect(await conditionsMet(c, ctx('2026-12-31T19:01:00Z'))).toBe(false); // 00:01 Jan 1 in Lahore
    expect(await conditionsMet(c, ctx('2026-12-31T18:59:00Z'))).toBe(true); // 23:59 Dec 31
  });
});

describe('sun', () => {
  const day = getTimes(new Date('2026-10-04T07:00:00Z'), LAHORE.lat, LAHORE.lng);
  const at = (d: Date | null, deltaMin: number) => new Date(d!.getTime() + deltaMin * 60_000);

  it('matches around sunset and sunrise', () => {
    expect(inSunPhase('sunset', at(day.sunset, 20), LAHORE.lat, LAHORE.lng, 45)).toBe(true);
    expect(inSunPhase('sunset', at(day.sunset, -90), LAHORE.lat, LAHORE.lng, 45)).toBe(false);
    expect(inSunPhase('sunrise', at(day.sunrise, -10), LAHORE.lat, LAHORE.lng, 45)).toBe(true);
  });

  it('matches golden hour and night', () => {
    expect(inSunPhase('goldenHour', at(day.sunset, -15), LAHORE.lat, LAHORE.lng, 45)).toBe(true);
    expect(inSunPhase('goldenHour', at(day.solarNoon, 0), LAHORE.lat, LAHORE.lng, 45)).toBe(false);
    expect(inSunPhase('night', at(day.dusk, 120), LAHORE.lat, LAHORE.lng, 45)).toBe(true);
    expect(inSunPhase('night', at(day.solarNoon, 0), LAHORE.lat, LAHORE.lng, 45)).toBe(false);
  });

  it('never matches sunset during polar night', () => {
    expect(inSunPhase('sunset', new Date('2026-12-21T12:00:00Z'), 85, 0, 180)).toBe(false);
  });
});

describe('weather', () => {
  it('maps WMO codes', () => {
    expect(weatherKindFromCode(0)).toBe('clear');
    expect(weatherKindFromCode(3)).toBe('cloudy');
    expect(weatherKindFromCode(45)).toBe('fog');
    expect(weatherKindFromCode(63)).toBe('rain');
    expect(weatherKindFromCode(95)).toBe('rain');
    expect(weatherKindFromCode(73)).toBe('snow');
  });

  it('only fetches weather when the cheap checks pass', async () => {
    let fetched = 0;
    const c = Conditions.parse({
      all: [
        { type: 'weather', is: 'rain' },
        { type: 'timeRange', from: '20:00', to: '04:00', tz: TZ },
      ],
    });
    const weather = async () => {
      fetched++;
      return 'rain' as const;
    };
    expect(await conditionsMet(c, { ...ctx('2026-10-04T10:00:00Z'), weather })).toBe(false);
    expect(fetched).toBe(0);
    expect(await conditionsMet(c, { ...ctx('2026-10-04T16:00:00Z'), weather })).toBe(true);
    expect(fetched).toBe(1);
  });

  it('unknown weather never satisfies a weather condition', async () => {
    const c = Conditions.parse({ all: [{ type: 'weather', is: 'clear' }] });
    expect(await conditionsMet(c, ctx('2026-10-04T10:00:00Z', null))).toBe(false);
  });
});
