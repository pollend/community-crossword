import {
  Application,
  FederatedMouseEvent,
  Graphics,
  Point,
  Rectangle,
} from "pixi.js";
import { MessageID, netParseSyncBlock, netSendViewRect } from "./net";
import "@pixi/math-extras";
import { Throttle } from "./timing";
import global, {
  expect,
  GRID_CELL_PX,
  PLAYFIELD_PADDING,
  SIDEBAR_PADDING,
} from "./state";
import { graphicDrawRect } from "./graphic";
import { GraphicQuad } from "./graphic_quad";

function isRectangleEqual(a: Rectangle, b: Rectangle): boolean {
  return (
    a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height
  );
}

const lastScreen = new Rectangle();
export const app = new Application();

(async () => {
  await app.init({ background: "#FFFFFF", resizeTo: window });
  document.getElementById("pixi-container")!.appendChild(app.canvas);

  global.socket = new WebSocket("ws://localhost:3010/ws");
  global.socket.binaryType = "arraybuffer";

  const mainGui = new Graphics();
  app.stage.eventMode = "static";
  app.stage.addChild(mainGui);

  global.mainContainer.eventMode = "static";
  app.stage.addChild(global.mainContainer);
  app.stage.addChild(global.sideBarContainer);

  // dragging the board
  {
    function onBoardDragMove(event: FederatedMouseEvent) {
      global.stageDragPosition.set(
        global.dragStartPosition.x - event.global.x,
        global.dragStartPosition.y - event.global.y,
      );
      syncViewThrottle.trigger();
    }
    function onBoardDragEnd(_: FederatedMouseEvent) {
      app.stage.off("pointermove", onBoardDragMove);
      global.setGamePosition(
        global.topLeftPosition.x + global.stageDragPosition.x,
        global.topLeftPosition.y + global.stageDragPosition.y,
      );
      global.stageDragPosition.set(0, 0);
      syncViewThrottle.trigger();
    }
    app.stage.on("pointerupoutside", onBoardDragEnd);
    app.stage.on("pointerup", onBoardDragEnd);
    global.mainContainer.on("pointerdown", (event) => {
      global.dragStartPosition = new Point(event.global.x, event.global.y);
      app.stage.on("pointermove", onBoardDragMove);
    });
  }
  const g_grid = new Graphics();
  global.playFieldContainer.addChild(g_grid);

  const g_mask = new Graphics();
  const g_container = new Graphics();
  global.mainContainer.mask = g_mask;
  global.mainContainer.addChild(g_mask);
  global.mainContainer.addChild(g_container);
  global.mainContainer.addChild(global.playFieldContainer);

  const syncViewThrottle = new Throttle(500, () => {
    const view = global.getViewRect();
    netSendViewRect(
      expect(global.socket),
      view.x / GRID_CELL_PX,
      view.y / GRID_CELL_PX,
      view.width / GRID_CELL_PX,
      view.height / GRID_CELL_PX,
    );
  });

  global.socket.onmessage = function (e) {
    const view = new DataView(e.data);
    let offset = 0;
    const msgid = view.getUint8(offset); // Read the message ID
    offset += 1;
    console.log("Received message ID:", msgid);
    switch (msgid) {
      case MessageID.ready: {
        syncViewThrottle.trigger();
        break;
      }
      case MessageID.sync_block: {
        const syncBlock = netParseSyncBlock(view, offset);
        const key = `${syncBlock.x}-${syncBlock.y}`
        if(global.quads[key] == undefined) {
          global.quads[key] = new GraphicQuad();
          global.playFieldContainer.addChild(global.quads[key].container);
        }
        global.quads[key].update(
          new Point(syncBlock.x, syncBlock.y),
          syncBlock.block,
        );
        break;
      }
    }
  };

  global.socket.onclose = function () {};

  global.socket.onopen = function () {
    //netSendViewRect(socket, 0, 0, app.screen.width, app.screen.height);
  };

  app.ticker.add((_) => {
    const mainRect = new Rectangle(
      PLAYFIELD_PADDING,
      PLAYFIELD_PADDING,
      app.screen.width * 0.8 - PLAYFIELD_PADDING * 2,
      app.screen.height - PLAYFIELD_PADDING * 2,
    );
    const gamePosition = global.gamePosition();
    global.playFieldContainer.pivot.set(gamePosition.x, gamePosition.y);
    global.mainContainer.position.set(mainRect.x, mainRect.y);
    global.mainContainer.setSize(mainRect.width, mainRect.height);
    global.sideBarContainer.pivot.set(
      app.screen.width * 0.8 + SIDEBAR_PADDING,
      SIDEBAR_PADDING,
    );

    g_mask.clear();
    graphicDrawRect(
      g_mask,
      new Rectangle(0, 0, mainRect.width, mainRect.height),
    ).fill(0xffff00);

    const changedSize: boolean = !isRectangleEqual(lastScreen, app.screen);
    if (changedSize) {
      lastScreen.copyFrom(app.screen);
      app.stage.hitArea = app.screen;

      mainGui.clear();
      graphicDrawRect(mainGui, mainRect.pad(2, 2))
        .fill(0xffffff)
        .stroke({ width: 3, color: 0x000000 });
      graphicDrawRect(
        g_container,
        new Rectangle(0, 0, mainRect.width, mainRect.height),
      ).fill(0xffffff);
    }

    g_grid.clear();
    const startX =
      global.playFieldContainer.pivot.x -
      (global.playFieldContainer.pivot.x % GRID_CELL_PX);
    const startY =
      global.playFieldContainer.pivot.y -
      (global.playFieldContainer.pivot.y % GRID_CELL_PX);
    for (let x = 0 - GRID_CELL_PX; x < mainRect.width + GRID_CELL_PX; x += 40) {
      g_grid
        .moveTo(x + startX, startY - GRID_CELL_PX)
        .lineTo(x + startX, mainRect.height + startY + GRID_CELL_PX);
    }
    for (let y = -GRID_CELL_PX; y < mainRect.height + GRID_CELL_PX; y += 40) {
      g_grid
        .moveTo(startX - GRID_CELL_PX, y + startY)
        .lineTo(mainRect.width + startX + GRID_CELL_PX, y + startY);
    }
    g_grid.stroke({ width: 1, color: 0xcccccc });
  });
})();
