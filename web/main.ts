import {
  Application,
  FederatedMouseEvent,
  Graphics,
  Point,
  Rectangle,
  Text,
  TextStyle
} from "pixi.js";
import { cellToValue, MessageID, netParseReady, netParseSyncChunk, netSendViewRect, Value } from "./net";
import global, {
    Direction,
  expect,
  GRID_CELL_PX,
  MouseState,
  PLAYFIELD_PADDING,
  SIDEBAR_PADDING,
  SPLIT_PERCENT,
} from "./state";
import { graphicDrawRect } from "./graphic";
import { GraphicQuad } from "./graphic_quad";

function isRectangleEqual(a: Rectangle, b: Rectangle): boolean {
  return (
    a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height
  );
}

const clueTextStyle = new TextStyle({
  fontFamily: 'Arial',
  fontSize: 20,
});

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
  
  const acrossText = new Text({
    text: "Across",
    anchor: { x: 0.5, y: 0 }, 
    style: {
      fontFamily: "Arial",
      fontSize: 24,
      fill: "#000000",
    }
  })
  app.stage.addChild(acrossText);
  const downText = new Text({
    text: "Down",
    anchor: { x: 0.5, y: 0 }, 
    style: {
      fontFamily: "Arial",
      fontSize: 24,
      fill: "#000000",
    }
  })
  app.stage.addChild(downText);


  global.mainContainer.eventMode = "static";
  app.stage.addChild(global.mainContainer);

  // dragging the board
  {
    function onBoardDragMove(event: FederatedMouseEvent) {
      global.mouse = MouseState.Dragging
      global.stageDragPosition.set(
        global.dragStartPosition.x - event.global.x,
        global.dragStartPosition.y - event.global.y,
      );
      global.syncViewThrottle.trigger();
    }
    function onBoardDragEnd(ev: FederatedMouseEvent) {

      app.stage.off("pointermove", onBoardDragMove);
      switch (global.mouse) {
        case MouseState.Dragging: {
          global.setGamePosition(
            global.topLeftPosition.x + global.stageDragPosition.x,
            global.topLeftPosition.y + global.stageDragPosition.y,
          );
          global.stageDragPosition.set(0, 0);
          global.syncViewThrottle.trigger();
          break;
        }
        case MouseState.Clicking: {
          const pp = ev.getLocalPosition(global.playFieldContainer);
          const center = new Point(
            Math.floor(pp.x/ GRID_CELL_PX),
            Math.floor(pp.y/ GRID_CELL_PX),
          );
          if(global.selection.center) {
            if(center.x == global.selection.center.x && center.y == global.selection.center.y) {
              global.selection.dir = global.selection.dir === Direction.Horizontal ? Direction.Vertical : Direction.Horizontal;
            } else {
              global.selection.center = center;
            }
          } else {
            global.selection.center = center
          }
          break;
        }
      }
      
      global.mouse = MouseState.None
    }
    app.stage.on("pointerupoutside", onBoardDragEnd);
    app.stage.on("pointerup", onBoardDragEnd);
    global.mainContainer.on("pointerdown", (event) => {
      global.mouse = MouseState.Clicking
      global.dragStartPosition = new Point(event.global.x, event.global.y);
      app.stage.on("pointermove", onBoardDragMove);
    });
  }
  const backGraphics = new Graphics();
  global.playFieldContainer.addChild(backGraphics);

  const graphicMask = new Graphics();
  const graphicContainer = new Graphics();
  global.mainContainer.mask = graphicMask;
  global.mainContainer.addChild(graphicMask);
  global.mainContainer.addChild(graphicContainer);
  global.mainContainer.addChild(global.playFieldContainer);

  global.socket.onmessage = function (e) {
    const socket = expect(global.socket);
    const view = new DataView(e.data);
    let offset = 0;
    const msgid = view.getUint8(offset); // Read the message ID
    offset += 1;
    console.log("Received message ID:", msgid);
    switch (msgid) {
      case MessageID.ready: {
        const readyPkt = netParseReady(view, offset);
        global.boardSize.set(readyPkt.board_width, readyPkt.board_height);
        global.syncViewThrottle.trigger();
        break;
      }
      case MessageID.sync_block: {
        const syncBlock = netParseSyncChunk(view, offset);
        for(const netClue of syncBlock.clues) {
          let insertIdx = -1;
          let found = false;
          for(let i = 0; i < global.clues.length; i++) {
            const cl = global.clues[i];
            if(cl === undefined) {
              insertIdx = i;
            } else {
              if(cl.pos.x === (netClue.x + syncBlock.x) && cl.pos.y === (netClue.y + syncBlock.y)) {
                found = true;
                if(netClue.dir === 0) {
                  cl.hor = netClue;
                } else {
                  cl.ver = netClue;
                }
              }
            }
          }
          if(found) {
            continue;
          }
          global.dirtyClues = true;
          if(insertIdx === -1) {
            global.clues.push({
              pos: new Point(netClue.x + syncBlock.x, netClue.y + syncBlock.y),
              hor: netClue.dir === 0 ? netClue : undefined,
              ver: netClue.dir === 1 ? netClue : undefined,
            })
          } else {
            global.clues[insertIdx] = {
              pos: new Point(netClue.x + syncBlock.x, netClue.y + syncBlock.y),
              hor: netClue.dir === 0 ? netClue : undefined,
              ver: netClue.dir === 1 ? netClue : undefined,
            };
          }
        }
        const index = global.quadIndex(syncBlock.x, syncBlock.y);
        if(global.quads[index] == undefined) {
          global.quads[index] = new GraphicQuad();
          global.playFieldContainer.addChild(global.quads[index].container);
        }
        global.quads[index].update(
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
      app.screen.width * SPLIT_PERCENT - PLAYFIELD_PADDING * 2,
      app.screen.height - PLAYFIELD_PADDING * 2,
    );
    const sideBarRect = new Rectangle(
      app.screen.width * SPLIT_PERCENT + SIDEBAR_PADDING,
      SIDEBAR_PADDING,
      app.screen.width * (1.0 - SPLIT_PERCENT) - SIDEBAR_PADDING * 2,
      app.screen.height - SIDEBAR_PADDING * 2,
    )
    const gamePosition = global.gamePosition();
    global.playFieldContainer.pivot.set(gamePosition.x, gamePosition.y);
    global.mainContainer.position.set(mainRect.x, mainRect.y);
    global.mainContainer.setSize(mainRect.width, mainRect.height);

    graphicMask.clear();
    graphicDrawRect(
      graphicMask,
      new Rectangle(0, 0, mainRect.width, mainRect.height),
    ).fill(0xffff00);

    const changedSize: boolean = !isRectangleEqual(lastScreen, app.screen);
    if (changedSize) {
      global.syncViewThrottle.trigger();
      lastScreen.copyFrom(app.screen);
      app.stage.hitArea = app.screen;

      graphicDrawRect(
        graphicContainer,
        new Rectangle(0, 0, mainRect.width, mainRect.height),
      ).fill(0xffffff);
    }
    mainGui.clear();
    graphicDrawRect(mainGui, mainRect.pad(2, 2))
      .fill(0xffffff)
      .stroke({ width: 3, color: 0x000000 });

    // clues down
    {
      const cluesDownContainer = new Rectangle(
        sideBarRect.x + 10,
        sideBarRect.y + 10,
        sideBarRect.width - 20,
        sideBarRect.height - 20,
      )
      acrossText.x = cluesDownContainer.x;
      acrossText.y = cluesDownContainer.y;
      global.downContainer.position.set(
        cluesDownContainer.x,
        cluesDownContainer.y,
      );
      global.downContainer.setSize(
        cluesDownContainer.width,
        cluesDownContainer.height,
      );

      const horizontalCluesContainer = new Rectangle(
        sideBarRect.width * 0.5 + sideBarRect.x + 10,
        sideBarRect.y + 10,
        sideBarRect.width * 0.5 - 20,
        sideBarRect.height - 20,
      );
      downText.x = horizontalCluesContainer.x;
      downText.y = horizontalCluesContainer.y;
      global.acrosssContainer.position.set(
        horizontalCluesContainer.x,
        horizontalCluesContainer.y);
      global.acrosssContainer.setSize(
        horizontalCluesContainer.width,
        horizontalCluesContainer.height,
      );

      if(global.dirtyClues) {
        global.acrosssContainer.removeChildren();
        global.downContainer.removeChildren();
        global.dirtyClues = false;
      }
    }

    backGraphics.clear();
    const center = global.selection.center;
    if(center) {
      switch(global.selection.dir) {
        case Direction.Horizontal: {
          let x0 = center.x;
          let x1 = center.x;
          const viewRect = global.getViewRectCells(); 
          while(x1 <= viewRect.right) {
            const cell = global.getCell(x1,center.y);
            if(cellToValue(cell) === Value.black) {
              break;
            }
            x1 += 1;
          }
          while(x0 > viewRect.left) {
            const cell = global.getCell(x0, center.y);
            if(cellToValue(cell) === Value.black) {
              break;
            }
            x0 -= 1;
          }
          backGraphics
            .rect(x0 * GRID_CELL_PX, center.y * GRID_CELL_PX, (x1 - x0) * GRID_CELL_PX, 1 * GRID_CELL_PX)
            .fill(0xa7d8ff);
          break;
        }
        case Direction.Vertical: {
          let y0 = center.y;
          let y1 = center.y;
          const viewRect = global.getViewRectCells(); 
          while(y1 <= viewRect.bottom) {
            const cell = global.getCell(center.x, y1);
            if(cellToValue(cell) === Value.black) {
              break;
            }
            y1 += 1;
          }
          while(y0 > viewRect.top) {
            const cell = global.getCell(center.x, y0);
            if(cellToValue(cell) === Value.black) {
              break;
            }
            y0 -= 1;
          }
          backGraphics
            .rect(center.x * GRID_CELL_PX, y0 * GRID_CELL_PX, GRID_CELL_PX, (y1 - y0) * GRID_CELL_PX)
            .fill(0xa7d8ff);
          break;
        }
      }

      
      backGraphics.
        rect(center.x * GRID_CELL_PX, center.y * GRID_CELL_PX,GRID_CELL_PX, GRID_CELL_PX)
        .fill(0xffda00)
    }

    const startX =
      global.playFieldContainer.pivot.x -(global.playFieldContainer.pivot.x % GRID_CELL_PX);
    const startY =
      global.playFieldContainer.pivot.y - (global.playFieldContainer.pivot.y % GRID_CELL_PX);
    for (let x = 0 - GRID_CELL_PX; x < mainRect.width + GRID_CELL_PX; x += 40) {
      backGraphics
        .moveTo(x + startX, startY - GRID_CELL_PX)
        .lineTo(x + startX, mainRect.height + startY + GRID_CELL_PX);
    }
    for (let y = -GRID_CELL_PX; y < mainRect.height + GRID_CELL_PX; y += 40) {
      backGraphics
        .moveTo(startX - GRID_CELL_PX, y + startY)
        .lineTo(mainRect.width + startX + GRID_CELL_PX, y + startY);
    }
    backGraphics.stroke({ width: 1, color: 0xcccccc });
  });
})();
