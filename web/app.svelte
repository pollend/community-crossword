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

  const SESSION_KEY = "a7407d0e-5821-4e07-8259-fcaa2228987a";

  interface CursorState {
    clientId: number;
    positions: Point[];
    t: number;
  };

  const profileSession = new ProfileSession();
  setContext("profile", profileSession)

  let frame: HTMLDivElement | undefined = $state.raw(undefined);
  let app: Application = new Application();
  let mainStage: Container = new Container();
  let socket: WebSocket | undefined = undefined;

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
    //Settings,
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

  // // Function to load/refresh the map image
  // function refreshMap() {
  //   mapRefreshKey = Date.now(); // Add timestamp to force cache refresh
  //   mapImageUrl = `${import.meta.env.VITE_APP_URL}/map.png?t=${mapRefreshKey}`;
  // }

  // Set up automatic map refresh every 30 minutes
  // let mapRefreshInterval: number;

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

    // prepare network ---------------------------------
    socket.onmessage = function (e) {
      const view = new DataView(e.data);
      let offset = 0;
      const msgid = view.getUint8(offset); // Read the message ID
      offset += 1;
      console.log("Received message ID:", msgid);
      switch (msgid) {
        case MessageID.ready: {
          const readyPkt = netParseReady(view, offset);
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
      {
        app.canvas.height = size.x

      }

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
  <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
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
      <div class="flex-auto">
        <div class="flex justify-between items-center mb-2">
          <span class="text-sm font-medium text-gray-700">Puzzle Progress</span>
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
  </div>
  <div class="flex-3 text-black block hidden md:block mt-10">
    <div class="flex">
      <div class="flex-1 m-3">
        <h1 class="text-2xl font-bold border-b-1 border-gray-200">Across</h1>
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
        <h2 class="text-2xl font-bold border-b-1 border-gray-200">Down</h2>
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

<Keyboard visible={showKeyboard} keypress={handleInput} backpress={backPress} close={() => showKeyboard = false}></Keyboard>
<Highscores isOpen={activePanel == ActivePanel.Highscores} close={() => activePanel = ActivePanel.None}/>
<Profile updateNick={(nick) => {
  netSendNick(socket!, nick);
}} displayStore={nickStore} isOpen={activePanel == ActivePanel.Profile} close={() => activePanel = ActivePanel.None}/>

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
