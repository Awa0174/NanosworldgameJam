// The Last Séance – HUD
// Zeigt nur an, was der Server schickt. Entscheidungen trifft ausschliesslich der Server.
//
// Von Lua (Client/HUD.lua):
//   Init(local_player_id, version)
//   State(json)            oeffentlicher Spielzustand
//   Say(text)              Madames Untertitel
//   Fx(kind, seat)         Effekt: chosen, aim, click, bang, ward, start, winner
//   Choice(json)           Auswahl oeffnen: { ritual, kind, options:[seat], seconds }
//   ChoiceEnd()            Auswahl schliessen
// An Lua:
//   Choose(ritual_id, value)
//   UiSound("hover" | "click")
//
// SICHERHEIT: Spielernamen und Texte werden IMMER per textContent gesetzt, nie per innerHTML.
// Sonst koennte ein praeparierter Spielername Code in fremden HUDs ausfuehren.

"use strict";

(function () {
	// Feste UI-Texte (Englisch). Madames Saetze kommen vom Server (Shared/Text.lua).
	const TEXT = {
		WAITING: "The table waits for more souls",
		COUNTDOWN: "The séance begins in",
		ENDED: "The séance is over",
		NEXT_IN: "A new séance in",
		SPECTATING: "You are watching from the shadows",
		CHOOSING: "The spirits are choosing…",
		YOU: "YOU",
		DEAD: "DEPARTED",
		CHOSEN_SMALL: "The spirits have chosen",
		START_SMALL: "The candles are lit",
		START_BIG: "THE SÉANCE BEGINS",
		WINNER_SMALL: "Leaves the séance alive",
		ODDS: (left) => `1 IN ${left}`,
		CHOOSE_TARGET: "Choose your target",
	};

	const MADAME_SHOW_MS = 6000;
	const URGENT_SECONDS = 3;

	// nanos stellt "Events" bereit. Im Browser (Vorschau) gibt es einen Ersatz, siehe preview.html.
	const Bus = window.Events;

	let localId = -1;
	let state = null;
	let choice = null;       // offene Auswahl oder null
	let madameTimer = null;
	let bannerTimer = null;
	const countdowns = new Map();   // Element -> Endzeit (performance.now() in ms)

	const $ = (id) => document.getElementById(id);

	// Lua-Tabellen ohne Eintraege kommen als {} statt [] an
	const asArray = (value) => Array.isArray(value) ? value : (value && typeof value === "object" ? Object.values(value) : []);

	function el(tag, className, text) {
		const node = document.createElement(tag);
		if (className) node.className = className;
		if (text !== undefined) node.textContent = text;
		return node;
	}

	function show(id, visible) {
		$(id).classList.toggle("hidden", !visible);
	}

	function restartAnimation(node, className) {
		node.classList.remove(className);
		void node.offsetWidth;   // Reflow erzwingen, damit die Animation neu startet
		node.classList.add(className);
	}

	// Spielt die CSS-Animation eines Elements erneut ab (auch wenn es schon sichtbar ist)
	function replay(node) {
		node.style.animation = "none";
		void node.offsetWidth;
		node.style.animation = "";
	}

	function mySeat() {
		if (!state) return null;
		return asArray(state.seats).find((s) => s.id === localId) || null;
	}

	function seatByIndex(index) {
		if (!state) return null;
		return asArray(state.seats).find((s) => s.seat === index) || null;
	}

	// ------------------------------------------------------------ Zeit (Docht + Zaehler)

	function startWick(timer) {
		const wick = $("wick");
		const fill = $("wick-fill");
		if (!timer || timer.remaining <= 0) {
			show("wick", false);
			return;
		}
		show("wick", true);
		const start = Math.max(0, Math.min(1, timer.remaining / timer.total));
		fill.style.transition = "none";
		fill.style.width = (start * 100) + "%";
		fill.classList.toggle("urgent", timer.remaining <= URGENT_SECONDS);
		void fill.offsetWidth;
		fill.style.transition = `width ${timer.remaining}s linear`;
		fill.style.width = "0%";

		clearTimeout(wick._urgent);
		const untilUrgent = (timer.remaining - URGENT_SECONDS) * 1000;
		if (untilUrgent > 0) {
			wick._urgent = setTimeout(() => fill.classList.add("urgent"), untilUrgent);
		}
	}

	// Mehrere Zaehler koennen gleichzeitig laufen (Lobby-Countdown, Auswahl-Ring)
	function startCountdown(seconds, node) {
		const running = countdowns.size > 0;
		countdowns.set(node, performance.now() + seconds * 1000);
		if (!running) requestAnimationFrame(tickCountdowns);
	}

	function stopCountdown(node) {
		countdowns.delete(node);
	}

	function tickCountdowns() {
		const now = performance.now();
		countdowns.forEach((ends, node) => {
			const left = Math.max(0, (ends - now) / 1000);
			node.textContent = Math.ceil(left).toString();
			node.classList.toggle("urgent", left <= URGENT_SECONDS);
			if (left <= 0) countdowns.delete(node);
		});
		if (countdowns.size > 0) requestAnimationFrame(tickCountdowns);
	}

	// ------------------------------------------------------------ Rendern

	function render() {
		if (!state) return;
		const me = mySeat();
		const phase = state.phase;

		renderRitual(phase, me);
		renderCylinder(phase);
		renderSeats(me);
		renderLobby(phase, me);

		// Sieger-Banner nur waehrend ENDED stehen lassen
		if (phase !== "ENDED" && $("banner").classList.contains("persist")) {
			show("banner", false);
			$("banner").classList.remove("persist");
		}
	}

	function renderRitual(phase, me) {
		const header = $("ritual");
		if (phase !== "PLAYING") {
			show("ritual", false);
			return;
		}
		const ritual = state.ritual;
		show("ritual", true);

		const instruction = $("ritual-instruction");
		if (ritual) {
			$("ritual-name").textContent = ritual.name;
			const myTurn = me && ritual.awaiting === me.seat;
			instruction.textContent = myTurn ? ritual.instruction_actor : ritual.instruction_others;
			instruction.classList.toggle("you", !!myTurn);
		} else {
			$("ritual-name").textContent = "The Séance";
			instruction.textContent = TEXT.CHOOSING;
			instruction.classList.remove("you");
		}
		startWick(state.timer);
	}

	function renderCylinder(phase) {
		const ritual = state.ritual;
		const data = ritual && ritual.id === "chamber" ? ritual.data : null;
		if (phase !== "PLAYING" || !data) {
			show("cylinder", false);
			return;
		}
		show("cylinder", true);

		const rotor = $("cyl-rotor");
		const total = data.chambers;
		const spent = data.spent;
		const ns = "http://www.w3.org/2000/svg";

		if (rotor.childElementCount !== total) {
			rotor.textContent = "";
			for (let i = 0; i < total; i++) {
				const angle = (i * 360 / total - 90) * Math.PI / 180;
				const c = document.createElementNS(ns, "circle");
				c.setAttribute("cx", (Math.cos(angle) * 30).toFixed(2));
				c.setAttribute("cy", (Math.sin(angle) * 30).toFixed(2));
				c.setAttribute("r", "11");
				rotor.appendChild(c);
			}
		}

		Array.from(rotor.children).forEach((c, i) => {
			c.setAttribute("class", "chamber" + (i < spent ? " spent" : "") + (i === spent ? " next" : ""));
		});
		// Naechste Kammer dreht sich nach oben
		rotor.style.transform = `rotate(${-spent * 360 / total}deg)`;

		const left = total - spent;
		const odds = $("cyl-odds");
		odds.textContent = TEXT.ODDS(left);
		odds.classList.toggle("danger", left <= 2);
	}

	function renderSeats(me) {
		const seats = asArray(state.seats);
		if (seats.length === 0) {
			show("circle", false);
			return;
		}
		show("circle", true);

		const list = $("seats");
		list.textContent = "";
		const target = state.ritual && state.ritual.data ? state.ritual.data.target : null;

		seats.slice().sort((a, b) => a.seat - b.seat).forEach((s) => {
			const item = el("li", "seat");
			item.dataset.seat = s.seat;
			if (!s.alive) item.classList.add("dead");
			if (s.seat === state.turn && state.phase === "PLAYING") item.classList.add("turn");
			if (me && s.seat === me.seat) item.classList.add("you");

			item.appendChild(el("span", "candle"));

			const name = el("span", "name", s.name);
			if (me && s.seat === me.seat) name.appendChild(el("span", "tag", TEXT.YOU));
			item.appendChild(name);

			item.appendChild(el("span", "mark", s.seat === target && s.alive ? "✛" : ""));

			const cards = el("span", "cards");
			for (let i = 0; i < Math.min(s.cards, 3); i++) cards.appendChild(el("i"));
			item.appendChild(cards);

			list.appendChild(item);
		});
	}

	function renderLobby(phase, me) {
		const text = $("lobby-text");
		const sub = $("lobby-sub");
		const counting = (phase === "COUNTDOWN" || phase === "ENDED") && state.timer;
		if (!counting) stopCountdown(sub);
		sub.classList.toggle("big", !!counting);
		sub.classList.remove("urgent");

		if (phase === "WAITING") {
			show("lobby", true);
			const lobby = state.lobby || {};
			const souls = (lobby.players || 0) + (lobby.bots || 0);
			text.textContent = TEXT.WAITING;
			sub.textContent = `${souls} / ${lobby.needed || 2}`;
		} else if (phase === "COUNTDOWN") {
			show("lobby", true);
			text.textContent = TEXT.COUNTDOWN;
			if (state.timer) startCountdown(state.timer.remaining, sub);
		} else if (phase === "ENDED") {
			// Der Sieger steht gross im Banner, hier nur der Countdown zur naechsten Runde
			show("lobby", true);
			text.textContent = TEXT.NEXT_IN;
			if (state.timer) startCountdown(state.timer.remaining, sub);
		} else if (phase === "PLAYING" && !me) {
			show("lobby", true);
			text.textContent = "";
			sub.textContent = TEXT.SPECTATING;
		} else {
			show("lobby", false);
		}
	}

	// ------------------------------------------------------------ Madame

	function say(text) {
		const box = $("madame");
		const line = $("madame-text");
		line.textContent = text;
		show("madame", true);
		box.classList.remove("fading");
		restartAnimation(line, "enter");
		clearTimeout(madameTimer);
		madameTimer = setTimeout(() => box.classList.add("fading"), MADAME_SHOW_MS);
	}

	// ------------------------------------------------------------ Effekte

	function word(text, kind) {
		const node = $("word");
		node.textContent = text;
		node.className = kind;
		restartAnimation(node, "show");
	}

	function flash(kind) {
		const node = $("flash");
		node.className = "";
		void node.offsetWidth;
		node.className = kind;
	}

	function banner(small, big, opts) {
		const node = $("banner");
		$("banner-small").textContent = small;
		$("banner-big").textContent = big;
		node.className = (opts && opts.danger) ? "danger" : "";
		clearTimeout(bannerTimer);
		if (opts && opts.persist) {
			node.classList.add("persist");
			replay(node);
			return;
		}
		replay(node);
		bannerTimer = setTimeout(() => show("banner", false), 2600);
	}

	function highlightSeat(index) {
		const item = document.querySelector(`.seat[data-seat="${Number(index)}"]`);
		if (item) restartAnimation(item, "chosen");
	}

	function fx(kind, seat) {
		const me = mySeat();
		switch (kind) {
			case "chosen":
				highlightSeat(seat);
				restartAnimation($("vignette"), "pulse");
				if (me && me.seat === seat) banner(TEXT.CHOSEN_SMALL, TEXT.YOU, { danger: true });
				break;
			case "aim":
				highlightSeat(seat);
				break;
			case "click":
				word("*click*", "click");
				break;
			case "bang":
				flash("bang");
				restartAnimation(document.body, "shake");
				word("BANG", "bang");
				break;
			case "ward":
				flash("ward");
				word("WARDED", "ward");
				break;
			case "start":
				banner(TEXT.START_SMALL, TEXT.START_BIG);
				break;
			case "winner": {
				const winner = seatByIndex(seat);
				if (winner) banner(TEXT.WINNER_SMALL, winner.name, { persist: true });
				break;
			}
		}
	}

	// ------------------------------------------------------------ Auswahl-Ring

	// Platz-Winkel (Grad, wie am Tisch) -> Position auf dem Bildschirm.
	// Der eigene Platz liegt unten, alle anderen so, wie man sie vom eigenen Stuhl aus sieht.
	function screenAngle(seatAngle, myAngle) {
		return (seatAngle - myAngle + 90) * Math.PI / 180;
	}

	function openChoice(data) {
		choice = data;
		show("banner", false);   // Der Ring sagt selbst, was zu tun ist
		const board = $("ring-board");
		board.querySelectorAll(".target").forEach((n) => n.remove());

		const me = mySeat();
		const myAngle = me ? me.angle : 90;
		const options = new Set(asArray(data.options).map(Number));
		const radius = 42; // Prozent der Brettgroesse

		asArray(state ? state.seats : []).forEach((s) => {
			const angle = screenAngle(s.angle, myAngle);
			const button = el("button", "target");
			button.style.left = (50 + Math.cos(angle) * radius) + "%";
			button.style.top = (50 + Math.sin(angle) * radius) + "%";
			button.appendChild(document.createTextNode(s.name));

			const isMe = me && s.seat === me.seat;
			const sub = isMe ? TEXT.YOU : (!s.alive ? TEXT.DEAD : "");
			if (sub) button.appendChild(el("span", "sub", sub));
			if (isMe) button.classList.add("self");
			if (!s.alive) button.classList.add("dead");

			const allowed = options.has(s.seat);
			button.disabled = !allowed;
			if (allowed) {
				button.addEventListener("mouseenter", () => Bus.Call("UiSound", "hover"));
				button.addEventListener("click", () => {
					if (!choice) return;
					Bus.Call("UiSound", "click");
					Bus.Call("Choose", choice.ritual, s.seat);
					closeChoice();
				});
			}
			board.appendChild(button);
		});

		$("ring-title").textContent = TEXT.CHOOSE_TARGET;
		show("ring", true);
		startCountdown(Number(data.seconds) || 0, $("ring-count"));
	}

	function closeChoice() {
		choice = null;
		show("ring", false);
		stopCountdown($("ring-count"));
	}

	// ------------------------------------------------------------ Events

	Bus.Subscribe("Init", (id) => {
		localId = Number(id);
		render();
	});

	Bus.Subscribe("State", (json) => {
		try {
			state = JSON.parse(json);
		} catch (e) {
			console.error("[DeathBox] Invalid state", e);
			return;
		}
		render();
	});

	Bus.Subscribe("Say", (text) => say(String(text)));
	Bus.Subscribe("Fx", (kind, seat) => fx(String(kind), Number(seat)));

	Bus.Subscribe("Choice", (json) => {
		try {
			openChoice(JSON.parse(json));
		} catch (e) {
			console.error("[DeathBox] Invalid choice", e);
		}
	});
	Bus.Subscribe("ChoiceEnd", closeChoice);
})();
