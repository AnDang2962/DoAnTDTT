/**
 * Module 2: Weather Proxy (HARDENED v0.2)
 *
 * + Retry với exponential backoff cho network/5xx error
 * + Timeout 5s
 * + Structured logging
 * + Strict validation
 * + Rate limit 60 req/phút/user (chống abuse quota free tier)
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import axios from 'axios';
import { requireAuth } from './lib/auth';
import { requireLatLng } from './lib/validate';
import { makeLogger } from './lib/logger';
import { enforceRateLimit } from './lib/rateLimit';
import { retry } from './lib/retry';

const OPENWEATHER_API_KEY = defineSecret('OPENWEATHER_API_KEY');

interface WeatherResult {
  lat: number;
  lng: number;
  tempC: number;
  weatherMain: string;
  description: string;
  isDangerous: boolean;
  rawCode: number;
}

export const getWeatherAlongRoute = onCall<
  { lat: number; lng: number },
  Promise<WeatherResult>
>(
  {
    region: 'asia-southeast1',
    secrets: [OPENWEATHER_API_KEY],
    timeoutSeconds: 15,
    memory: '256MiB',
  },
  async (request) => {
    const log = makeLogger('getWeatherAlongRoute');
    const startMs = Date.now();
    const auth = requireAuth(request);

    // Validate
    const { lat, lng } = requireLatLng(request.data ?? {});

    // Rate limit (chống abuse quota OpenWeatherMap free tier 1000 calls/day)
    await enforceRateLimit({
      name: 'weather',
      uid: auth.uid,
      maxCount: 60,
      windowSec: 60,
    });

    const apiKey = OPENWEATHER_API_KEY.value();
    if (!apiKey) {
      log.error('weather_no_api_key');
      throw new HttpsError(
        'failed-precondition',
        'OPENWEATHER_API_KEY chưa cấu hình'
      );
    }

    try {
      const res = await retry(
        () =>
          axios.get('https://api.openweathermap.org/data/2.5/weather', {
            params: { lat, lon: lng, units: 'metric', appid: apiKey },
            timeout: 5000,
          }),
        { maxAttempts: 3, baseDelayMs: 200, logger: log, opName: 'openweather' }
      );

      const w = res.data;
      const code = (w.weather?.[0]?.id as number | undefined) ?? 800;

      // Mã thời tiết nguy hiểm (theo OpenWeatherMap weather codes):
      //   2xx Thunderstorm | 3xx Drizzle | 5xx Rain | 6xx Snow | 7xx Atmosphere
      // Code 800-804 = Clear/Clouds → an toàn
      const isDangerous = code < 800;

      const result: WeatherResult = {
        lat,
        lng,
        tempC: w.main?.temp ?? 0,
        weatherMain: w.weather?.[0]?.main ?? 'Unknown',
        description: w.weather?.[0]?.description ?? '',
        isDangerous,
        rawCode: code,
      };

      log.duration('weather_completed', startMs, {
        code,
        is_dangerous: isDangerous,
      });
      return result;
    } catch (err) {
      log.error('weather_failed', {
        error: err instanceof Error ? err.message : String(err),
      });
      throw new HttpsError('internal', 'Không lấy được dữ liệu thời tiết');
    }
  }
);
