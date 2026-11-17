"use strict";

(() => {
  const $ = id => document.getElementById(id);
  const canvas = $("board");
  const ctx = canvas.getContext("2d");
  const PAD = 32, CELL = 56, SIZE = 16;
  const colors = {one: "#62c4ff", two: "#ff8f87", gold: "#ffd36d"};
  const vectors = {North: [0, -1], East: [1, 0], South: [0, 1], West: [-1, 0]};
  let replay = null, at = 0, selected = null, playing = false, clock = null, elapsed = 0, loadId = 0;
  const teamColor = team => team === 1 ? colors.one : colors.two;
  const basename = name => name.split(/[\\/]/).pop() || name;
  const current = () => replay?.frames[at];
  const previous = () => at > 0 ? replay.frames[at - 1] : null;
  const center = (x, y) => [PAD + (x + .5) * CELL, PAD + (y + .5) * CELL];

  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
  }

  function notice(message, error = false) {
    $("notice").textContent = message;
    $("notice").classList.toggle("error", error);
  }

  function pause() {
    playing = false;
    clock = null;
    elapsed = 0;
    $("play").textContent = "Play";
  }

  async function loadFile(file) {
    if (!file) return;
    const id = ++loadId;
    pause();
    try {
      if (file.size > ReplayFormat.MAX_BYTES) throw new Error("Replay exceeds the 128 MiB limit");
      notice(`Reading ${file.name}…`);
      const source = await file.text();
      if (id !== loadId) return;
      const parsed = ReplayFormat.parseReplay(source);
      replay = parsed;
      at = 0;
      selected = null;
      $("timeline").max = replay.frames.length - 1;
      $("empty").classList.add("hidden");
      $("name-one").textContent = basename(replay.header.team_names[0]);
      $("name-two").textContent = basename(replay.header.team_names[1]);
      $("name-one").title = replay.header.team_names[0];
      $("name-two").title = replay.header.team_names[1];
      $("map-name").textContent = basename(replay.header.map_name);
      $("map-name").title = replay.header.map_name;
      notice(`${file.name} · ${replay.frames.length.toLocaleString()} snapshots · ${replay.complete ? "complete match" : "partial recording: match outcome not recorded"}`);
      render();
    } catch (error) {
      if (id === loadId) notice(`Could not open replay: ${error.message}`, true);
    } finally {
      $("file").value = "";
    }
  }

  function setFrame(index) {
    if (!replay) return;
    at = Math.max(0, Math.min(replay.frames.length - 1, index));
    if (at === replay.frames.length - 1) pause();
    render();
  }

  function cheese(x, y, scale = 1) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(scale, scale);
    ctx.fillStyle = colors.gold;
    ctx.beginPath();
    ctx.moveTo(-11, 9); ctx.lineTo(12, 9); ctx.lineTo(8, -10); ctx.closePath(); ctx.fill();
    ctx.fillStyle = "#b78a36";
    for (const [dx, dy, radius] of [[-4, 3, 2.5], [5, 4, 2], [5, -3, 2]]) {
      ctx.beginPath(); ctx.arc(dx, dy, radius, 0, Math.PI * 2); ctx.fill();
    }
    ctx.restore();
  }

  function arrow(x1, y1, x2, y2, color) {
    const angle = Math.atan2(y2 - y1, x2 - x1);
    ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x2, y2);
    ctx.lineTo(x2 - 9 * Math.cos(angle - .5), y2 - 9 * Math.sin(angle - .5));
    ctx.lineTo(x2 - 9 * Math.cos(angle + .5), y2 - 9 * Math.sin(angle + .5));
    ctx.closePath(); ctx.fill();
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#101722"; ctx.fillRect(0, 0, 960, 960);
    ctx.font = "12px ui-monospace, monospace"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    for (let y = 0; y < SIZE; y++) {
      for (let x = 0; x < SIZE; x++) {
        const tile = replay ? replay.header.tiles[y * SIZE + x] : 0;
        const left = PAD + x * CELL, top = PAD + y * CELL;
        ctx.fillStyle = tile === 1 ? "#44536b" : tile === 2 ? "#193b52" : tile === 3 ? "#4c2c37" : (x + y) % 2 ? "#1c2838" : "#1a2534";
        ctx.fillRect(left + 1, top + 1, CELL - 2, CELL - 2);
        if (tile === 1) {
          ctx.fillStyle = "#53647d"; ctx.fillRect(left + 5, top + 5, CELL - 10, 5);
        }
        if (tile === 2 || tile === 3) {
          ctx.strokeStyle = tile === 2 ? "#39789c" : "#9e5b66"; ctx.lineWidth = 1;
          ctx.strokeRect(left + 7, top + 7, CELL - 14, CELL - 14);
          ctx.fillStyle = tile === 2 ? colors.one : colors.two;
          ctx.fillText(tile === 2 ? "A1" : "A2", left + CELL / 2, top + CELL / 2);
        }
      }
    }
    ctx.fillStyle = "#71839b";
    for (let i = 0; i < SIZE; i++) {
      ctx.fillText(i, PAD + (i + .5) * CELL, 15);
      ctx.fillText(i, 15, PAD + (i + .5) * CELL);
    }
    if (!replay) return;
    const frame = current(), prev = previous();
    const counts = new Map();
    for (const spawner of frame.spawners) {
      const [x, y] = center(spawner.x, spawner.y);
      ctx.strokeStyle = "#b9a25b"; ctx.lineWidth = 1.5; ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.arc(x, y, 22, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]);
      if (spawner.present) counts.set(spawner.y * SIZE + spawner.x, 1);
      else { ctx.fillStyle = "#b3a77f"; ctx.font = "13px ui-monospace, monospace"; ctx.fillText(spawner.delay, x, y); }
    }
    for (const drop of frame.dropped_cheese) {
      const key = drop.y * SIZE + drop.x;
      counts.set(key, (counts.get(key) || 0) + drop.count);
    }
    for (const [key, count] of counts) {
      const [x, y] = center(key % SIZE, Math.floor(key / SIZE));
      cheese(x, y);
      if (count > 1) {
        ctx.fillStyle = colors.gold; ctx.font = "bold 12px ui-monospace, monospace"; ctx.fillText(`×${count}`, x + 15, y - 16);
      }
    }
    if ($("show-actions").checked && prev) {
      ctx.save(); ctx.globalAlpha = .65;
      const origins = new Map(prev.mice.map(mouse => [mouse.id, mouse]));
      for (const turn of frame.turns) {
        const origin = origins.get(turn.mouse_id);
        if (!origin?.alive || turn.fault !== "None") continue;
        if (turn.action !== "move" && turn.action !== "attack") continue;
        const [dx, dy] = vectors[turn.action === "move" ? turn.direction : origin.facing];
        const [x1, y1] = center(origin.x, origin.y);
        const [x2, y2] = center(origin.x + dx, origin.y + dy);
        ctx.save(); ctx.beginPath(); ctx.rect(PAD, PAD, CELL * SIZE, CELL * SIZE); ctx.clip();
        if (turn.action === "attack") {
          ctx.fillStyle = "#ff595938";
          ctx.fillRect(x2 - CELL / 2 + 2, y2 - CELL / 2 + 2, CELL - 4, CELL - 4);
        }
        arrow(x1, y1, x2, y2, turn.action === "attack" ? "#ff6868" : teamColor(origin.team));
        ctx.restore();
      }
      ctx.restore();
    }
    for (const mouse of [...frame.mice.filter(m => !m.alive), ...frame.mice.filter(m => m.alive)]) {
      if (!mouse.alive && !$("show-dead").checked) continue;
      const [x, y] = center(mouse.x, mouse.y);
      ctx.save();
      if (!mouse.alive) {
        ctx.globalAlpha = .5; ctx.strokeStyle = teamColor(mouse.team); ctx.lineWidth = 3;
        ctx.beginPath(); ctx.moveTo(x - 10, y - 10); ctx.lineTo(x + 10, y + 10);
        ctx.moveTo(x + 10, y - 10); ctx.lineTo(x - 10, y + 10); ctx.stroke();
      } else {
        ctx.fillStyle = teamColor(mouse.team); ctx.strokeStyle = "#101722"; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(x, y, 17, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
        const [dx, dy] = vectors[mouse.facing];
        ctx.fillStyle = "#101722";
        ctx.beginPath(); ctx.moveTo(x + dx * 16, y + dy * 16);
        ctx.lineTo(x + dx * 7 - dy * 5, y + dy * 7 + dx * 5);
        ctx.lineTo(x + dx * 7 + dy * 5, y + dy * 7 - dx * 5); ctx.closePath(); ctx.fill();
        ctx.font = "bold 12px ui-monospace, monospace"; ctx.fillText(mouse.id, x - dx * 3, y - dy * 3);
        if (mouse.has_cheese) cheese(x + 16, y + 16, .65);
      }
      if (mouse.id === selected) {
        ctx.globalAlpha = 1; ctx.strokeStyle = "#eaffc9"; ctx.lineWidth = 2;
        ctx.strokeRect(x - 25, y - 25, 50, 50);
      }
      ctx.restore();
    }
    const mouse = frame.mice.find(m => m.id === selected);
    if ($("show-vision").checked && mouse) {
      for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
        if (Math.abs(x - mouse.x) <= 2 && Math.abs(y - mouse.y) <= 2) continue;
        ctx.fillStyle = "#080e19bc"; ctx.fillRect(PAD + x * CELL, PAD + y * CELL, CELL, CELL);
      }
      ctx.save(); ctx.beginPath(); ctx.rect(PAD, PAD, CELL * SIZE, CELL * SIZE); ctx.clip();
      ctx.strokeStyle = "#acffb4"; ctx.lineWidth = 2; ctx.setLineDash([7, 5]);
      ctx.strokeRect(PAD + (mouse.x - 2) * CELL, PAD + (mouse.y - 2) * CELL, CELL * 5, CELL * 5);
      ctx.restore();
    }
  }

  function renderInspection() {
    const container = $("inspection"); container.replaceChildren();
    const mouse = current().mice.find(m => m.id === selected);
    if (!mouse) {
      container.textContent = "Click a mouse in the arena or roster to inspect its state and radius-2 vision.";
      return;
    }
    const heading = element("h3", `Mouse #${mouse.id}`); heading.style.color = teamColor(mouse.team); container.append(heading);
    const values = [["Team", mouse.team], ["Position", `${mouse.x}, ${mouse.y}`], ["Facing", mouse.facing], ["State", mouse.alive ? "Alive" : "Dead"], ["Carrying cheese", mouse.has_cheese ? "Yes" : "No"], ["VM fault", mouse.fault]];
    const turn = current().turns.find(t => t.mouse_id === mouse.id);
    values.push(["Last request", turn ? turn.action + (turn.action === "move" ? ` ${turn.direction}` : "") : "—"]);
    const dl = element("dl");
    for (const [key, value] of values) dl.append(element("dt", key), element("dd", String(value)));
    container.append(dl, element("p", "Vision is a 5×5 square, without wall occlusion. The overlay shows the current position’s footprint, not necessarily the observations used for the preceding action.", "hint"));
  }

  function renderRoster() {
    const roster = $("roster"); roster.replaceChildren();
    $("roster-count").textContent = `${current().mice.length} MICE`;
    for (const mouse of current().mice) {
      const row = element("button", undefined, `roster-row${mouse.id === selected ? " selected" : ""}${mouse.alive ? "" : " dead"}`);
      row.setAttribute("aria-pressed", String(mouse.id === selected));
      const dot = element("span", undefined, "dot"); dot.style.background = teamColor(mouse.team);
      row.append(dot, element("span", `#${mouse.id} · Team ${mouse.team}`), element("small", mouse.alive ? `${mouse.x},${mouse.y}${mouse.has_cheese ? " · cheese" : ""}` : "dead"));
      row.addEventListener("click", () => { selected = mouse.id; render(); });
      roster.append(row);
    }
  }

  function renderEvents() {
    const container = $("events"); container.replaceChildren();
    const frame = current(), prev = previous();
    if (!prev) { container.textContent = "Initial state, before tick 1. No actions have run."; return; }
    container.append(element("p", "Requests below were made from the preceding frame. Combat resolves before movement."));
    const add = (text, type = "") => container.append(element("div", text, `event ${type}`));
    for (let team = 0; team < 2; team++) {
      const delta = frame.scores[team] - prev.scores[team];
      if (delta) add(`Team ${team + 1} deposited ${delta} cheese.`, "score");
    }
    const before = new Map(prev.mice.map(mouse => [mouse.id, mouse]));
    for (const mouse of frame.mice) {
      const old = before.get(mouse.id);
      if (old?.alive && !mouse.alive) add(`#${mouse.id} died (${mouse.fault === "None" ? "combat" : mouse.fault}).`, "death");
      else if (old && !old.has_cheese && mouse.has_cheese) add(`#${mouse.id} picked up cheese.`, "score");
    }
    for (const turn of frame.turns) {
      const mouse = frame.mice.find(m => m.id === turn.mouse_id);
      const origin = before.get(turn.mouse_id);
      if (turn.fault !== "None") { add(`#${turn.mouse_id}: VM fault — ${turn.fault}.`); continue; }
      let text = `#${turn.mouse_id}: ${turn.action}`;
      if (turn.action === "move") {
        text += ` ${turn.direction}`;
        text += !mouse.alive ? " · cancelled by death" : origin && mouse.x === origin.x && mouse.y === origin.y ? " · blocked" : " · moved";
      } else if (turn.action === "attack") text += ` ${origin?.facing || ""}`;
      else if (turn.action === "squeak") text += ` ${turn.message} · not resolved by game rules yet`;
      add(text);
    }
    if (!frame.turns.length) add("No action requests recorded.");
  }

  function render() {
    draw();
    if (!replay) return;
    const frame = current();
    for (const [team, suffix] of [[1, "one"], [2, "two"]]) {
      $(`score-${suffix}`).textContent = frame.scores[team - 1];
      $(`alive-${suffix}`).textContent = `${frame.mice.filter(m => m.team === team && m.alive).length} alive`;
    }
    const resultLabels = {Undecided: "IN PROGRESS", Team_One_Won: "TEAM 1 WINS · TEAM 2 LOSES", Team_Two_Won: "TEAM 2 WINS · TEAM 1 LOSES", Draw: "DRAW"};
    $("result").textContent = resultLabels[frame.result];
    $("recording-status").textContent = frame.end_reason === "Elimination" ? "Team elimination" : frame.end_reason === "Tick_Limit" ? "Tick limit · decided by score" : replay.complete ? "Complete recording" : "Partial recording";
    $("tick-label").textContent = `TICK ${frame.tick} / ${replay.frames[replay.frames.length - 1].tick}`;
    $("timeline").value = at;
    $("timeline").disabled = replay.frames.length < 2;
    $("play").disabled = replay.frames.length < 2;
    $("first").disabled = $("previous").disabled = at === 0;
    $("last").disabled = $("next").disabled = at === replay.frames.length - 1;
    renderInspection(); renderRoster(); renderEvents();
  }

  $("file").addEventListener("change", event => loadFile(event.target.files[0]));
  document.addEventListener("dragover", event => { event.preventDefault(); document.body.classList.add("dragging"); });
  document.addEventListener("dragleave", event => { if (!event.relatedTarget) document.body.classList.remove("dragging"); });
  document.addEventListener("drop", event => { event.preventDefault(); document.body.classList.remove("dragging"); loadFile(event.dataTransfer.files[0]); });
  $("play").addEventListener("click", () => {
    if (!replay) return;
    if (playing) { pause(); return; }
    if (at === replay.frames.length - 1) setFrame(0);
    playing = true; clock = null; elapsed = 0; $("play").textContent = "Pause";
  });
  for (const [id, destination] of [["first", () => 0], ["previous", () => at - 1], ["next", () => at + 1], ["last", () => replay.frames.length - 1]]) {
    $(id).addEventListener("click", () => { pause(); setFrame(destination()); });
  }
  $("timeline").addEventListener("input", event => { pause(); setFrame(Number(event.target.value)); });
  $("speed").addEventListener("change", () => { elapsed = 0; clock = null; });
  for (const id of ["show-actions", "show-dead", "show-vision"]) $(id).addEventListener("change", draw);
  canvas.addEventListener("click", event => {
    if (!replay) return;
    const rect = canvas.getBoundingClientRect();
    const x = Math.floor(((event.clientX - rect.left) * 960 / rect.width - PAD) / CELL);
    const y = Math.floor(((event.clientY - rect.top) * 960 / rect.height - PAD) / CELL);
    const matches = current().mice.filter(m => m.x === x && m.y === y && (m.alive || $("show-dead").checked));
    selected = (matches.find(m => m.alive) || matches[0])?.id ?? null;
    render();
  });
  document.addEventListener("keydown", event => {
    if (!replay || /^(INPUT|SELECT|TEXTAREA|BUTTON)$/.test(event.target.tagName) || event.ctrlKey || event.metaKey || event.altKey) return;
    if (event.code === "Space") { event.preventDefault(); $("play").click(); }
    else if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
      event.preventDefault(); pause();
      setFrame(event.key === "Home" ? 0 : event.key === "End" ? replay.frames.length - 1 : at + (event.key === "ArrowLeft" ? -1 : 1));
    }
  });
  function animate(timestamp) {
    if (playing && replay) {
      if (clock !== null) elapsed += Math.min(timestamp - clock, 1000);
      clock = timestamp;
      const interval = 1000 / Number($("speed").value);
      if (elapsed >= interval) {
        const steps = Math.floor(elapsed / interval);
        elapsed %= interval;
        setFrame(at + steps);
      }
    }
    requestAnimationFrame(animate);
  }
  draw();
  requestAnimationFrame(animate);
})();
