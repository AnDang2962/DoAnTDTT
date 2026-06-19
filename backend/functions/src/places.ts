import { onCall, HttpsError } from 'firebase-functions/v2/https';
import axios from 'axios';

interface NearbyPlace {
  name: string;
  lat: number;
  lng: number;
  address: string;
  distanceKm: number;
  category: string;
}

const CATEGORY_MAP: Record<string, string> = {
  gas_station: 'gas_station',
  restaurant:  'restaurant',
  hotel:       'hotel',
  rest_stop:   'rest_area',
  hospital:    'hospital',
  atm:         'atm',
  mechanic:    'auto_repair',
};

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
    Math.cos((lat2 * Math.PI) / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export const searchNearbyPlace = onCall(
  { region: 'asia-southeast1', secrets: ['MAPBOX_PUBLIC_KEY'] },
  async (request) => {
    const { lat, lng, placeType, radiusKm = 5 } = request.data as {
      lat: number;
      lng: number;
      placeType: string;
      radiusKm?: number;
    };

    if (!lat || !lng || !placeType) {
      throw new HttpsError('invalid-argument', 'Thiếu lat, lng, hoặc placeType');
    }

    const category = CATEGORY_MAP[placeType];
    if (!category) throw new HttpsError('invalid-argument', `placeType không hợp lệ: ${placeType}`);

    const token = process.env.MAPBOX_PUBLIC_KEY;
    if (!token) throw new HttpsError('internal', 'Thiếu MAPBOX_PUBLIC_KEY');

    const deltaLat = radiusKm / 111;
    const deltaLng = radiusKm / (111 * Math.cos((lat * Math.PI) / 180));
    const bbox = `${lng - deltaLng},${lat - deltaLat},${lng + deltaLng},${lat + deltaLat}`;

    try {
      const res = await axios.get(
        `https://api.mapbox.com/search/searchbox/v1/category/${category}`,
        {
          params: {
            proximity: `${lng},${lat}`,
            bbox,
            limit: 10,
            language: 'vi',
            access_token: token,
          },
          timeout: 15000,
        }
      );

      const features: any[] = res.data?.features ?? [];

      const places: NearbyPlace[] = features
        .filter((f) => f.geometry?.coordinates?.length === 2)
        .map((f) => {
          const [pLng, pLat] = f.geometry.coordinates as [number, number];
          const p = f.properties ?? {};
          return {
            name: p.name ?? 'Không rõ tên',
            lat: pLat,
            lng: pLng,
            address: p.full_address ?? p.place_formatted ?? '',
            distanceKm: Math.round(haversineKm(lat, lng, pLat, pLng) * 10) / 10,
            category: placeType,
          };
        })
        .filter((p) => p.distanceKm <= radiusKm)
        .sort((a, b) => a.distanceKm - b.distanceKm)
        .slice(0, 5);

      return { places };
    } catch (e: any) {
      throw new HttpsError('internal', `SearchBox thất bại: ${e?.response?.status ?? e?.message}`);
    }
  }
);
