<script lang="ts">

  import { onDestroy, onMount, setContext } from "svelte";
  import {
    Application,
    Container,
    FederatedMouseEvent,
    Graphics,
    isMobile,
    Point,
    Rectangle,
  } from "pixi.js";

  import {
    cellToValue,
    charToValue,
    isBlocked,
    MessageID,
    netParseCell,
    netParseGameState,
    netParseNick,
    netParseReady,
    netParseSessionNegotiation,
    netParseSolveClue,
    netParseSyncChunk,
    netParseSyncCursors,
    netSendCell,
    netSendNick,
    netSendSessionNegotiation,
    netSendViewRect,
    Value
  } from "./net";
  import Keyboard from "./keyboard.svelte"
  import Highscores from "./highscores.svelte"
  import Profile from "./profile.svelte";
  import { Quad } from "./quad";
  import { graphicDrawRect } from "./graphic";
  import { Debounce, Throttle } from "./timing";
  import { Direction, type Clue, MouseState } from "./types";
  import { GRID_CELL_PX, GRID_SIZE } from "./constants";
  import 'pixi.js/math-extras';
  import { writable } from "svelte/store";
  import { ProfileSession } from "./profile";
    import { HighscoreTable } from "./highscoreTable";

  const SESSION_KEY = "a7407d0e-5821-4e07-8259-fcaa2228987a";
  interface CursorState {
    clientId: number;
    positions: Point[];
    t: number;
  };

  const profileSession = new ProfileSession();
  setContext("profile", profileSession)
  const globalHighscores = new HighscoreTable("global")
  setContext("globalHighscores", globalHighscores);

  let frame: HTMLDivElement | undefined = $state.raw(undefined);
  let app: Application = new Application();
  let mainStage: Container = new Container();
  let socket: WebSocket | undefined = undefined;
  setContext("socket", socket);

  let mouse: MouseState = MouseState.None;
  let cursorPos = new Point(0, 0);
  let topLeftPosition = new Point(0, 0);
  let dragStartPosition = new Point(0, 0);
  let stageDragPosition = new Point(0, 0);
  let quads: Quad[] = [];
  let progress: number = $state(0);
  let disconnected: boolean = $state(false);
  let otherPlayerCursors: CursorState[] = [];

  let showKeyboard: boolean = $state(false);
  let highlightSlotsVertical: number[] = $state([]);
  let highlightSlotHorizontal: number[] = $state([]);
  const nickStore = writable<string>('');

  const enum ActivePanel {
    None,
    Highscores,
    Profile
  }

  // Tab state
  let activePanel: ActivePanel = $state(ActivePanel.None);

  interface ClueSlots {
    pos: Point; // Position of the clue in grid cells
    hor: Clue | undefined;
    ver: Clue | undefined;
  }
  let clueSlots: (ClueSlots | undefined)[] = $state([]);

  function handleInput(c: string) {
    const value = charToValue(c);
    if (value !== undefined && selection.terminated === false) {
      if (selection.center) {
        const rec = getViewRectCells();
        rec.width -= 1;
        rec.height -= 1;
        if (rec.contains(selection.center.x, selection.center.y) === false)
          return; // do not allow to set value outside of view

        switch (selectionDir) {
          case Direction.Horizontal: {
            netSendCell(
              socket!,
              selection.center.x,
              selection.center.y,
              value,
            );
            while(true) {
              selection.center.x += 1;
              const cell = getCell(selection.center.x, selection.center.y);
              if(cell === undefined) {
                selection.terminated = true;
                return; // do not allow to set value outside of view
              }
              if (cellToValue(cell) === Value.black) {
                selection.center.x -= 1;
                selection.terminated = true;
                return; // do not allow to set value on black cell
              }
              if(isBlocked(cell)) {
                continue; // do not allow to set value on black cell
              }
              break;
            }
            break;
          }
          case Direction.Vertical: {
            netSendCell(
              socket!,
              selection.center.x,
              selection.center.y,
              value,
            );
            while(true) {
              selection.center.y += 1;
              const cell = getCell(selection.center.x, selection.center.y);
              if(cell === undefined) {
                selection.terminated = true;
                return; // do not allow to set value outside of view
              }
              if (cellToValue(cell) === Value.black) {
                selection.center.y -= 1;
                selection.terminated = true;
                return; // do not allow to set value on black cell
              }
              if(isBlocked(cell)) {
                continue; // do not allow to set value on black cell
              }
              break;
            }
          }
        }
      }
    }
  }

  function backPress() {

  }

  const refreshQuads = new Throttle(200, () => {
    const updated: Quad[] = [];
    const viewCells = getViewRectCells();
    const viewQuad = getViewRectQuad(viewCells);
    for (let i = 0; i < clueSlots.length; i++) {
      const clue = clueSlots[i];
      if (clue === undefined) continue;
      if (!viewCells.contains(clue.pos.x, clue.pos.y)) {
        clueSlots[i] = undefined;
      }
    }

    for (let x = viewQuad.left; x <= viewQuad.right; x++) {
      for (let y = viewQuad.top; y <= viewQuad.bottom; y++) {
        const foundQuadIdx = quads.findIndex(
          (q) => q.pos.x === x && q.pos.y === y,
        );
        if (foundQuadIdx !== -1) {
          const updateQuad = quads.splice(foundQuadIdx, 1)[0];
          updateQuad.clueNumbers.fill(-1);
          for (const clue of updateQuad.clues) {
            const clusePos = new Point(
              clue.x + updateQuad.pos.x * GRID_SIZE,
              clue.y + updateQuad.pos.y * GRID_SIZE,
            );
            if (!viewCells.contains(clusePos.x, clusePos.y)) continue;

            const emptyIdx = clueSlots.findIndex((cl) => cl === undefined);
            const targetIdx = clueSlots.findIndex((cl) => {
              if (cl === undefined) return false;
              return cl.pos.x === clusePos.x && cl.pos.y === clusePos.y;
            });
            let idx = 0;
            if (targetIdx >= 0) {
              clueSlots[targetIdx] = {
                pos: new Point(clusePos.x, clusePos.y),
                hor: clue.dir === 0 ? clue : clueSlots[targetIdx]?.hor,
                ver: clue.dir === 1 ? clue : clueSlots[targetIdx]?.ver,
              };
              idx = targetIdx;
            } else if (emptyIdx >= 0) {
              clueSlots[emptyIdx] = {
                pos: new Point(clusePos.x, clusePos.y),
                hor: clue.dir === 0 ? clue : undefined,
                ver: clue.dir === 1 ? clue : undefined,
              };
              idx = emptyIdx;
            } else {
              clueSlots.push({
                pos: new Point(clusePos.x, clusePos.y),
                hor: clue.dir === 0 ? clue : undefined,
                ver: clue.dir === 1 ? clue : undefined,
              });
              idx = clueSlots.length - 1;
            }
            updateQuad.clueNumbers[clue.y * GRID_SIZE + clue.x] = idx;
          }
          updateQuad.update();
          updated.push(updateQuad);
        }
      }
    }
    for (const q of quads) {
      q.destroy();
    }
    quads = updated;
  });

  const syncViewThrottle = new Throttle(100, () => {
    const view = getViewRect();
    const x = Math.floor(view.x / GRID_CELL_PX);
    const y = Math.floor(view.y / GRID_CELL_PX);
    const width = Math.floor((view.width + view.x) / GRID_CELL_PX) - x;
    const height = Math.floor((view.height + view.y) / GRID_CELL_PX) - y;
    netSendViewRect(socket!, x, y, width, height, cursorPos);
  });

  let boardSize = new Point(0, 0);

  let selectionDir: number= $state(Direction.Horizontal);
  let selection: {
    terminated: boolean;
    center: Point | undefined;
  } = {
    terminated: false,
    center: new Point(1, 1),
  };

  function getChunkAndIndex(
    x: number,
    y: number,
  ): { quad: Quad; index: number } | undefined {
    const xx = Math.floor(x / GRID_SIZE);
    const yy = Math.floor(y / GRID_SIZE);
    const quad = quads.find((q) => xx == q.pos.x && yy == q.pos.y);
    if (!quad) {
      return undefined; // or some default value
    }
    const cellX = x % GRID_SIZE;
    const cellY = y % GRID_SIZE;
    const index = cellY * GRID_SIZE + cellX;
    return { quad, index };
  }

  function getCell(x: number, y: number): number | undefined {
    const xx = Math.floor(x / GRID_SIZE);
    const yy = Math.floor(y / GRID_SIZE);
    const quad = quads.find((q) => xx == q.pos.x && yy == q.pos.y);
    if (!quad) {
      return undefined;
    }
    const cellX = x % GRID_SIZE;
    const cellY = y % GRID_SIZE;
    return quad.cells[cellY * GRID_SIZE + cellX];
  }

  function getViewRectCells(): Rectangle {
    const view = getViewRect();
    const x = Math.floor(view.x / GRID_CELL_PX);
    const y = Math.floor(view.y / GRID_CELL_PX);
    const width = Math.floor((view.x + view.width) / GRID_CELL_PX) - x + 1;
    const height = Math.floor((view.y + view.height) / GRID_CELL_PX) - y + 1;
    return new Rectangle(x, y, width, height);
  }

  function getViewRectQuad(rect: Rectangle): Rectangle {
    const x = Math.floor(rect.x / GRID_SIZE);
    const y = Math.floor(rect.y / GRID_SIZE);
    const width = Math.ceil((rect.width + rect.x) / GRID_SIZE) - x + 1;
    const height = Math.ceil((rect.height + rect.y) / GRID_SIZE) - y + 1;
    return new Rectangle(x, y, width, height);
  }

  function viewSize(): Point {
    const bound = frame!.getBoundingClientRect();
    return new Point(bound.width, bound.height);
  }

  // Function to draw a detailed cursor pointer
  function drawCursor(graphics: Graphics, x: number, y: number, clientId: number) {
    // Generate a consistent color based on client ID
    const hue = (clientId * 137.508) % 360; // Golden angle for good color distribution

    // Convert HSL to RGB for PixiJS
    const h = hue / 360;
    const s = 0.7;
    const l = 0.5;
    
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x1 = c * (1 - Math.abs((h * 6) % 2 - 1));
    const m = l - c / 2;
    
    let r = 0, g = 0, b = 0;
    if (h < 1/6) { r = c; g = x1; b = 0; }
    else if (h < 2/6) { r = x1; g = c; b = 0; }
    else if (h < 3/6) { r = 0; g = c; b = x1; }
    else if (h < 4/6) { r = 0; g = x1; b = c; }
    else if (h < 5/6) { r = x1; g = 0; b = c; }
    else { r = c; g = 0; b = x1; }
    
    const rgb = ((Math.round((r + m) * 255) << 16) | 
                 (Math.round((g + m) * 255) << 8) | 
                 Math.round((b + m) * 255));

    // Draw cursor pointer shape
    const points = [
      x, y,           // tip
      x, y + 16,      // bottom left
      x + 4, y + 12,  // left indent
      x + 8, y + 14,  // middle point
      x + 12, y + 10, // right point
      x + 8, y + 6    // right indent
    ];

    // Draw white outline/border
    graphics
      .poly(points)
      .fill(0xFFFFFF)
      .stroke({ width: 2, color: 0x000000 });

    // Draw colored fill (slightly smaller)
    const innerPoints = [
      x + 1, y + 1,
      x + 1, y + 14,
      x + 4, y + 11,
      x + 7, y + 12,
      x + 10, y + 9,
      x + 7, y + 6
    ];

    graphics
      .poly(innerPoints)
      .fill(rgb);

    // Add a small shadow effect
    const shadowPoints = [
      x + 2, y + 2,
      x + 2, y + 17,
      x + 5, y + 13,
      x + 9, y + 15,
      x + 13, y + 11,
      x + 9, y + 7
    ];

    graphics
      .poly(shadowPoints)
      .fill({
        color: 0x000000, 
        alpha: 0.2
      }); // Semi-transparent black shadow

    graphics
      .circle(x + 14, y + 2, 3)
      .fill(rgb)
      .stroke({ width: 1, color: 0xFFFFFF });
  }

  function setGamePosition(x: number, y: number) {
    const size = viewSize();
    topLeftPosition.set(
      Math.min(Math.max(0, x), boardSize.x * GRID_CELL_PX - size.x), 
      Math.min(Math.max(0, y), boardSize.y * GRID_CELL_PX - size.y));
  }

  function getViewRect(): Rectangle {
    const size = viewSize();
    return new Rectangle(
      Math.min(Math.max(topLeftPosition.x + stageDragPosition.x, 0), boardSize.x * GRID_CELL_PX - size.x),
      Math.min(Math.max(topLeftPosition.y + stageDragPosition.y, 0), boardSize.y * GRID_CELL_PX - size.y),
      size.x,
      size.y,
    );
  }

  onDestroy(() => {
    app.destroy({ removeView: true }, { children: true, texture: true });
  });

  onMount(async () => {
    await app.init({ background: "#FFFFFF", resizeTo: frame});
    frame!.appendChild(app.canvas);

    if(import.meta.env.VITE_WS_URL) {
      socket = new WebSocket(`${import.meta.env.VITE_WS_URL}`);
    } else {
      const protocol = window.location.protocol.includes('https') ? 'wss': 'ws'
      socket = new WebSocket(`${protocol}://${location.host}`);
    }
    socket.binaryType = "arraybuffer";
    socket.onmessage = function (e) {
      const view = new DataView(e.data);
      let offset = 0;
      const msgid = view.getUint8(offset); // Read the message ID
      offset += 1;
      switch (msgid) {
        case MessageID.ready: {
          const readyPkt = netParseReady(view, offset);
          globalHighscores.refresh();
          boardSize.set(readyPkt.board_width, readyPkt.board_height);
          topLeftPosition.set(
            (boardSize.x * GRID_CELL_PX) * Math.random(),
            (boardSize.y * GRID_CELL_PX) * Math.random(),
          );
          syncViewThrottle.trigger();
          netSendSessionNegotiation(socket!, window.localStorage.getItem(SESSION_KEY) || ""); // will send an empty key if not set
          break;
        }
        case MessageID.update_nick: {
          nickStore.set(netParseNick(view, offset));
          break;
        }
        case MessageID.session_negotiation: {
          let msg = netParseSessionNegotiation(view, offset);
          nickStore.set(msg.nick);
          profileSession.load(msg.session);
          window.localStorage.setItem(SESSION_KEY, msg.session);
          break;
        }
        case MessageID.input_or_sync_cell: {
          const cell = netParseCell(view, offset);
          const quadX = Math.floor(cell.x / GRID_SIZE);
          const quadY = Math.floor(cell.y / GRID_SIZE);
          const quad = quads.find((q) => quadX == q.pos.x && quadY == q.pos.y);
          if (quad) {
            const cellX = cell.x % GRID_SIZE;
            const cellY = cell.y % GRID_SIZE;
            const index = cellY * GRID_SIZE + cellX;
            quad.cells[index] = cell.value;
            quad.update();
          }
          break;
        }
        case MessageID.broadcast_game_state: {
          const msg = netParseGameState(view, offset);
          progress = msg.progress * 100.0;
          break;
        }
        case MessageID.sync_block: {
          const syncBlock = netParseSyncChunk(view, offset);
          const q = new Quad(
            new Point(syncBlock.x, syncBlock.y),
            syncBlock.clues,
            syncBlock.block,
          );
          quads.push(q);
          q.container.zIndex = 2;
          mainStage.addChild(q.container);
          refreshQuads.trigger();
          break;
        }
        case MessageID.solve_clue: {
          const net_solve = netParseSolveClue(view, offset);
          const qq: Quad[] = []
          if(net_solve.owner) {
            const cl = clueSlots.find(c => c && c.pos.x === net_solve.x && c.pos.y === net_solve.y);
            if(net_solve.dir === Direction.Horizontal && cl && cl.hor) {
              profileSession.push(net_solve.values, cl.hor.text);
            } else if(net_solve.dir === Direction.Vertical && cl && cl.ver) {
              profileSession.push(net_solve.values, cl.ver.text);
            }
          }
          for(let i = 0; i < net_solve.values.length; i++) {
            const xx = net_solve.x + (net_solve.dir === Direction.Horizontal ? i : 0);
            const yy = net_solve.y + (net_solve.dir === Direction.Vertical ? i : 0);
            const quadX = Math.floor(xx / GRID_SIZE);
            const quadY = Math.floor(yy / GRID_SIZE);
            const quad = quads.find((q) => quadX == q.pos.x && quadY == q.pos.y);
            if (quad) {
              const cellX = xx % GRID_SIZE;
              const cellY = yy % GRID_SIZE;
              const index = cellY * GRID_SIZE + cellX;
              quad.cells[index] = net_solve.values[i] | 0x80;
              if(qq.findIndex(q => q.pos.x === quad.pos.x && q.pos.y === quad.pos.y) < 0) {
                qq.push(quad);
              }
            }
          }
          for(const q of qq) {
            q.update();
          }
          break;
        }
        case MessageID.sync_cursors_delete: 
        case MessageID.sync_cursors: {
          const net_cursors = netParseSyncCursors(view, offset, msgid === MessageID.sync_cursors_delete);
          for(const id of net_cursors.del) {
            const idx = otherPlayerCursors.findIndex(c => c.clientId === id);
            if(idx >= 0) {
              otherPlayerCursors.splice(idx, 1);
            }
          }
          for(const net of net_cursors.new) {
            const existingCursor = otherPlayerCursors.find(c => c.clientId=== net.clientId);
            if(existingCursor) {
              existingCursor.positions.push(net.pos.clone());
              // Keep only the last few positions for pathfinding
              if(existingCursor.positions.length > 5) {
                existingCursor.positions = existingCursor.positions.slice(-5);
              }
            } else {
              const startPos = net.pos.clone();
              otherPlayerCursors.push({
                clientId: net.clientId,
                positions: [startPos],
                t: 0,
              });
            }
          }
          break;
        }
      }
    };

    socket.onclose = function () {
      disconnected = true;
    };

    socket.onopen = function () {

    };
    // ----------------------------------------------------
    const graphicContainer = new Graphics();
    const backGraphics = new Graphics();
    const frontGraphics = new Graphics();
    app.stage.eventMode = "static";

    app.stage.addChild(graphicContainer);
    app.stage.addChild(mainStage);
    mainStage.addChild(backGraphics);

    mainStage.addChild(frontGraphics)
    frontGraphics.zIndex = 10;
    mainStage.sortableChildren = true;

    document.addEventListener("keydown", (event) => handleInput(event.key));

    // dragging the board
    {
      function onBoardDragMove(event: FederatedMouseEvent) {
        mouse = MouseState.Dragging;
        stageDragPosition.set(
          dragStartPosition.x - event.global.x,
          dragStartPosition.y - event.global.y,
        );
        syncViewThrottle.trigger();
        refreshQuads.trigger();
      }
      function onBoardDragEnd(ev: FederatedMouseEvent) {
        app.stage.off("pointermove", onBoardDragMove);
        switch (mouse) {
          case MouseState.Dragging: {
            setGamePosition(
              topLeftPosition.x + stageDragPosition.x,
              topLeftPosition.y + stageDragPosition.y,
            );
            stageDragPosition.set(0, 0);
            syncViewThrottle.trigger();
            refreshQuads.trigger();
            break;
          }
          case MouseState.Clicking: {
            if(isMobile.any) {
              showKeyboard = true;
            }
            const pp = ev.getLocalPosition(mainStage);
            const center = new Point(
              Math.floor(pp.x / GRID_CELL_PX),
              Math.floor(pp.y / GRID_CELL_PX),
            );
            selection.terminated = false;
            if (selection.center) {
              if (
                center.x == selection.center.x &&
                center.y == selection.center.y
              ) {
                selectionDir =
                  selectionDir === Direction.Horizontal
                    ? Direction.Vertical
                    : Direction.Horizontal;
              } else {
                selection.center = center;
              }
            } else {
              selection.center = center;
            }
            break;
          }
        }

        mouse = MouseState.None;
      }
      const mouseDebonce = new Debounce(200, () => {
        syncViewThrottle.trigger(); 
      });
      app.stage.on("pointermove", (event) => {
        cursorPos.set(topLeftPosition.x + stageDragPosition.x + event.global.x, 
                      topLeftPosition.y + stageDragPosition.y + event.global.y);
        mouseDebonce.trigger();
      });
      app.stage.on("pointerupoutside", onBoardDragEnd);
      app.stage.on("pointerup", onBoardDragEnd);
      app.stage.on("pointerdown", (event) => {
        mouse = MouseState.Clicking;
        dragStartPosition = new Point(event.global.x, event.global.y);
        app.stage.on("pointermove", onBoardDragMove);
      });
    }

    app.ticker.add((_) => {
      const size = viewSize();
      app.canvas.height =frame!.clientWidth 

      const rect = getViewRect();
      mainStage.pivot.set(rect.x, rect.y);
      graphicContainer.clear();
      graphicDrawRect(
        graphicContainer,
        new Rectangle(0, 0, size.x, size.y),
      ).fill(0xffffff);
      backGraphics.clear();
      frontGraphics.clear();
      // render other player cursors
      {
        for (let i = otherPlayerCursors.length - 1; i >= 0; i--) {
          const cursor = otherPlayerCursors[i];

          let position = cursor.positions[0].clone();
          if (cursor.positions.length > 1) {
            cursor.t = Math.min(1, cursor.t + app.ticker.deltaTime * 0.1);
            position.set(cursor.positions[0].x + (cursor.positions[1].x - cursor.positions[0].x) * cursor.t,
            cursor.positions[0].y + (cursor.positions[1].y - cursor.positions[0].y) * cursor.t)
          }
          if(cursor.t >= 1) {
            cursor.t = 0;
            cursor.positions.shift();
          }
          
          // Draw the detailed cursor instead of a simple circle
          drawCursor(frontGraphics, position.x, position.y, cursor.clientId);
        }
      }

      const center = selection.center;
      if (center) {
        let x0 = center.x;
        let x1 = center.x;
        let y0 = center.y;
        let y1 = center.y;

        highlightSlotHorizontal = [];
        highlightSlotsVertical = [];
        const viewRect = getViewRectCells();
        while (x1 <= viewRect.right) {
          const cell = getChunkAndIndex(x1, center.y);
          if (
            cell === undefined ||
            cellToValue(cell.quad.cells[cell.index]) === Value.black
          ) {
            break;
          }
          const clueIdx = cell.quad.clueNumbers[cell.index];
          if (clueIdx >= 0 && clueSlots[clueIdx] && clueSlots[clueIdx].hor)
            highlightSlotHorizontal.push(clueIdx);
          if (x1 === boardSize.x - 1) break;
          x1 += 1;
        }
        while (x0 >= viewRect.left) {
          const cell = getChunkAndIndex(x0, center.y);
          if (
            cell === undefined ||
            cellToValue(cell.quad.cells[cell.index]) === Value.black
          ) {
            break;
          }
          const clueIdx = cell.quad.clueNumbers[cell.index];
          if (clueIdx >= 0 && clueSlots[clueIdx] && clueSlots[clueIdx].hor)
            highlightSlotHorizontal.push(clueIdx);
          if (x0 === 0) break;
          x0 -= 1;
        }
        while (y1 <= viewRect.bottom) {
          const cell = getChunkAndIndex(center.x, y1);
          if (
            cell === undefined ||
            cellToValue(cell.quad.cells[cell.index]) === Value.black
          )
            break;
          const clueIdx = cell.quad.clueNumbers[cell.index];
          if (clueIdx >= 0 && clueSlots[clueIdx] && clueSlots[clueIdx].ver)
            highlightSlotsVertical.push(clueIdx);
          if (y1 === boardSize.y - 1) break;
          y1 += 1;
        }
        while (y0 >= viewRect.top) {
          const cell = getChunkAndIndex(center.x, y0);
          if (
            cell === undefined ||
            cellToValue(cell.quad.cells[cell.index]) === Value.black
          )
            break;
          const clueIdx = cell.quad.clueNumbers[cell.index];
          if (clueIdx >= 0 && clueSlots[clueIdx] && clueSlots[clueIdx].ver)
            highlightSlotsVertical.push(clueIdx);
          if (y0 === 0) break;
          y0 -= 1;
        }
        switch (selectionDir) {
          case Direction.Horizontal: {
            backGraphics
              .rect(
                x0 * GRID_CELL_PX,
                center.y * GRID_CELL_PX,
                (x1 - x0) * GRID_CELL_PX,
                1 * GRID_CELL_PX,
              )
              .fill(0xa7d8ff);
            break;
          }
          case Direction.Vertical: {
            backGraphics
              .rect(
                center.x * GRID_CELL_PX,
                y0 * GRID_CELL_PX,
                GRID_CELL_PX,
                (y1 - y0) * GRID_CELL_PX,
              )
              .fill(0xa7d8ff);
            break;
          }
        }
        backGraphics
          .rect(
            center.x * GRID_CELL_PX,
            center.y * GRID_CELL_PX,
            GRID_CELL_PX,
            GRID_CELL_PX,
          )
          .fill(0xffda00);
      }

      // render grid
      {
        const startX = mainStage.pivot.x - (mainStage.pivot.x % GRID_CELL_PX);
        const startY = mainStage.pivot.y - (mainStage.pivot.y % GRID_CELL_PX);
        for (
          let x = 0 - GRID_CELL_PX;
          x < size.x + GRID_CELL_PX;
          x += GRID_CELL_PX
        ) {
          backGraphics
            .moveTo(x + startX, startY - GRID_CELL_PX)
            .lineTo(x + startX, size.y + startY + GRID_CELL_PX);
        }
        for (
          let y = -GRID_CELL_PX;
          y < size.y + GRID_CELL_PX;
          y += GRID_CELL_PX
        ) {
          backGraphics
            .moveTo(startX - GRID_CELL_PX, y + startY)
            .lineTo(size.x + startX + GRID_CELL_PX, y + startY);
        }
        backGraphics.stroke({ width: 1, color: 0xcccccc });
      }
    });
  });

  let selectionText = $derived.by(() => {
    if(selectionDir === Direction.Horizontal && highlightSlotHorizontal.length > 0) {
      const slot = clueSlots[highlightSlotHorizontal[highlightSlotHorizontal.length - 1]]
      if(slot && slot.hor) {
        return slot.hor.text;
      }
    } else if(selectionDir === Direction.Vertical) {
      const slot = clueSlots[highlightSlotsVertical[highlightSlotsVertical.length - 1]]
      if(slot && slot.ver) {
        return slot.ver.text;
      }
    }
    return "";
  });
</script>

{#if disconnected}
  <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-200">
    <div class="bg-white rounded-lg p-6 max-w-md mx-4 shadow-xl">
      <div class="text-center">
        <div class="text-6xl mb-4">🔌</div>
        <h2 class="text-2xl font-bold text-gray-800 mb-3">Connection Lost</h2>
        <p class="text-gray-600 mb-6">
          The connection to the server has been lost. Please check your internet connection and try again.
        </p>
        <button 
          class="bg-blue-500 hover:bg-blue-600 text-white font-semibold py-2 px-6 rounded-lg transition-colors"
          onclick={() => location.reload()}
        >
          Reconnect
        </button>
      </div>
    </div>
  </div>
{/if}

<div class="container mx-auto flex sm:w-full relative">
  <div class="top-0 right-0 z-30 flex space-x-1 absolute">
    <button class="px-2 py-2 font-medium transition-all duration-200 bg-blue-500" onclick={() => {activePanel = ActivePanel.Highscores}} >
      <div class="flex items-center space-x-2">
        <svg class="w-6 h-6" fill="white" viewBox="0 0 32 32">
          <path d="M 6,0 V 4 H 2 C 1.43333,4 0.95078,4.19961 0.55078,4.59961 0.18411,4.99961 0,5.48217 0,6.04883 V 16 c 0,1.1 0.38372,2.04962 1.15039,2.84961 C 1.91706,19.61628 2.86667,20 4,20 h 8 v 4 H 6 C 5.43333,24 4.95078,24.19961 4.55078,24.59961 4.18411,24.99961 4,25.48217 4,26.04883 V 28 H 28 V 26 C 28,25.46667 27.80039,24.99961 27.40039,24.59961 27.00039,24.19961 26.53333,24 26,24 h -6 v -4 h 8 c 1.1,0 2.03411,-0.38372 2.80078,-1.15039 C 31.60078,18.08295 32,17.13334 32,16 V 6 C 32,5.46667 31.80039,4.99961 31.40039,4.59961 31.00039,4.19961 30.53333,4 30,4 H 26 V 0 Z M 4,8 h 2 v 8 H 4 Z m 22,0 h 2 v 8 h -2 z" />
        </svg>
      </div>
    </button>
    <button class="px-2 py-2 font-medium transition-all duration-200 bg-blue-500" onclick={() => {activePanel = ActivePanel.Profile}}  >
      <div class="flex items-center space-x-2">
        <svg class="w-6 h-6" fill="white" viewBox="0 0 32 32">
          <path d="M 14,0 C 11.9333,1e-6 10.1833,0.717059 8.75,2.150391 7.2833,3.55039 6.5488,5.250003 6.5488,7.25 c 0,1.933332 0.7015,3.600002 2.1015,5 -1.6666,0.7 -3.1841,1.700002 -4.5507,3 C 1.3662,17.883333 0,21.082947 0,24.84961 0.033,26.849608 1.3996,28.533726 4.0996,29.900391 6.8329,31.30039 10.1333,32 14,32 17.9,32 21.2003,31.30039 23.9003,29.900391 26.6337,28.533726 28,26.849608 28,24.84961 28,21.082947 26.6337,17.883333 23.9003,15.25 22.5337,13.950002 21.0162,12.95 19.3496,12.25 20.7829,10.850002 21.5,9.183332 21.5,7.25 21.5,5.250003 20.7654,3.55039 19.2988,2.150391 17.8655,0.717059 16.1,0 14,0 Z" />
        </svg>
      </div>
    </button>
   
<!--
    <button class="px-2 py-2 font-medium transition-all duration-200 bg-blue-500" onclick={() => {activePanel = ActivePanel.Settings}} >
      <div class="flex items-center space-x-2">
        <svg class="w-6 h-6" fill="white" viewBox="0 0 32 32">
          <path d="m 16,0 c -2.23333,0 -4.30118,0.40118 -6.20117,1.20118 -0.3,0.13333 -0.51706,0.34843 -0.65039,0.64843 -0.13334,0.3 -0.13334,0.6004 0,0.90039 l 1.30078,3.09961 c -0.6,0.33334 -1.18334,0.73451 -1.75,1.20118 L 6.34961,4.70118 C 6.11627,4.46784 5.83333,4.34961 5.5,4.34961 c -0.3,0 -0.56745,0.11823 -0.80078,0.35157 -1.6,1.56666 -2.78412,3.31667 -3.55078,5.25 -0.13334,0.3 -0.13334,0.59843 0,0.89843 L 1.79883,11.5 4.89844,12.75 4.5,14.80079 H 1.19922 c -0.33334,0 -0.61628,0.11627 -0.84961,0.34961 C 0.11627,15.38373 0,15.66667 0,16 c 0,2.23334 0.39922,4.30118 1.19922,6.20118 l 0.65039,0.64843 c 0.3,0.13334 0.60039,0.13334 0.90039,0 l 3.09961,-1.29882 1.19922,1.75 -2.34961,2.34961 C 4.46588,25.88373 4.34961,26.16667 4.34961,26.5 c 0,0.33334 0.11627,0.61628 0.34961,0.84961 1.56666,1.56667 3.31666,2.73334 5.25,3.5 0.3,0.13334 0.60039,0.13334 0.90039,0 L 11.5,30.20118 12.75,27.1504 14.79883,27.5 v 3.30079 c 0,0.33333 0.11627,0.61627 0.34961,0.84961 C 15.38177,31.88373 15.66666,32 16,32 c 2.23333,0 4.29922,-0.39921 6.19922,-1.19921 l 0.65039,-0.65039 c 0.13333,-0.3 0.13333,-0.6004 0,-0.9004 L 21.54883,26.20118 23.29883,25 25.64844,27.34961 26.5,27.6504 27.29883,27.34961 c 1.59999,-1.59999 2.78411,-3.35 3.55078,-5.25 0.13333,-0.3 0.13333,-0.59843 0,-0.89843 L 30.19922,20.55079 27.09961,19.25 27.5,17.20118 h 3.29883 c 0.33333,0 0.61627,-0.11823 0.84961,-0.35157 C 31.88177,16.61628 32,16.33334 32,16 32,13.76667 31.59882,11.70078 30.79883,9.80079 L 30.14844,9.1504 c -0.3,-0.13334 -0.59844,-0.13334 -0.89844,0 L 26.14844,10.45118 25,8.70118 27.29883,6.34961 27.64844,5.55079 c 0,-0.33334 -0.11628,-0.61628 -0.34961,-0.84961 l -1.65039,-1.5 C 24.5151,2.33451 23.33294,1.6504 22.09961,1.1504 c -0.33334,-0.13334 -0.65118,-0.13334 -0.95117,0 -0.3,0.13333 -0.49961,0.35039 -0.59961,0.65039 L 19.25,4.9004 17.19922,4.5 V 1.20118 c 0,-0.33334 -0.11628,-0.61823 -0.34961,-0.85157 C 16.61627,0.11628 16.33333,0 16,0 Z m 0,8.25 c 2.13333,0 3.96667,0.75001 5.5,2.25 1.5,1.53334 2.25,3.36667 2.25,5.5 0,2.13334 -0.75,3.96667 -2.25,5.5 C 19.96667,23 18.13333,23.75 16,23.75 13.86667,23.75 12.03333,23 10.5,21.5 9,19.96667 8.25,18.13334 8.25,16 8.25,13.86667 9,12.03334 10.5,10.5 12.03333,9.00001 13.86667,8.25 16,8.25 Z m 0,3.9004 c -1.06667,0 -1.98334,0.36627 -2.75,1.0996 -0.73334,0.76667 -1.10156,1.68334 -1.10156,2.75 0,1.06667 0.36822,1.98334 1.10156,2.75 0.76666,0.76667 1.68333,1.1504 2.75,1.1504 1.06666,0 1.98333,-0.38373 2.75,-1.1504 0.76666,-0.76666 1.14844,-1.68333 1.14844,-2.75 0,-1.06666 -0.38178,-1.98333 -1.14844,-2.75 C 17.98333,12.51667 17.06666,12.1504 16,12.1504 Z" />
        </svg>
      </div>
    </button> -->
  </div>

  <div class="flex-4 flex flex-col overflow-hidden mt-15">
    <div class="mb-3 flex">
      <!-- community-crossword -->
      <div class="flex-auto">
        <div class="flex justify-between items-center mb-2">
          <span class="text-sm font-medium text-gray-700 font-headline">Global Progress</span>
          <span class="text-sm font-medium text-gray-700">{Math.round(progress)}%</span>
        </div>
        <div class="w-full bg-gray-200 h-3">
          <div 
            class="bg-green-500 h-3 transition-all duration-300 ease-out"
            style="width: {progress}%"
          ></div>
        </div>
      </div>
    </div>
    <div class="aspect-square border-black border-2" bind:this={frame}></div>
    <div class="bg-sky-300 items-center justify-center text-black text-center mb-3 p-4">
      {#if selectionText !== ""}
        {selectionText}
      {:else}
        ???
      {/if}
    </div>

    <ins class="adsbygoogle"
      style="display:inline-block;width:728px;height:90px"
      data-ad-client="ca-pub-9118570546154001"
      data-ad-slot="5528739759"></ins>
    <script>
      (adsbygoogle = window.adsbygoogle || []).push({});
    </script>
  </div>
  <div class="flex-3 text-black block hidden md:block mt-10">
    <div class="flex">
      <div class="flex-1 m-3">
        <h1 class="text-2xl font-bold border-b-1 border-gray-200 font-headline">Across</h1>
        <div class="overflow-y-auto h-200">
          {#each clueSlots as clue, i}
            {#if clue && clue.hor}
              {@const verticalSelection = highlightSlotHorizontal.findIndex((k) => i === k) >= 0}
              <div
                class={{
                  "border-l-10 border-transparent pl-3 py-1 cursor-pointer my-2 select-none": true,
                  "!border-sky-300": selectionDir === Direction.Vertical && verticalSelection,
                  "bg-sky-300": selectionDir === Direction.Horizontal && verticalSelection,
                }}
                onclick={() => {
                   (selection.center = clue.pos) && (selectionDir = Direction.Horizontal);
                }}
              >
                {i + 1}. {clue.hor.text}
              </div>
            {/if}
          {/each}
        </div>
      </div>
      <div class="flex-1 m-3">
        <h2 class="text-2xl font-bold border-b-1 border-gray-200 font-headline">Down</h2>
        <div class="overflow-y-auto h-200">
          {#each clueSlots as clue, i}
            {#if clue && clue.ver}
              {@const horizontalSelection = highlightSlotsVertical.findIndex((k) => i === k)}
              <div
                class={{
                  "border-l-10 border-transparent pl-3 py-1 cursor-pointer my-2 select-none" : true,
                  "!border-sky-300": selectionDir === Direction.Horizontal && horizontalSelection >= 0,
                  "bg-sky-300": selectionDir === Direction.Vertical && horizontalSelection >= 0,
                }}
                onclick={() => {
                   (selection.center = clue.pos) && (selectionDir = Direction.Vertical);
                }}
              >
                {i + 1}. {clue.ver.text}
              </div>
            {/if}
          {/each}
        </div>
      </div>
    </div>
    
    <!-- <div class="m-3">
      <h3 class="text-xl font-bold border-b-1 border-gray-200 mb-2">Puzzle Map</h3>
      <div class="relative bg-gray-100 rounded-lg p-2">
        {#if mapImageUrl}
          <img 
            src={mapImageUrl} 
            alt="Puzzle Progress Map" 
            style="image-rendering: pixelated;image-rendering: -moz-crisp-edges; image-rendering: -webkit-optimize-contrast;"
            class="w-full h-auto max-h-48 object-contain rounded"
            loading="lazy"
          />
        {:else}
          <div class="w-full h-24 bg-gray-200 rounded flex items-center justify-center text-gray-500">
            Loading map...
          </div>
        {/if}
      </div>
    </div> -->
  </div>

</div>

<Keyboard visible={showKeyboard} keypress={handleInput} close={() => showKeyboard = false}></Keyboard>
<Highscores isOpen={activePanel == ActivePanel.Highscores} close={() => activePanel = ActivePanel.None}/>
<Profile updateNick={(nick) => {
  netSendNick(socket!, nick);
}} displayStore={nickStore} isOpen={activePanel == ActivePanel.Profile} close={() => activePanel = ActivePanel.None}/>

<!-- Buy Me a Coffee - Floating Button -->
<div class="fixed bottom-6 right-6 z-30">
  <!-- svelte-ignore a11y_consider_explicit_label -->
  <a 
    href="https://buymeacoffee.com/mpollind" 
    target="_blank" 
    rel="noopener noreferrer"
    class="group flex items-center justify-center w-12 h-12 bg-blue-500 hover:bg-blue-300 rounded-full shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-110"
    title="Buy me a coffee ☕"
  >
    <svg class="w-8 h-8" width="884" height="1279" viewBox="0 0 884 1279" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M791.109 297.518L790.231 297.002L788.201 296.383C789.018 297.072 790.04 297.472 791.109 297.518V297.518Z" fill="#0D0C22"/>
      <path d="M803.896 388.891L802.916 389.166L803.896 388.891Z" fill="#0D0C22"/>
      <path d="M791.484 297.377C791.359 297.361 791.237 297.332 791.118 297.29C791.111 297.371 791.111 297.453 791.118 297.534C791.252 297.516 791.379 297.462 791.484 297.377V297.377Z" fill="#0D0C22"/>
      <path d="M791.113 297.529H791.244V297.447L791.113 297.529Z" fill="#0D0C22"/>
      <path d="M803.111 388.726L804.591 387.883L805.142 387.573L805.641 387.04C804.702 387.444 803.846 388.016 803.111 388.726V388.726Z" fill="#0D0C22"/>
      <path d="M793.669 299.515L792.223 298.138L791.243 297.605C791.77 298.535 792.641 299.221 793.669 299.515V299.515Z" fill="#0D0C22"/>
      <path d="M430.019 1186.18C428.864 1186.68 427.852 1187.46 427.076 1188.45L427.988 1187.87C428.608 1187.3 429.485 1186.63 430.019 1186.18Z" fill="#0D0C22"/>
      <path d="M641.187 1144.63C641.187 1143.33 640.551 1143.57 640.705 1148.21C640.705 1147.84 640.86 1147.46 640.929 1147.1C641.015 1146.27 641.084 1145.46 641.187 1144.63Z" fill="#0D0C22"/>
      <path d="M619.284 1186.18C618.129 1186.68 617.118 1187.46 616.342 1188.45L617.254 1187.87C617.873 1187.3 618.751 1186.63 619.284 1186.18Z" fill="#0D0C22"/>
      <path d="M281.304 1196.06C280.427 1195.3 279.354 1194.8 278.207 1194.61C279.136 1195.06 280.065 1195.51 280.684 1195.85L281.304 1196.06Z" fill="#0D0C22"/>
      <path d="M247.841 1164.01C247.704 1162.66 247.288 1161.35 246.619 1160.16C247.093 1161.39 247.489 1162.66 247.806 1163.94L247.841 1164.01Z" fill="#0D0C22"/>
      <path d="M472.623 590.836C426.682 610.503 374.546 632.802 306.976 632.802C278.71 632.746 250.58 628.868 223.353 621.274L270.086 1101.08C271.74 1121.13 280.876 1139.83 295.679 1153.46C310.482 1167.09 329.87 1174.65 349.992 1174.65C349.992 1174.65 416.254 1178.09 438.365 1178.09C462.161 1178.09 533.516 1174.65 533.516 1174.65C553.636 1174.65 573.019 1167.08 587.819 1153.45C602.619 1139.82 611.752 1121.13 613.406 1101.08L663.459 570.876C641.091 563.237 618.516 558.161 593.068 558.161C549.054 558.144 513.591 573.303 472.623 590.836Z" fill="#FFDD00"/>
      <path d="M78.6885 386.132L79.4799 386.872L79.9962 387.182C79.5987 386.787 79.1603 386.435 78.6885 386.132V386.132Z" fill="#0D0C22"/>
      <path d="M879.567 341.849L872.53 306.352C866.215 274.503 851.882 244.409 819.19 232.898C808.711 229.215 796.821 227.633 788.786 220.01C780.751 212.388 778.376 200.55 776.518 189.572C773.076 169.423 769.842 149.257 766.314 129.143C763.269 111.85 760.86 92.4243 752.928 76.56C742.604 55.2584 721.182 42.8009 699.88 34.559C688.965 30.4844 677.826 27.0375 666.517 24.2352C613.297 10.1947 557.342 5.03277 502.591 2.09047C436.875 -1.53577 370.983 -0.443234 305.422 5.35968C256.625 9.79894 205.229 15.1674 158.858 32.0469C141.91 38.224 124.445 45.6399 111.558 58.7341C95.7448 74.8221 90.5829 99.7026 102.128 119.765C110.336 134.012 124.239 144.078 138.985 150.737C158.192 159.317 178.251 165.846 198.829 170.215C256.126 182.879 315.471 187.851 374.007 189.968C438.887 192.586 503.87 190.464 568.44 183.618C584.408 181.863 600.347 179.758 616.257 177.304C634.995 174.43 647.022 149.928 641.499 132.859C634.891 112.453 617.134 104.538 597.055 107.618C594.095 108.082 591.153 108.512 588.193 108.942L586.06 109.252C579.257 110.113 572.455 110.915 565.653 111.661C551.601 113.175 537.515 114.414 523.394 115.378C491.768 117.58 460.057 118.595 428.363 118.647C397.219 118.647 366.058 117.769 334.983 115.722C320.805 114.793 306.661 113.611 292.552 112.177C286.134 111.506 279.733 110.801 273.333 110.009L267.241 109.235L265.917 109.046L259.602 108.134C246.697 106.189 233.792 103.953 221.025 101.251C219.737 100.965 218.584 100.249 217.758 99.2193C216.932 98.1901 216.482 96.9099 216.482 95.5903C216.482 94.2706 216.932 92.9904 217.758 91.9612C218.584 90.9319 219.737 90.2152 221.025 89.9293H221.266C232.33 87.5721 243.479 85.5589 254.663 83.8038C258.392 83.2188 262.131 82.6453 265.882 82.0832H265.985C272.988 81.6186 280.026 80.3625 286.994 79.5366C347.624 73.2302 408.614 71.0801 469.538 73.1014C499.115 73.9618 528.676 75.6996 558.116 78.6935C564.448 79.3474 570.746 80.0357 577.043 80.8099C579.452 81.1025 581.878 81.4465 584.305 81.7391L589.191 82.4445C603.438 84.5667 617.61 87.1419 631.708 90.1703C652.597 94.7128 679.422 96.1925 688.713 119.077C691.673 126.338 693.015 134.408 694.649 142.03L696.731 151.752C696.786 151.926 696.826 152.105 696.852 152.285C701.773 175.227 706.7 198.169 711.632 221.111C711.994 222.806 712.002 224.557 711.657 226.255C711.312 227.954 710.621 229.562 709.626 230.982C708.632 232.401 707.355 233.6 705.877 234.504C704.398 235.408 702.75 235.997 701.033 236.236H700.895L697.884 236.649L694.908 237.044C685.478 238.272 676.038 239.419 666.586 240.486C647.968 242.608 629.322 244.443 610.648 245.992C573.539 249.077 536.356 251.102 499.098 252.066C480.114 252.57 461.135 252.806 442.162 252.771C366.643 252.712 291.189 248.322 216.173 239.625C208.051 238.662 199.93 237.629 191.808 236.58C198.106 237.389 187.231 235.96 185.029 235.651C179.867 234.928 174.705 234.177 169.543 233.397C152.216 230.798 134.993 227.598 117.7 224.793C96.7944 221.352 76.8005 223.073 57.8906 233.397C42.3685 241.891 29.8055 254.916 21.8776 270.735C13.7217 287.597 11.2956 305.956 7.64786 324.075C4.00009 342.193 -1.67805 361.688 0.472751 380.288C5.10128 420.431 33.165 453.054 73.5313 460.35C111.506 467.232 149.687 472.807 187.971 477.556C338.361 495.975 490.294 498.178 641.155 484.129C653.44 482.982 665.708 481.732 677.959 480.378C681.786 479.958 685.658 480.398 689.292 481.668C692.926 482.938 696.23 485.005 698.962 487.717C701.694 490.429 703.784 493.718 705.08 497.342C706.377 500.967 706.846 504.836 706.453 508.665L702.633 545.797C694.936 620.828 687.239 695.854 679.542 770.874C671.513 849.657 663.431 928.434 655.298 1007.2C653.004 1029.39 650.71 1051.57 648.416 1073.74C646.213 1095.58 645.904 1118.1 641.757 1139.68C635.218 1173.61 612.248 1194.45 578.73 1202.07C548.022 1209.06 516.652 1212.73 485.161 1213.01C450.249 1213.2 415.355 1211.65 380.443 1211.84C343.173 1212.05 297.525 1208.61 268.756 1180.87C243.479 1156.51 239.986 1118.36 236.545 1085.37C231.957 1041.7 227.409 998.039 222.9 954.381L197.607 711.615L181.244 554.538C180.968 551.94 180.693 549.376 180.435 546.76C178.473 528.023 165.207 509.681 144.301 510.627C126.407 511.418 106.069 526.629 108.168 546.76L120.298 663.214L145.385 904.104C152.532 972.528 159.661 1040.96 166.773 1109.41C168.15 1122.52 169.44 1135.67 170.885 1148.78C178.749 1220.43 233.465 1259.04 301.224 1269.91C340.799 1276.28 381.337 1277.59 421.497 1278.24C472.979 1279.07 524.977 1281.05 575.615 1271.72C650.653 1257.95 706.952 1207.85 714.987 1130.13C717.282 1107.69 719.576 1085.25 721.87 1062.8C729.498 988.559 737.115 914.313 744.72 840.061L769.601 597.451L781.009 486.263C781.577 480.749 783.905 475.565 787.649 471.478C791.392 467.391 796.352 464.617 801.794 463.567C823.25 459.386 843.761 452.245 859.023 435.916C883.318 409.918 888.153 376.021 879.567 341.849ZM72.4301 365.835C72.757 365.68 72.1548 368.484 71.8967 369.792C71.8451 367.813 71.9483 366.058 72.4301 365.835ZM74.5121 381.94C74.6842 381.819 75.2003 382.508 75.7337 383.334C74.925 382.576 74.4089 382.009 74.4949 381.94H74.5121ZM76.5597 384.641C77.2996 385.897 77.6953 386.689 76.5597 384.641V384.641ZM80.672 387.979H80.7752C80.7752 388.1 80.9645 388.22 81.0333 388.341C80.9192 388.208 80.7925 388.087 80.6548 387.979H80.672ZM800.796 382.989C793.088 390.319 781.473 393.726 769.996 395.43C641.292 414.529 510.713 424.199 380.597 419.932C287.476 416.749 195.336 406.407 103.144 393.382C94.1102 392.109 84.3197 390.457 78.1082 383.798C66.4078 371.237 72.1548 345.944 75.2003 330.768C77.9878 316.865 83.3218 298.334 99.8572 296.355C125.667 293.327 155.64 304.218 181.175 308.09C211.917 312.781 242.774 316.538 273.745 319.36C405.925 331.405 540.325 329.529 671.92 311.91C695.905 308.686 719.805 304.941 743.619 300.674C764.835 296.871 788.356 289.731 801.175 311.703C809.967 326.673 811.137 346.701 809.778 363.615C809.359 370.984 806.139 377.915 800.779 382.989H800.796Z" fill="#0D0C22"/>
    </svg>
  </a>
</div>

<!-- Sessions Panel 
{#if showSessionsPanel}
  <div 
    class="fixed top-0 right-0 h-full w-96 bg-white shadow-2xl transform transition-transform duration-300 ease-in-out z-50"
  >
    <div class="flex items-center justify-between p-6 border-b border-gray-200 bg-gradient-to-r from-blue-600 to-blue-700 text-white">
      <h2 class="text-2xl font-bold">👥 Active Sessions</h2>
      <button 
        onclick={() => showSessionsPanel = false}
        class="text-white hover:text-gray-200 transition-colors duration-200"
        aria-label="Close sessions panel"
      >
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>

    <div class="flex-1 overflow-y-auto p-6">
      <div class="text-center text-gray-500 mt-8">
        <svg class="w-16 h-16 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
        <p class="text-lg font-medium">Sessions Feature Coming Soon!</p>
        <p class="text-sm">This will show active game sessions and allow you to join different rooms.</p>
      </div>
    </div>

    <div class="border-t border-gray-200 p-4 bg-gray-50">
      <div class="flex items-center justify-between text-sm text-gray-600">
        <span>Current session: Room #{Math.floor(Math.random() * 1000)}</span>
        <span>{players} player{players !== 1 ? 's' : ''} online</span>
      </div>
    </div>
  </div>
{/if} -->

<!-- Highscores Panel -->

<style lang="postcss">
  @reference "tailwindcss";

  :global(body) {
    background: white;
  }
</style>
