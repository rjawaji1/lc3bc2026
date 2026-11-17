'use strict';

const MapFormat = (() => {
	const SIZE = 16;
	const key = (x, y) => `${x},${y}`;
	const point = (value) => value.split(',').map(Number);
	const inBounds = (x, y) => Number.isInteger(x) && Number.isInteger(y) && x >= 0 && y >= 0 && x < SIZE && y < SIZE;
	const inSource = (map, x, y) => inBounds(x, y) && (map.symmetry === 'VERTICAL' ? x < 8 : y < 8);
	const reflect = (map, x, y) => (map.symmetry === 'VERTICAL' ? [15 - x, y] : [x, 15 - y]);
	const onAltar = (map, x, y) =>
		map.altar !== null && x >= map.altar[0] && x < map.altar[0] + 2 && y >= map.altar[1] && y < map.altar[1] + 2;

	function create(symmetry = 'VERTICAL') {
		return { symmetry, altar: null, walls: new Set(), mice: new Set(), cheese: new Map() };
	}

	function clone(map) {
		return {
			symmetry: map.symmetry,
			altar: map.altar ? [...map.altar] : null,
			walls: new Set(map.walls),
			mice: new Set(map.mice),
			cheese: new Map(map.cheese),
		};
	}

	function validate(map) {
		const errors = [];
		if (!['VERTICAL', 'HORIZONTAL'].includes(map.symmetry)) errors.push('Choose vertical or horizontal symmetry.');
		if (!map.altar) errors.push('Place one 2×2 altar.');
		else {
			const [x, y] = map.altar;
			if (!inSource(map, x, y) || !inSource(map, x + 1, y + 1))
				errors.push('The entire altar must fit in the source half.');
			for (let dy = 0; dy < 2; dy++)
				for (let dx = 0; dx < 2; dx++) {
					if (map.walls.has(key(x + dx, y + dy))) errors.push('The altar cannot overlap walls.');
				}
		}
		if (!map.mice.size) errors.push('Place at least one mouse in the source half.');
		for (const cell of map.walls) {
			if (!inSource(map, ...point(cell))) errors.push('Walls must be in the source half.');
		}
		for (const cell of [...map.mice, ...map.cheese.keys()]) {
			const [x, y] = point(cell);
			if (!inSource(map, x, y) || map.walls.has(cell) || onAltar(map, x, y))
				errors.push('Mice and cheese spawners must occupy floor cells in the source half.');
		}
		for (const delay of map.cheese.values()) {
			if (!Number.isSafeInteger(delay) || delay < 0)
				errors.push('Cheese delays must be nonnegative whole numbers.');
		}
		return [...new Set(errors)];
	}

	function paint(map, tool, x, y, delay = 0) {
		if (!inSource(map, x, y)) throw new Error('Edit the source half; the other half is reflected automatically.');
		const cell = key(x, y);
		if (tool === 'erase') {
			if (onAltar(map, x, y)) map.altar = null;
			map.walls.delete(cell);
			map.mice.delete(cell);
			map.cheese.delete(cell);
		} else if (tool === 'wall') {
			if (onAltar(map, x, y)) throw new Error('Erase or move the altar before placing a wall here.');
			map.walls.add(cell);
			map.mice.delete(cell);
			map.cheese.delete(cell);
		} else if (tool === 'altar') {
			if (!inSource(map, x + 1, y + 1)) throw new Error('The 2×2 altar must fit entirely in the source half.');
			for (let dy = 0; dy < 2; dy++)
				for (let dx = 0; dx < 2; dx++) {
					const target = key(x + dx, y + dy);
					if (map.walls.has(target) || map.mice.has(target) || map.cheese.has(target))
						throw new Error('Place the altar on a clear 2×2 floor area.');
				}
			map.altar = [x, y];
		} else if (tool === 'mouse' || tool === 'cheese') {
			if (map.walls.has(cell) || onAltar(map, x, y))
				throw new Error('Mice and cheese spawners must be placed on floor.');
			if (tool === 'mouse') map.mice.add(cell);
			else {
				if (!Number.isSafeInteger(delay) || delay < 0)
					throw new Error('Enter a nonnegative whole-number cheese delay.');
				map.cheese.set(cell, delay);
			}
		} else throw new Error('Unknown drawing tool.');
	}

	function transpose(map) {
		const result = create(map.symmetry === 'VERTICAL' ? 'HORIZONTAL' : 'VERTICAL');
		const swap = (cell) => point(cell).reverse().join(',');
		result.altar = map.altar ? [...map.altar].reverse() : null;
		result.walls = new Set([...map.walls].map(swap));
		result.mice = new Set([...map.mice].map(swap));
		result.cheese = new Map([...map.cheese].map(([cell, delay]) => [swap(cell), delay]));
		return result;
	}

	function serialize(map) {
		const lines = [`SYMMETRY ${map.symmetry}`];
		const sorted = (cells) =>
			[...cells].sort((a, b) => {
				const [ax, ay] = point(a),
					[bx, by] = point(b);
				return ay - by || ax - bx;
			});
		if (map.altar) lines.push(`ALTAR ${map.altar.join(',')}`);
		for (const cell of sorted(map.mice)) lines.push(`MOUSE ${cell}`);
		for (const cell of sorted(map.cheese.keys())) lines.push(`CHEESE ${cell} ${map.cheese.get(cell)}`);
		for (const cell of sorted(map.walls)) lines.push(`WALL ${cell}`);
		return lines.join('\n') + '\n';
	}

	function parse(source) {
		const map = create();
		let symmetrySeen = false;
		for (const [index, raw] of source.split(/\r?\n/).entries()) {
			const line = raw.split('#')[0].trim();
			if (!line) continue;
			const fields = line.split(/\s+/);
			const [command, value] = fields;
			const fail = (message) => {
				throw new Error(`Line ${index + 1}: ${message}`);
			};
			if (fields.length !== (command === 'CHEESE' ? 3 : 2)) fail('Wrong number of arguments.');
			if (command === 'SYMMETRY') {
				if (symmetrySeen || !['VERTICAL', 'HORIZONTAL'].includes(value))
					fail('Expected one VERTICAL or HORIZONTAL symmetry declaration.');
				map.symmetry = value;
				symmetrySeen = true;
				continue;
			}
			if (!['ALTAR', 'WALL', 'MOUSE', 'CHEESE'].includes(command)) fail('Unknown map keyword.');
			if (!/^\d+,\d+$/.test(value) || !inBounds(...point(value)))
				fail('Expected coordinates from 0 to 15, written as x,y.');
			const cell = key(...point(value));
			if (command === 'ALTAR') {
				if (map.altar) fail('Only one source altar is allowed.');
				map.altar = point(cell);
			} else if (command === 'WALL') {
				if (map.walls.has(cell)) fail('Duplicate wall.');
				map.walls.add(cell);
			} else if (command === 'MOUSE') {
				if (map.mice.has(cell)) fail('Duplicate mouse.');
				map.mice.add(cell);
			} else {
				if (map.cheese.has(cell)) fail('Duplicate cheese spawner.');
				if (!/^\d+$/.test(fields[2])) fail('Cheese delay must be a nonnegative whole number.');
				map.cheese.set(cell, Number(fields[2]));
			}
		}
		if (!symmetrySeen) throw new Error('Missing SYMMETRY declaration.');
		const errors = validate(map);
		if (errors.length) throw new Error(errors.join(' '));
		return map;
	}

	function describe(map, x, y) {
		const source = inSource(map, x, y);
		const [sx, sy] = source ? [x, y] : reflect(map, x, y);
		const cell = key(sx, sy);
		return {
			source,
			wall: map.walls.has(cell),
			altar: onAltar(map, sx, sy),
			mouse: map.mice.has(cell),
			cheese: map.cheese.has(cell) ? map.cheese.get(cell) : null,
			team: source ? 1 : 2,
		};
	}

	return { SIZE, create, clone, validate, paint, transpose, serialize, parse, describe, inSource, reflect };
})();

if (typeof module !== 'undefined') module.exports = MapFormat;
