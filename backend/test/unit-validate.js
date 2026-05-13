/**
 * Pure-logic unit tests for validation helpers.
 * Không cần emulator. Chạy: node test/unit-validate.js
 */
const path = require('path');
const Module = require('module');

// Compile TS on the fly using the built lib/
const { requireString, requireNumber, requireLatLng, requireRoomId } = require(
  '../functions/lib/lib/validate.js'
);

let pass = 0, fail = 0;
function expect(name, fn, errCodeExpected = null) {
  try {
    fn();
    if (errCodeExpected) {
      console.log(`✗ ${name} — expected throw, got success`);
      fail++;
    } else {
      console.log(`✓ ${name}`);
      pass++;
    }
  } catch (e) {
    if (errCodeExpected && e.code === errCodeExpected) {
      console.log(`✓ ${name} → rejected (${e.message})`);
      pass++;
    } else {
      console.log(`✗ ${name} — unexpected: ${e.message}`);
      fail++;
    }
  }
}

console.log('=== Validation unit tests ===\n');

// requireString
expect('requireString accepts valid', () => requireString('hello', 'name'));
expect('requireString rejects number', () => requireString(42, 'name'), 'invalid-argument');
expect('requireString respects minLen', () => requireString('a', 'name', { minLen: 3 }), 'invalid-argument');
expect('requireString respects maxLen', () => requireString('aaaaa', 'name', { maxLen: 3 }), 'invalid-argument');

// requireNumber
expect('requireNumber accepts valid', () => requireNumber(42, 'age'));
expect('requireNumber rejects string', () => requireNumber('42', 'age'), 'invalid-argument');
expect('requireNumber rejects NaN', () => requireNumber(NaN, 'age'), 'invalid-argument');
expect('requireNumber rejects Infinity', () => requireNumber(Infinity, 'age'), 'invalid-argument');
expect('requireNumber respects min', () => requireNumber(-5, 'lat', { min: -90, max: 90 }));
expect('requireNumber rejects out-of-range', () => requireNumber(999, 'lat', { max: 90 }), 'invalid-argument');

// requireLatLng
expect('requireLatLng valid SG', () => requireLatLng({ lat: 10.7, lng: 106.6 }));
expect('requireLatLng rejects lat=999', () => requireLatLng({ lat: 999, lng: 0 }), 'invalid-argument');
expect('requireLatLng rejects missing', () => requireLatLng({ lat: 10 }), 'invalid-argument');

// requireRoomId
expect('requireRoomId valid', () => requireRoomId('K89AGH'));
expect('requireRoomId rejects lowercase', () => requireRoomId('k89agh'), 'invalid-argument');
expect('requireRoomId rejects 5-char', () => requireRoomId('K89AG'), 'invalid-argument');
expect('requireRoomId rejects banned 0', () => requireRoomId('K89A0H'), 'invalid-argument');
expect('requireRoomId rejects banned I', () => requireRoomId('K89AIH'), 'invalid-argument');

console.log(`\n=== ${pass} passed, ${fail} failed ===`);
process.exit(fail === 0 ? 0 : 1);
