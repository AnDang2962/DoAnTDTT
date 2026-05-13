/**
 * Geo utilities — Haversine + polyline projection.
 *
 * Mục đích:
 *   - Algorithm 2 (Group Gap Detection) — phiên bản v0.4 dùng polyline projection
 *     thay vì heuristic vĩ độ.
 *   - Distance Filter 50m phía client (M3 dùng cùng công thức).
 *
 * Tại sao polyline projection?
 *   Trên route quanh co (qua đèo, vòng xuyến), khoảng cách Haversine 2 điểm GPS
 *   không phản ánh "ai đi xa hơn trên đường". Ví dụ trên đèo Hải Vân:
 *     - Xe A ở km 50 (vĩ độ X)
 *     - Xe B ở km 60, vĩ độ THẤP HƠN A do đường vòng
 *   Heuristic cũ kết luận B là Sweeper (sai). Projection chiếu mỗi xe xuống
 *   polyline → tính progress thực sự (m từ điểm xuất phát).
 */

export type LatLng = { lat: number; lng: number };
export type Polyline = LatLng[];

/**
 * Khoảng cách giữa 2 tọa độ GPS theo Haversine.
 * Output: km. Độ phức tạp: O(1).
 */
export function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371;
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Tổng độ dài polyline (km). Cộng dồn Haversine từng segment.
 */
export function polylineLengthKm(polyline: Polyline): number {
  let total = 0;
  for (let i = 1; i < polyline.length; i++) {
    total += haversineKm(
      polyline[i - 1].lat,
      polyline[i - 1].lng,
      polyline[i].lat,
      polyline[i].lng
    );
  }
  return total;
}

/**
 * Chiếu 1 điểm GPS lên 1 segment (đoạn thẳng A-B).
 * Trả về: { t, distKm } — t là tham số chiếu (0 = ở A, 1 = ở B, ngoài [0,1]
 * = nằm ngoài segment), distKm = khoảng cách điểm tới projection.
 *
 * Ghi chú: dùng equirectangular approximation cho phép tính dot/cross product
 * trên flat plane. Chính xác đủ cho khoảng cách dưới 100km (route motorbike).
 */
function projectOntoSegment(
  point: LatLng,
  a: LatLng,
  b: LatLng
): { t: number; distKm: number; projected: LatLng } {
  // Convert tọa độ thành flat plane meters tại tâm = a (equirectangular)
  const cosLat = Math.cos((a.lat * Math.PI) / 180);
  const mPerDegLat = 111320; // ~111.32 km/degree latitude
  const ax = 0,
    ay = 0;
  const bx = (b.lng - a.lng) * mPerDegLat * cosLat;
  const by = (b.lat - a.lat) * mPerDegLat;
  const px = (point.lng - a.lng) * mPerDegLat * cosLat;
  const py = (point.lat - a.lat) * mPerDegLat;

  const segLenSq = (bx - ax) ** 2 + (by - ay) ** 2;
  if (segLenSq === 0) {
    // a và b trùng nhau
    return {
      t: 0,
      distKm: haversineKm(point.lat, point.lng, a.lat, a.lng),
      projected: a,
    };
  }

  // Dot product để tìm t (parameter chiếu)
  const t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / segLenSq;
  const tClamped = Math.max(0, Math.min(1, t));

  // Projected point trong flat plane
  const projX = ax + tClamped * (bx - ax);
  const projY = ay + tClamped * (by - ay);
  const dx = px - projX;
  const dy = py - projY;
  const distMeters = Math.sqrt(dx * dx + dy * dy);

  // Convert projected điểm về lat/lng để return
  const projectedLatLng: LatLng = {
    lat: a.lat + projY / mPerDegLat,
    lng: a.lng + projX / (mPerDegLat * cosLat),
  };

  return {
    t: tClamped,
    distKm: distMeters / 1000,
    projected: projectedLatLng,
  };
}

/**
 * Chiếu 1 điểm GPS lên TOÀN BỘ polyline. Tìm segment gần nhất, tính
 * "progress" (km từ điểm xuất phát) tại điểm chiếu.
 *
 * Đây là hàm quan trọng nhất — quyết định ai là Sweeper.
 *
 * @returns
 *   - progressKm: km từ polyline[0] tới điểm chiếu (xe nào càng cao
 *     càng đi xa, càng thấp càng tụt lại = Sweeper)
 *   - offRouteKm: khoảng cách từ điểm GPS tới polyline (xe nào lớn quá
 *     có nghĩa đã đi lệch route — out of scope cho v0.4)
 *   - segmentIndex: segment index của projection (0-based)
 *
 * Độ phức tạp: O(n) với n = số điểm polyline. Polyline VN thường < 500
 * điểm cho route 200km nên O(n) chấp nhận được. Có thể tối ưu bằng
 * spatial index khi route > 1000km.
 */
export function projectOntoPolyline(
  point: LatLng,
  polyline: Polyline
): { progressKm: number; offRouteKm: number; segmentIndex: number } {
  if (polyline.length < 2) {
    throw new Error('Polyline phải có ít nhất 2 điểm');
  }

  let bestIdx = 0;
  let bestT = 0;
  let bestDist = Infinity;

  for (let i = 0; i < polyline.length - 1; i++) {
    const r = projectOntoSegment(point, polyline[i], polyline[i + 1]);
    if (r.distKm < bestDist) {
      bestDist = r.distKm;
      bestIdx = i;
      bestT = r.t;
    }
  }

  // Tính progressKm = sum(segment[0..bestIdx-1]) + t * |segment[bestIdx]|
  let progressKm = 0;
  for (let i = 0; i < bestIdx; i++) {
    progressKm += haversineKm(
      polyline[i].lat,
      polyline[i].lng,
      polyline[i + 1].lat,
      polyline[i + 1].lng
    );
  }
  const segLen = haversineKm(
    polyline[bestIdx].lat,
    polyline[bestIdx].lng,
    polyline[bestIdx + 1].lat,
    polyline[bestIdx + 1].lng
  );
  progressKm += bestT * segLen;

  return {
    progressKm,
    offRouteKm: bestDist,
    segmentIndex: bestIdx,
  };
}
