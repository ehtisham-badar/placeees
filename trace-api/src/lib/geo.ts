const EARTH_RADIUS_M = 6_371_008.8;
const rad = (d: number) => (d * Math.PI) / 180;
const deg = (r: number) => (r * 180) / Math.PI;

export interface LatLng {
  lat: number;
  lng: number;
}

/** Great-circle distance in meters. */
export function distanceM(a: LatLng, b: LatLng): number {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Point reached by travelling `distance` meters from `from` on `bearingDeg`. */
export function destination(from: LatLng, bearingDeg: number, distance: number): LatLng {
  const δ = distance / EARTH_RADIUS_M;
  const θ = rad(bearingDeg);
  const φ1 = rad(from.lat);
  const λ1 = rad(from.lng);
  const φ2 = Math.asin(Math.sin(φ1) * Math.cos(δ) + Math.cos(φ1) * Math.sin(δ) * Math.cos(θ));
  const λ2 =
    λ1 + Math.atan2(Math.sin(θ) * Math.sin(δ) * Math.cos(φ1), Math.cos(δ) - Math.sin(φ1) * Math.sin(φ2));
  return { lat: deg(φ2), lng: ((deg(λ2) + 540) % 360) - 180 };
}

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export function geohash({ lat, lng }: LatLng, precision = 7): string {
  let latR = [-90, 90];
  let lngR = [-180, 180];
  let out = '';
  let bit = 0;
  let ch = 0;
  let even = true;
  while (out.length < precision) {
    const range = even ? lngR : latR;
    const val = even ? lng : lat;
    const mid = (range[0]! + range[1]!) / 2;
    if (val >= mid) {
      ch = (ch << 1) | 1;
      range[0] = mid;
    } else {
      ch <<= 1;
      range[1] = mid;
    }
    even = !even;
    if (++bit === 5) {
      out += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return out;
}
