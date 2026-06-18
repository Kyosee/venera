import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSource } from './gen-altstore-source.mjs';

const v210 = {
  version: '2.0.10', build: '210', date: '2026-06-05', description: 'old notes',
  downloadURL: 'https://github.com/Kyosee/venera/releases/download/v2.0.10/venera-ios-2.0.10%2B210.ipa',
  size: 111,
};
const v211 = {
  version: '2.0.11', build: '212', date: '2026-06-14', description: 'new notes',
  downloadURL: 'https://github.com/Kyosee/venera/releases/download/v2.0.11/venera-ios-2.0.11%2B212.ipa',
  size: 15884946,
};

test('seeds from empty: identity + first version', () => {
  const s = buildSource(null, v210);
  assert.equal(s.identifier, 'io.github.kyosee.venera');
  assert.equal(s.apps[0].bundleIdentifier, 'io.github.kyosee.venera');
  assert.equal(s.apps[0].versions.length, 1);
  assert.equal(s.apps[0].versions[0].version, '2.0.10');
  assert.equal(s.apps[0].versions[0].minOSVersion, '14.0');
});

test('prepends newer version (newest first) + mirrors legacy fields', () => {
  let s = buildSource(null, v210);
  s = buildSource(s, v211);
  assert.equal(s.apps[0].versions.length, 2);
  assert.equal(s.apps[0].versions[0].version, '2.0.11');
  assert.equal(s.apps[0].version, '2.0.11');
  assert.equal(s.apps[0].versionDate, '2026-06-14');
  assert.equal(s.apps[0].downloadURL, v211.downloadURL);
  assert.equal(s.apps[0].size, 15884946);
});

test('idempotent for same version+build', () => {
  let s = buildSource(null, v211);
  s = buildSource(s, v211);
  assert.equal(s.apps[0].versions.length, 1);
});

test('orders out-of-order inserts by version desc', () => {
  let s = buildSource(null, v211);
  s = buildSource(s, v210);
  assert.equal(s.apps[0].versions[0].version, '2.0.11');
  assert.equal(s.apps[0].version, '2.0.11');
});

test('keeps %2B-encoded downloadURL verbatim', () => {
  const s = buildSource(null, v211);
  assert.ok(s.apps[0].versions[0].downloadURL.endsWith('%2B212.ipa'));
});
