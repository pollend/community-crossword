<script lang="ts">

  import { onDestroy, onMount } from "svelte";
  import {
    Application,
    Container,
    FederatedMouseEvent,
    Graphics,
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
    netParseReady,
    netParseSyncChunk,
    netParseSyncCursors,
    netSendCell,
    netSendViewRect,
    Value
  } from "./net";
  import { Quad } from "./quad";
  import { graphicDrawRect } from "./graphic";
  import { Debounce, Throttle } from "./timing";
  import { Direction, type Clue, MouseState } from "./types";
  import { GRID_CELL_PX, GRID_SIZE } from "./constants";
  import 'pixi.js/math-extras';

  interface CursorState {
    clientId: number;
    positions: Point[];
    t: number;
  };

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
  let players: number = $state(0);
  let disconnected: boolean = $state(false);
  let otherPlayerCursors: CursorState[] = [];
  // let mapImageUrl: string = $state('');
  // let mapRefreshKey: number = $state(0);

  let highlightSlotsVertical: number[] = $state([]);
  let highlightSlotHorizontal: number[] = $state([]);

  interface ClueSlots {
    pos: Point; // Position of the clue in grid cells
    hor: Clue | undefined;
    ver: Clue | undefined;
  }
  let clueSlots: (ClueSlots | undefined)[] = $state([]);

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
    // // Load initial map
    // refreshMap();
    
    // // Set up refresh interval (30 minutes = 1800000ms)
    // mapRefreshInterval = setInterval(refreshMap, 1800000);
    await app.init({ background: "#FFFFFF", resizeTo: frame });
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
      switch (msgid) {
        case MessageID.ready: {
          const readyPkt = netParseReady(view, offset);
          boardSize.set(readyPkt.board_width, readyPkt.board_height);
          topLeftPosition.set(
            (boardSize.x * GRID_CELL_PX) * Math.random(),
            (boardSize.y * GRID_CELL_PX) * Math.random(),
          );
          syncViewThrottle.trigger();
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
          players = msg.num_player;
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
    //let pingTimeout: number | undefined = undefined;
    //pingTimeout = setTimeout(() => {
    //  if (socket && socket.readyState === WebSocket.OPEN) {
    //    netSendPing(socket);
    //  }
    //}, 5000);

    socket.onclose = function () {
      disconnected = true;
    //  if (pingTimeout) {
    //    clearTimeout(pingTimeout);
    //    pingTimeout = undefined;
    //  }
    };

    socket.onopen = function () {
      //netSendViewRect(socket, 0, 0, app.screen.width, app.screen.height);
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

    document.addEventListener("keydown", (event) => {
      const value = charToValue(event.key);

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
    });

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

<div class="container mx-auto flex sm:w-full">
  <div class="flex-4 flex flex-col">
    <div class="mb-3 flex">
      <div class="w-10 flex m-auto items-center">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-person-arms-up" viewBox="0 0 16 16">
          <path d="M8 3a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3"/>
          <path d="m5.93 6.704-.846 8.451a.768.768 0 0 0 1.523.203l.81-4.865a.59.59 0 0 1 1.165 0l.81 4.865a.768.768 0 0 0 1.523-.203l-.845-8.451A1.5 1.5 0 0 1 10.5 5.5L13 2.284a.796.796 0 0 0-1.239-.998L9.634 3.84a.7.7 0 0 1-.33.235c-.23.074-.665.176-1.304.176-.64 0-1.074-.102-1.305-.176a.7.7 0 0 1-.329-.235L4.239 1.286a.796.796 0 0 0-1.24.998l2.5 3.216c.317.316.475.758.43 1.204Z"/>
        </svg>
        {players}
      </div>
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
    
    <div class="bg-sky-300 items-center justify-center text-black text-center mb-3 p-4">
      {#if selectionText !== ""}
        {selectionText}
      {:else}
        ???
      {/if}
    </div>
  
    <div class="aspect-square overflow-hidden border-black border-2" bind:this={frame}></div>
  </div>
  <div class="flex-3 text-black">
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

<style lang="postcss">
  @reference "tailwindcss";

  :global(body) {
    background: white;
  }
</style>
