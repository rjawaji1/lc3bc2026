'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const test = require('node:test');
const MapFormat = require('./map-format.js');

const example = 'SYMMETRY VERTICAL\nALTAR 1,1\nMOUSE 3,3\nCHEESE 4,3 0\nWALL 2,5\n';

test('existing showcase imports and round-trips without losing data', () => {
	const source = readFileSync(`${__dirname}/../examples/showcase.map`, 'utf8');
	const map = MapFormat.parse(source);
	assert.deepEqual(MapFormat.validate(map), []);
	assert.deepEqual(MapFormat.parse(MapFormat.serialize(map)), map);
});

test('preview reflects walls, full altars, mice and cheese using simulator rules', () => {
	for (const symmetry of ['VERTICAL', 'HORIZONTAL']) {
		const vertical = MapFormat.parse(example);
		const map = symmetry === 'VERTICAL' ? vertical : MapFormat.transpose(vertical);
		for (let y = 0; y < 16; y++)
			for (let x = 0; x < 16; x++) {
				if (!MapFormat.inSource(map, x, y)) continue;
				const [rx, ry] = MapFormat.reflect(map, x, y);
				const source = MapFormat.describe(map, x, y);
				const reflected = MapFormat.describe(map, rx, ry);
				assert.deepEqual(reflected, { ...source, source: false, team: 2 });
			}
		assert.deepEqual(MapFormat.parse(MapFormat.serialize(map)), map);
	}
});

test('switching symmetry twice preserves the design', () => {
	const map = MapFormat.parse(example);
	assert.deepEqual(MapFormat.transpose(MapFormat.transpose(map)), map);
	assert.deepEqual(MapFormat.reflect(map, 3, 2), [12, 2]);
	assert.deepEqual(MapFormat.reflect(MapFormat.transpose(map), 2, 3), [2, 12]);
});

test('paint supports shared mouse/spawner cells and wall replacement', () => {
	const map = MapFormat.parse(example);
	MapFormat.paint(map, 'cheese', 3, 3, 12);
	assert.equal(map.cheese.get('3,3'), 12);
	assert.ok(map.mice.has('3,3'));
	MapFormat.paint(map, 'wall', 3, 3);
	assert.ok(map.walls.has('3,3'));
	assert.ok(!map.mice.has('3,3'));
	assert.ok(!map.cheese.has('3,3'));
	MapFormat.paint(map, 'erase', 3, 3);
	assert.ok(!map.walls.has('3,3'));
});

test('altar is moved as a 2x2 object and erased from any occupied cell', () => {
	const map = MapFormat.parse(example);
	MapFormat.paint(map, 'altar', 5, 10);
	assert.deepEqual(map.altar, [5, 10]);
	assert.equal(MapFormat.describe(map, 6, 11).altar, true);
	assert.equal(MapFormat.describe(map, 1, 1).altar, false);
	MapFormat.paint(map, 'erase', 6, 11);
	assert.equal(map.altar, null);
});

test('placement rejects the mirrored half, overlaps and altar boundary crossings', () => {
	const map = MapFormat.parse(example);
	assert.throws(() => MapFormat.paint(map, 'wall', 8, 3), /source half/);
	assert.throws(() => MapFormat.paint(map, 'altar', 7, 3), /fit entirely/);
	assert.throws(() => MapFormat.paint(map, 'altar', 2, 4), /clear 2×2/);
	assert.throws(() => MapFormat.paint(map, 'mouse', 1, 1), /floor/);
	assert.throws(() => MapFormat.paint(map, 'cheese', 3, 4, -1), /nonnegative/);
	assert.throws(() => MapFormat.paint(map, 'cheese', 3, 4, 1.5), /nonnegative/);
	assert.throws(() => MapFormat.paint(map, 'wall', 1, 1), /altar/);
});

test('invalid maps are rejected before import or download', () => {
	for (const source of [
		'ALTAR 1,1\nMOUSE 3,3',
		example + 'SYMMETRY HORIZONTAL\n',
		example + 'MOUSE 3,3\n',
		example + 'CHEESE 4,3 2\n',
		example + 'WALL 2,5\n',
		example + 'WALL 1,1\n',
		example + 'WALL 8,3\n',
		example + 'MOUSE 2,5\n',
		example + 'CHEESE 2,5 0\n',
		example + 'MOUSE 16,0\n',
		example + 'CHEESE 3,4 -1\n',
		example + 'CHEESE 3,4 9007199254740992\n',
		example.replace('ALTAR 1,1', 'ALTAR 7,1'),
		example.replace('VERTICAL', 'DIAGONAL'),
	])
		assert.throws(() => MapFormat.parse(source), source);
	assert.equal(MapFormat.validate(MapFormat.create()).length, 2);
});

test('comments, whitespace and arbitrary declaration ordering are supported', () => {
	const map = MapFormat.parse('  MOUSE 3,3 # spawn\r\nCHEESE 3,3 5\nALTAR 1,1\n\nSYMMETRY VERTICAL\n');
	assert.equal(map.cheese.get('3,3'), 5);
	assert.deepEqual(MapFormat.validate(map), []);
});

test('cloned history snapshots are independent', () => {
	const map = MapFormat.parse(example);
	const previous = MapFormat.clone(map);
	MapFormat.paint(map, 'erase', 1, 1);
	MapFormat.paint(map, 'wall', 0, 0);
	assert.deepEqual(previous.altar, [1, 1]);
	assert.ok(!previous.walls.has('0,0'));
});
