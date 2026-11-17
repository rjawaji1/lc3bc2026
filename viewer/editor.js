'use strict';

(() => {
	const $ = (id) => document.getElementById(id);
	const grid = $('editor-grid');
	const cells = [];
	const undo = [];
	const redo = [];
	let map = MapFormat.parse('SYMMETRY VERTICAL\nALTAR 1,1\nMOUSE 3,3\nCHEESE 4,3 0\n');
	let tool = 'wall';
	let focused = 0;
	let stroke = null;
	let importId = 0;

	function notice(message, error = false) {
		$('editor-notice').textContent = message;
		$('editor-notice').classList.toggle('error', error);
	}

	function remember(previous) {
		undo.push(previous);
		if (undo.length > 100) undo.shift();
		redo.length = 0;
	}

	function render() {
		$('map-symmetry').value = map.symmetry;
		$('source-label').textContent =
			map.symmetry === 'VERTICAL'
				? 'Edit left half · right half is mirrored'
				: 'Edit top half · bottom half is mirrored';
		if (!MapFormat.inSource(map, focused % 16, Math.floor(focused / 16))) focused = 0;
		for (let y = 0; y < 16; y++) {
			for (let x = 0; x < 16; x++) {
				const cell = cells[y * 16 + x];
				const tile = MapFormat.describe(map, x, y);
				const classes = ['editor-cell'];
				const description = [`(${x}, ${y})`, tile.source ? 'source' : 'mirrored', tile.wall ? 'wall' : 'floor'];
				const labels = [];
				if ((x + y) % 2) classes.push('alternate');
				if (tile.wall) classes.push('wall');
				if (tile.altar) {
					classes.push(tile.team === 1 ? 'altar-one' : 'altar-two');
					labels.push(`A${tile.team}`);
					description.push(`team ${tile.team} altar`);
				}
				if (tile.mouse) {
					classes.push(tile.team === 1 ? 'mouse-one' : 'mouse-two');
					labels.push(`M${tile.team}`);
					description.push(`team ${tile.team} mouse`);
				}
				cell.replaceChildren();
				for (const label of labels) {
					const text = document.createElement('span');
					text.textContent = label;
					cell.append(text);
				}
				if (tile.cheese !== null) {
					classes.push('spawner');
					const cheese = document.createElement('span');
					cheese.className = 'cell-cheese';
					cheese.textContent = tile.cheese === 0 ? 'C' : String(tile.cheese);
					cell.append(cheese);
					description.push(`cheese spawner, delay ${tile.cheese} ticks`);
				}
				if (map.symmetry === 'VERTICAL' && x === 7) classes.push('source-edge-x');
				if (map.symmetry === 'HORIZONTAL' && y === 7) classes.push('source-edge-y');
				cell.className = classes.join(' ');
				cell.disabled = !tile.source;
				cell.tabIndex = tile.source && y * 16 + x === focused ? 0 : -1;
				cell.title = description.join(' · ');
				cell.setAttribute('aria-label', description.join(', '));
			}
		}
		const errors = MapFormat.validate(map);
		const validation = $('map-validation');
		validation.replaceChildren();
		validation.classList.toggle('valid', errors.length === 0);
		if (errors.length) {
			const list = document.createElement('ul');
			for (const error of errors) {
				const item = document.createElement('li');
				item.textContent = error;
				list.append(item);
			}
			validation.append(list);
		} else validation.textContent = 'Valid map · ready to download.';
		$('download-map').disabled = errors.length > 0;
		$('map-counts').textContent = `${map.mice.size * 2} mice · ${map.cheese.size * 2} spawners`;
		$('map-source').value = MapFormat.serialize(map);
		$('undo').disabled = undo.length === 0;
		$('redo').disabled = redo.length === 0;
	}

	function apply(cell) {
		if (!cell || cell.disabled) return;
		const x = Number(cell.dataset.x),
			y = Number(cell.dataset.y);
		const id = y * 16 + x;
		if (stroke?.visited.has(id)) return;
		stroke?.visited.add(id);
		const previous = MapFormat.clone(map);
		try {
			const rawDelay = $('cheese-delay').value;
			const delay = rawDelay.trim() === '' ? NaN : Number(rawDelay);
			MapFormat.paint(map, tool, x, y, delay);
			if (!stroke && MapFormat.serialize(previous) !== MapFormat.serialize(map)) remember(previous);
			notice('Design the blue source half. The red half is reflected automatically.');
			render();
		} catch (error) {
			map = previous;
			notice(error.message, true);
		}
	}

	function finishStroke() {
		if (!stroke) return;
		if (MapFormat.serialize(stroke.previous) !== MapFormat.serialize(map)) remember(stroke.previous);
		stroke = null;
		render();
	}

	const corner = document.createElement('span');
	grid.append(corner);
	for (let x = 0; x < 16; x++) {
		const label = document.createElement('span');
		label.className = 'grid-axis';
		label.textContent = x;
		label.setAttribute('aria-hidden', 'true');
		grid.append(label);
	}
	for (let y = 0; y < 16; y++) {
		const label = document.createElement('span');
		label.className = 'grid-axis';
		label.textContent = y;
		label.setAttribute('aria-hidden', 'true');
		grid.append(label);
		for (let x = 0; x < 16; x++) {
			const cell = document.createElement('button');
			cell.type = 'button';
			cell.dataset.x = x;
			cell.dataset.y = y;
			grid.append(cell);
			cells.push(cell);
		}
	}

	grid.addEventListener('pointerdown', (event) => {
		const cell = event.target.closest('button');
		if (event.button !== 0 || !cell || cell.disabled) return;
		event.preventDefault();
		finishStroke();
		focused = Number(cell.dataset.y) * 16 + Number(cell.dataset.x);
		cell.focus();
		if (tool === 'wall' || tool === 'erase') stroke = { previous: MapFormat.clone(map), visited: new Set() };
		apply(cell);
	});
	grid.addEventListener('pointermove', (event) => {
		const cell = document.elementFromPoint(event.clientX, event.clientY)?.closest('.editor-cell');
		if (!cell) return;
		$('cell-label').textContent = cell.title;
		if (stroke) apply(cell);
	});
	window.addEventListener('pointerup', finishStroke);
	window.addEventListener('pointercancel', finishStroke);
	window.addEventListener('blur', finishStroke);
	grid.addEventListener('click', (event) => {
		if (event.detail === 0) apply(event.target.closest('button'));
	});
	grid.addEventListener('focusin', (event) => {
		const cell = event.target.closest('button');
		if (!cell) return;
		cells[focused].tabIndex = -1;
		focused = Number(cell.dataset.y) * 16 + Number(cell.dataset.x);
		cell.tabIndex = 0;
		$('cell-label').textContent = cell.title;
	});
	grid.addEventListener('keydown', (event) => {
		const directions = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
		if (!directions[event.key]) return;
		event.preventDefault();
		const [dx, dy] = directions[event.key];
		const x = (focused % 16) + dx,
			y = Math.floor(focused / 16) + dy;
		if (MapFormat.inSource(map, x, y)) cells[y * 16 + x].focus();
	});

	$('tools').addEventListener('click', (event) => {
		const button = event.target.closest('[data-tool]');
		if (!button) return;
		finishStroke();
		tool = button.dataset.tool;
		for (const item of $('tools').querySelectorAll('button'))
			item.setAttribute('aria-pressed', String(item === button));
	});
	$('map-symmetry').addEventListener('change', () => {
		finishStroke();
		remember(MapFormat.clone(map));
		map = MapFormat.transpose(map);
		notice('Source design transposed to match the new symmetry.');
		render();
	});
	$('undo').addEventListener('click', () => {
		finishStroke();
		if (!undo.length) return;
		redo.push(MapFormat.clone(map));
		map = undo.pop();
		render();
	});
	$('redo').addEventListener('click', () => {
		finishStroke();
		if (!redo.length) return;
		undo.push(MapFormat.clone(map));
		map = redo.pop();
		render();
	});
	$('clear-map').addEventListener('click', () => {
		if (!window.confirm('Clear this map? You can restore it with Undo.')) return;
		finishStroke();
		remember(MapFormat.clone(map));
		map = MapFormat.create(map.symmetry);
		render();
		notice('Map cleared. Place a 2×2 altar and at least one mouse before downloading.');
	});
	$('import-map').addEventListener('click', () => $('map-file').click());
	$('map-file').addEventListener('change', async () => {
		const file = $('map-file').files[0];
		if (!file) return;
		const id = ++importId;
		try {
			if (file.size > 1024 * 1024) throw new Error('Map files must be smaller than 1 MiB.');
			const source = await file.text();
			if (id !== importId) return;
			const imported = MapFormat.parse(source);
			finishStroke();
			remember(MapFormat.clone(map));
			map = imported;
			$('map-filename').value = file.name;
			render();
			notice(`Opened ${file.name}.`);
		} catch (error) {
			if (id === importId) notice(`Could not open map: ${error.message}`, true);
		} finally {
			if (id === importId) $('map-file').value = '';
		}
	});
	$('download-map').addEventListener('click', () => {
		finishStroke();
		const errors = MapFormat.validate(map);
		if (errors.length) return notice(errors.join(' '), true);
		let name =
			$('map-filename')
				.value.trim()
				.replace(/[\\/:*?"<>|\x00-\x1f]/g, '-') || 'my-arena.map';
		if (!name.endsWith('.map')) name += '.map';
		const url = URL.createObjectURL(new Blob([MapFormat.serialize(map)], { type: 'text/plain;charset=utf-8' }));
		const link = document.createElement('a');
		link.href = url;
		link.download = name;
		document.body.append(link);
		link.click();
		link.remove();
		setTimeout(() => URL.revokeObjectURL(url), 1000);
		notice(`Downloaded ${name}. Pass it to the simulator with your two bot programs.`);
	});
	window.addEventListener('keydown', (event) => {
		if (event.target.closest('input, textarea, select') || !(event.ctrlKey || event.metaKey)) return;
		if (event.key.toLowerCase() !== 'z') return;
		event.preventDefault();
		$(event.shiftKey ? 'redo' : 'undo').click();
	});

	render();
})();
