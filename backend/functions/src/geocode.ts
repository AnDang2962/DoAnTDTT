/**
 * geocodePlace — Cloud Function proxy gọi Mapbox Geocoding API.
 *
 * Mục đích: Giấu Mapbox token ở backend, không expose client-side.
 *
 * Hỗ trợ 2 use case:
 *   - Voice search (limit=1, autocomplete=false): "Đà Lạt" → 1 kết quả chính xác
 *   - Type-ahead (limit=5, autocomplete=true): "Đà L" → 5 gợi ý
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { requireAuth } from './lib/auth';
import { requireString } from './lib/validate';
import { enforceRateLimit } from './lib/rateLimit';
import { makeLogger } from './lib/logger';
import { retry } from './lib/retry';

const MAPBOX_PUBLIC_KEY = defineSecret('MAPBOX_PUBLIC_KEY');

interface GeocodePlace {
  name: string;       // "Đà Lạt"
  fullName: string;   // "Đà Lạt, Lâm Đồng, Việt Nam"
  lat: number;
  lng: number;
  type: string;       // 'place', 'locality', 'region', 'poi', ...
}

interface GeocodeResult {
  places: GeocodePlace[];
}

export const geocodePlace = onCall<
  {
    query: string;
    limit?: number;       // 1 cho voice, 5 cho autocomplete
    autocomplete?: boolean; // true cho type-ahead
    country?: string;
  },
  Promise<GeocodeResult>
>(
  {
    region: 'asia-southeast1',
    secrets: [MAPBOX_PUBLIC_KEY],
    timeoutSeconds: 15,
    memory: '256MiB',
  },
  async (request) => {
    const log = makeLogger('geocodePlace');
    const startMs = Date.now();
    const auth = requireAuth(request);

    const query = requireString(request.data?.query, 'query', {
      minLen: 1,
      maxLen: 200,
    });

    const limit = Math.min(
      Math.max(
        typeof request.data?.limit === 'number' ? request.data.limit : 5,
        1
      ),
      10
    );

    const autocomplete = request.data?.autocomplete !== false; // default true
    const country = (request.data?.country ?? 'vn').toLowerCase();

    // Rate limit: 120 req/phút (cho autocomplete type-ahead)
    await enforceRateLimit({
      name: 'geocode',
      uid: auth.uid,
      maxCount: 120,
      windowSec: 60,
    });

    const apiKey = MAPBOX_PUBLIC_KEY.value();
    if (!apiKey) {
      log.error('geocode_no_api_key');
      throw new HttpsError(
        'failed-precondition',
        'MAPBOX_PUBLIC_KEY chưa cấu hình'
      );
    }

    try {
      const encodedQuery = encodeURIComponent(query);
      const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodedQuery}.json`;

      const res = await retry(
        () =>
          axios.get(url, {
            params: {
              access_token: apiKey,
              limit,
              country,
              language: 'vi',
              autocomplete,
            },
            timeout: 5000,
          }),
        { logger: log, opName: 'mapbox_geocode' }
      );

      const features = (res.data?.features ?? []) as Array<{
        text: string;
        place_name: string;
        center: [number, number]; // [lng, lat]
        place_type: string[];
      }>;

      const places: GeocodePlace[] = features.map((f) => ({
        name: f.text,
        fullName: f.place_name,
        lng: f.center[0],
        lat: f.center[1],
        type: f.place_type?.[0] ?? 'unknown',
      }));

      log.duration('geocode_completed', startMs, {
        query_len: query.length,
        autocomplete,
        results_count: places.length,
      });

      return { places };
    } catch (err) {
      log.error('geocode_failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError('internal', 'Không tìm được địa điểm');
    }
  }
);
