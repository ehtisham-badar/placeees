import { geohash } from '../lib/geo.js';
import type { WeatherKind } from './schema.js';

const TTL_MS = 10 * 60_000;
const cache = new Map<string, { kind: WeatherKind | null; at: number }>();

/** Maps a WMO weather code (Open-Meteo `weather_code`) to the kinds a drop can wait for. */
export function weatherKindFromCode(code: number): WeatherKind | null {
  if (code <= 1) return 'clear';
  if (code <= 3) return 'cloudy';
  if (code === 45 || code === 48) return 'fog';
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95) return 'rain';
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return 'snow';
  return null;
}

/** Current weather near a point, cached per geohash-5 cell (~5 km) for 10 minutes. */
export async function currentWeather(lat: number, lng: number): Promise<WeatherKind | null> {
  const cell = geohash({ lat, lng }, 5);
  const hit = cache.get(cell);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.kind;

  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(3)}&longitude=${lng.toFixed(3)}&current=weather_code`;
    const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (!res.ok) throw new Error(`open-meteo ${res.status}`);
    const body = (await res.json()) as { current?: { weather_code?: number } };
    const code = body.current?.weather_code;
    const kind = typeof code === 'number' ? weatherKindFromCode(code) : null;
    cache.set(cell, { kind, at: Date.now() });
    return kind;
  } catch {
    return null; // unknown weather never satisfies a weather condition
  }
}
