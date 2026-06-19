/**
 * Unit tests for polyline projection.
 * Pure logic, không cần emulator. Chạy: node test/unit-geo.js
 */
const {
  haversineKm,
  polylineLengthKm,
  projectOntoPolyline,
} = require('../functions/lib/lib/geo.js');

let pass = 0,
  fail = 0;

function expectClose(name, actual, expected, tolerance = 0.05) {
  const diff = Math.abs(actual - expected);
  if (diff <= tolerance) {
    console.log(`✓ ${name} (got ${actual.toFixed(3)}, expected ~${expected})`);
    pass++;
  } else {
    console.log(
      `✗ ${name} (got ${actual.toFixed(3)}, expected ${expected}, diff ${diff.toFixed(3)})`
    );
    fail++;
  }
}

function expectEq(name, actual, expected) {
  if (actual === expected) {
    console.log(`✓ ${name}`);
    pass++;
  } else {
    console.log(`✗ ${name} (got ${actual}, expected ${expected})`);
    fail++;
  }
}

console.log('=== Geo (Polyline) Unit Tests ===\n');

// === Haversine sanity ===
console.log('--- Haversine ---');
expectClose(
  'SG → Phan Thiết (~165km)',
  haversineKm(10.7769, 106.7009, 10.9333, 108.1),
  155, // straight-line, đường chim bay
  10
);
expectClose(
  'Same point = 0km',
  haversineKm(10.7, 106.7, 10.7, 106.7),
  0,
  0.01
);

// === polylineLengthKm ===
console.log('\n--- polylineLengthKm ---');
const sgRoute = [
  { lat: 10.7769, lng: 106.7009 }, // SG
  { lat: 10.85, lng: 106.85 }, // mid 1
  { lat: 10.9, lng: 107.5 }, // mid 2
  { lat: 10.9333, lng: 108.1 }, // Phan Thiết
];
expectClose(
  'SG route 4 điểm (~155km)',
  polylineLengthKm(sgRoute),
  155,
  10
);

// === projectOntoPolyline ===
console.log('\n--- projectOntoPolyline ---');

// Test 1: Điểm trùng start → progressKm = 0
const r1 = projectOntoPolyline(sgRoute[0], sgRoute);
expectClose('Điểm trùng start → progress=0', r1.progressKm, 0, 0.1);
expectEq('Điểm trùng start → segment=0', r1.segmentIndex, 0);

// Test 2: Điểm trùng end → progressKm = totalLength
const r2 = projectOntoPolyline(sgRoute[3], sgRoute);
expectClose('Điểm trùng end → progress=totalLen', r2.progressKm, 155, 10);

// Test 3: Điểm chính giữa segment 0 → progressKm ≈ halfSegment0
const halfPoint = {
  lat: (sgRoute[0].lat + sgRoute[1].lat) / 2,
  lng: (sgRoute[0].lng + sgRoute[1].lng) / 2,
};
const r3 = projectOntoPolyline(halfPoint, sgRoute);
const seg0Len = haversineKm(
  sgRoute[0].lat,
  sgRoute[0].lng,
  sgRoute[1].lat,
  sgRoute[1].lng
);
expectClose('Điểm giữa seg0 → progress=halfSeg0', r3.progressKm, seg0Len / 2, 0.5);
expectClose('Điểm giữa seg0 → off-route ~0', r3.offRouteKm, 0, 0.5);

// Test 4: Điểm CÁCH XA polyline → off-route lớn
const offRoutePoint = { lat: 12.0, lng: 109.0 }; // Nha Trang, lệch hẳn
const r4 = projectOntoPolyline(offRoutePoint, sgRoute);
console.log(
  `   off-route Nha Trang: ${r4.offRouteKm.toFixed(1)}km (kỳ vọng > 100km)`
);
if (r4.offRouteKm > 100) {
  console.log('✓ Off-route detection work');
  pass++;
} else {
  console.log('✗ Off-route detection FAIL');
  fail++;
}

// Test 5: Sweeper ordering - 2 thành viên trên cùng route
console.log('\n--- Sweeper detection scenario ---');
const memberA = { lat: 10.78, lng: 106.71 }; // gần SG
const memberB = { lat: 10.92, lng: 107.8 }; // gần Phan Thiết
const aProj = projectOntoPolyline(memberA, sgRoute);
const bProj = projectOntoPolyline(memberB, sgRoute);
console.log(
  `   Member A progress: ${aProj.progressKm.toFixed(1)}km, off-route: ${aProj.offRouteKm.toFixed(2)}km`
);
console.log(
  `   Member B progress: ${bProj.progressKm.toFixed(1)}km, off-route: ${bProj.offRouteKm.toFixed(2)}km`
);
if (aProj.progressKm < bProj.progressKm) {
  console.log('✓ Sweeper = A (progress thấp hơn) → đúng');
  pass++;
} else {
  console.log('✗ Sweeper detection sai logic');
  fail++;
}

// Test 6: Route đi NGƯỢC lại (Bắc → Nam) — kiểm tra heuristic vĩ độ KHÔNG còn áp dụng
console.log('\n--- Route Bắc → Nam (chứng minh polyline fix vấn đề v0.3) ---');
const reverseRoute = [
  { lat: 10.9333, lng: 108.1 }, // Phan Thiết (start)
  { lat: 10.85, lng: 106.85 },
  { lat: 10.7769, lng: 106.7009 }, // SG (end)
];
// memberA gần SG (vĩ độ thấp), memberB gần Phan Thiết (vĩ độ cao)
// v0.3 sẽ kết luận A là Sweeper (vĩ độ thấp nhất) — SAI vì A đi xa hơn
// v0.4 polyline projection sẽ đúng: B mới là Sweeper
const aProj2 = projectOntoPolyline(memberA, reverseRoute);
const bProj2 = projectOntoPolyline(memberB, reverseRoute);
console.log(
  `   Member A (gần SG, vĩ độ thấp) progress: ${aProj2.progressKm.toFixed(1)}km`
);
console.log(
  `   Member B (gần Phan Thiết, vĩ độ cao) progress: ${bProj2.progressKm.toFixed(1)}km`
);
if (bProj2.progressKm < aProj2.progressKm) {
  console.log(
    '✓ Sweeper = B (vĩ độ CAO nhưng progress thấp) — v0.3 sai, v0.4 đúng!'
  );
  pass++;
} else {
  console.log('✗ Polyline detection FAIL trên route ngược');
  fail++;
}

console.log(`\n=== ${pass} passed, ${fail} failed ===`);
process.exit(fail === 0 ? 0 : 1);
