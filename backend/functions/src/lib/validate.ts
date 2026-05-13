/**
 * Input validation helpers.
 *
 * Triết lý: fail-fast với HttpsError 'invalid-argument'. Không bao giờ để
 * input xấu xâm nhập business logic.
 */
import { HttpsError } from 'firebase-functions/v2/https';
import { Polyline } from './geo';

export function requireString(
  value: unknown,
  fieldName: string,
  opts: { minLen?: number; maxLen?: number } = {}
): string {
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', `${fieldName} phải là string`);
  }
  if (opts.minLen !== undefined && value.length < opts.minLen) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} phải có ít nhất ${opts.minLen} ký tự`
    );
  }
  if (opts.maxLen !== undefined && value.length > opts.maxLen) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} không được dài quá ${opts.maxLen} ký tự`
    );
  }
  return value;
}

export function requireNumber(
  value: unknown,
  fieldName: string,
  opts: { min?: number; max?: number } = {}
): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new HttpsError('invalid-argument', `${fieldName} phải là số hợp lệ`);
  }
  if (opts.min !== undefined && value < opts.min) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} phải >= ${opts.min}`
    );
  }
  if (opts.max !== undefined && value > opts.max) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} phải <= ${opts.max}`
    );
  }
  return value;
}

export interface LatLng {
  lat: number;
  lng: number;
}

export function requireLatLng(data: { lat?: unknown; lng?: unknown }): LatLng {
  return {
    lat: requireNumber(data.lat, 'lat', { min: -90, max: 90 }),
    lng: requireNumber(data.lng, 'lng', { min: -180, max: 180 }),
  };
}

/**
 * Validate roomCode dạng RouteMate (6 ký tự, in hoa + số, không có I/O/0/1).
 */
export function requireRoomId(value: unknown): string {
  const s = requireString(value, 'roomId', { minLen: 6, maxLen: 6 });
  if (!/^[A-HJ-NP-Z2-9]{6}$/.test(s)) {
    throw new HttpsError(
      'invalid-argument',
      'roomId phải là 6 ký tự (chữ in hoa, số, không có I/O/0/1)'
    );
  }
  return s;
}

/**
 * Validate polyline: array của {lat, lng}, ít nhất 2 điểm, tối đa 5000 điểm.
 *
 * Limit 5000 điểm = ~1500km route ở mật độ Google Directions trung bình.
 * Quá đủ cho route Việt Nam (Hà Nội → Sài Gòn ~ 1700km nhưng polyline
 * Google thường < 3000 điểm).
 */
export function requirePolyline(value: unknown): Polyline {
  if (!Array.isArray(value)) {
    throw new HttpsError('invalid-argument', 'polyline phải là array');
  }
  if (value.length < 2) {
    throw new HttpsError(
      'invalid-argument',
      'polyline phải có ít nhất 2 điểm'
    );
  }
  if (value.length > 5000) {
    throw new HttpsError(
      'invalid-argument',
      'polyline không được vượt quá 5000 điểm'
    );
  }
  return value.map((p, i) => {
    if (typeof p !== 'object' || p === null) {
      throw new HttpsError(
        'invalid-argument',
        `polyline[${i}] phải là object {lat, lng}`
      );
    }
    return {
      lat: requireNumber((p as { lat?: unknown }).lat, `polyline[${i}].lat`, {
        min: -90,
        max: 90,
      }),
      lng: requireNumber((p as { lng?: unknown }).lng, `polyline[${i}].lng`, {
        min: -180,
        max: 180,
      }),
    };
  });
}
