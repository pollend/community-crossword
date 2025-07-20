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
    MessageID,
    netParseCell,
    netParseReady,
    netParseSyncChunk,
    netSendCell,
    netSendViewRect,
    Value,
  } from "./net";
  import { Quad } from "./quad";
  import { graphicDrawRect } from "./graphic";
  import { Throttle } from "./timing";
  import { Direction, type Clue, MouseState } from "./types";
  import { GRID_CELL_PX, GRID_SIZE } from "./constants";

  let frame: HTMLDivElement | undefined = $state.raw(undefined);
  let app: Application = new Application();
  let mainStage: Container = new Container();
  let socket: WebSocket | undefined = undefined;

  let mouse: MouseState = MouseState.None;
  let topLeftPosition = new Point(0, 0);
  let dragStartPosition = new Point(0, 0);
  let stageDragPosition = new Point(0, 0);
  let quads: Quad[] = [];

  let highlightSlotsVertical: number[] = $state([]);
  let highlightSlotHorizontal: number[] = $state([]);

  interface ClueSlots {
    pos: Point; // Position of the clue in grid cells
    hor: Clue | undefined;
    ver: Clue | undefined;
  }
  let clueSlots: (ClueSlots | undefined)[] = $state([]);
  let hightligthSlots: number[] = $state([]);

  const refreshQuads = new Throttle(100, () => {
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
    netSendViewRect(socket!, x, y, width, height);
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

  function getCell(x: number, y: number): number {
    const xx = Math.floor(x / GRID_SIZE);
    const yy = Math.floor(y / GRID_SIZE);
    const quad = quads.find((q) => xx == q.pos.x && yy == q.pos.y);
    if (!quad) {
      return 0; // or some default value
    }
    const cellX = x % GRID_SIZE;
    const cellY = y % GRID_SIZE;
    return quad.cells[cellY * GRID_SIZE + cellX];
  }

  function setGamePosition(x: number, y: number) {
    topLeftPosition.set(Math.max(0, x), Math.max(0, y));
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

  function getViewRect(): Rectangle {
    const size = viewSize();
    return new Rectangle(
      Math.max(topLeftPosition.x + stageDragPosition.x, 0),
      Math.max(topLeftPosition.y + stageDragPosition.y, 0),
      size.x,
      size.y,
    );
  }

  onDestroy(() => {
    app.destroy({ removeView: true }, { children: true, texture: true });
  });

  onMount(async () => {
    await app.init({ background: "#FFFFFF", resizeTo: frame });
    frame!.appendChild(app.canvas);

    socket = new WebSocket("ws://localhost:3010/ws");
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
          syncViewThrottle.trigger();
          break;
        }
        case MessageID.sync_input_cell: {
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
        case MessageID.sync_block: {
          const syncBlock = netParseSyncChunk(view, offset);
          const q = new Quad(
            new Point(syncBlock.x, syncBlock.y),
            syncBlock.clues,
            syncBlock.block,
          );
          quads.push(q);
          mainStage.addChild(q.container);
          refreshQuads.trigger();
          break;
        }
      }
    };

    socket.onclose = function () {};

    socket.onopen = function () {
      //netSendViewRect(socket, 0, 0, app.screen.width, app.screen.height);
    };
    // ----------------------------------------------------
    const graphicContainer = new Graphics();
    const backGraphics = new Graphics();
    app.stage.eventMode = "static";
    app.stage.addChild(graphicContainer);
    app.stage.addChild(mainStage);
    mainStage.addChild(backGraphics);

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
              const cell = getCell(selection.center.x + 1, selection.center.y);
              netSendCell(
                socket!,
                selection.center.x,
                selection.center.y,
                value,
              );
              if (cellToValue(cell) === Value.black) {
                selection.terminated = true;
                return; // do not allow to set value on black cell
              }
              selection.center.x += 1;
              break;
            }
            case Direction.Vertical: {
              const cell = getCell(selection.center.x, selection.center.y + 1);
              netSendCell(
                socket!,
                selection.center.x,
                selection.center.y,
                value,
              );
              if (cellToValue(cell) === Value.black) {
                selection.terminated = true;
                return; // do not allow to set value on black cell
              }
              selection.center.y += 1;
              break;
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
      mainStage.pivot.set(
        Math.max(0, topLeftPosition.x + stageDragPosition.x),
        Math.max(0, topLeftPosition.y + stageDragPosition.y),
      );
      graphicContainer.clear();
      graphicDrawRect(
        graphicContainer,
        new Rectangle(0, 0, size.x, size.y),
      ).fill(0xffffff);
      backGraphics.clear();
      const center = selection.center;
      hightligthSlots = [];
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

<div class="container mx-auto flex sm:w-full">
  <div class="flex-4 flex flex-col">
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
                on:click={() => {
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
                on:click={() => {
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
  </div>
</div>

<style lang="postcss">
  @reference "tailwindcss";

  :global(body) {
    background: white;
  }
</style>
