"use strict";

(() => {
  const directions = new Set(["North", "East", "South", "West"]);
  const faults = new Set(["None", "Invalid_Direction", "Unsupported_Trap", "Unsupported_Instruction", "Reserved_Instruction"]);
  const results = new Set(["Undecided", "Team_One_Won", "Team_Two_Won", "Draw"]);
  const reasons = new Set(["None", "Elimination", "Tick_Limit"]);
  const MAX_BYTES = 128 * 1024 * 1024;
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  const integer = (n, min, max) => Number.isSafeInteger(n) && n >= min && n <= max;
  const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
  const position = value => object(value) && integer(value.x, 0, 15) && integer(value.y, 0, 15);
  const list = (value, name, limit) => {
    const items = value === null ? [] : value;
    check(Array.isArray(items) && items.length <= limit, `Invalid ${name} array`);
    return items;
  };

  function parseReplay(source) {
    check(typeof source === "string" && source.length <= MAX_BYTES, "Replay exceeds the 128 MiB limit");
    const lines = source.replace(/^\uFEFF/, "").split(/\r?\n/);
    let header = null;
    const frames = [];
    let identities = null;
    for (let index = 0; index < lines.length; index++) {
      if (!lines[index].trim()) continue;
      try {
        const record = JSON.parse(lines[index]);
        check(object(record), "Expected a JSON object");
        if (header === null) {
          check(record.kind === "header" && record.version === 1, "Expected a version 1 replay header");
          check(record.width === 16 && record.height === 16, "Only 16×16 maps are supported");
          check(integer(record.max_ticks, 1, 10000), "Invalid tick limit");
          check(typeof record.map_name === "string", "Invalid map name");
          check(Array.isArray(record.team_names) && record.team_names.length === 2 && record.team_names.every(n => typeof n === "string"), "Invalid team names");
          check(Array.isArray(record.tiles) && record.tiles.length === 256 && record.tiles.every(n => integer(n, 0, 3)), "Invalid terrain");
          header = record;
          continue;
        }
        check(record.kind === "frame", "Expected a frame");
        check(integer(record.tick, 0, header.max_ticks) && record.tick === frames.length, "Frames must start at tick 0 and be consecutive");
        check(!frames.length || frames[frames.length - 1].result === "Undecided", "Frame found after match completion");
        check(results.has(record.result) && reasons.has(record.end_reason), "Invalid match result");
        check((record.result === "Undecided") === (record.end_reason === "None"), "Inconsistent result and end reason");
        check(Array.isArray(record.scores) && record.scores.length === 2 && record.scores.every(n => integer(n, 0, Number.MAX_SAFE_INTEGER)), "Invalid scores");
        record.mice = list(record.mice, "mice", 256);
        record.spawners = list(record.spawners, "spawners", 256);
        record.dropped_cheese = list(record.dropped_cheese, "dropped cheese", 256);
        record.turns = list(record.turns, "turns", 256);
        const ids = new Map();
        const occupied = new Set();
        for (const mouse of record.mice) {
          check(position(mouse) && integer(mouse.id, 1, 65535) && integer(mouse.team, 1, 2), "Invalid mouse identity or position");
          check(!ids.has(mouse.id), "Duplicate mouse ID");
          check(directions.has(mouse.facing) && typeof mouse.alive === "boolean" && typeof mouse.has_cheese === "boolean" && faults.has(mouse.fault), "Invalid mouse state");
          check(!mouse.has_cheese || mouse.alive, "Dead mouse cannot carry cheese");
          if (mouse.alive) {
            const cell = mouse.y * 16 + mouse.x;
            check(!occupied.has(cell) && header.tiles[cell] !== 1, "Overlapping mice or mouse inside a wall");
            occupied.add(cell);
          }
          ids.set(mouse.id, mouse.team);
        }
        if (identities === null) identities = ids;
        check(ids.size === identities.size && [...ids].every(([id, team]) => identities.get(id) === team), "Mouse identities changed between frames");
        const spawnerPositions = new Set();
        for (const spawner of record.spawners) {
          check(position(spawner) && integer(spawner.delay, 0, Number.MAX_SAFE_INTEGER) && typeof spawner.present === "boolean", "Invalid spawner");
          const key = spawner.y * 16 + spawner.x;
          check(!spawnerPositions.has(key) && header.tiles[key] === 0, "Duplicate spawner or spawner not on floor");
          spawnerPositions.add(key);
        }
        const dropPositions = new Set();
        for (const drop of record.dropped_cheese) {
          check(position(drop) && integer(drop.count, 1, Number.MAX_SAFE_INTEGER), "Invalid dropped cheese");
          const key = drop.y * 16 + drop.x;
          check(!dropPositions.has(key) && header.tiles[key] !== 1, "Duplicate dropped cheese or cheese inside wall");
          dropPositions.add(key);
        }
        const turnIds = new Set();
        for (const turn of record.turns) {
          check(object(turn) && ids.has(turn.mouse_id) && !turnIds.has(turn.mouse_id), "Invalid or duplicate action owner");
          check(["wait", "move", "attack", "squeak"].includes(turn.action) && faults.has(turn.fault), "Invalid action");
          check(directions.has(turn.direction) && integer(turn.message, 0, 65535), "Invalid action arguments");
          turnIds.add(turn.mouse_id);
        }
        check(record.tick !== 0 || record.turns.length === 0, "Initial frame cannot contain actions");
        frames.push(record);
      } catch (error) {
        throw new Error(`Line ${index + 1}: ${error.message}`);
      }
    }
    check(header !== null && frames.length > 0, "Replay needs a header and an initial frame");
    return {header, frames, complete: frames[frames.length - 1].result !== "Undecided"};
  }

  const api = {parseReplay, MAX_BYTES};
  globalThis.ReplayFormat = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})();
