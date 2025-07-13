import {Application, Assets, Sprite } from "pixi.js";
import {MessageID, netSendViewRect} from "./net";
import { setBlock } from "./board";
export const GRID_SIZE = 32; // Size of each grid block in pixels
export const GRID_LEN = GRID_SIZE * GRID_SIZE;

export const app = new Application();
export const socket = new WebSocket("ws://localhost:3010/ws");

(async () => {
  // Create a new application
  socket.binaryType = "arraybuffer"
  socket.onmessage = function(e) {
    const view = new DataView(e.data);
    let offset = 0;
    const msgid = view.getUint8(offset); // Read the message ID
    offset += 1;
    switch(msgid) {
      case MessageID.SyncBlock: {
        const xx = view.getUint32(offset);
        offset += 4;
        const yy = view.getUint32(offset);
        offset += 4;
        let data: number[] = [];
        for(let j = 0; j < GRID_SIZE * GRID_SIZE; j++) {
          data.push(view.getUint8(offset));
          offset += 1;
        }
        setBlock(xx, yy, data);
        break;
      } 
    }
  };
  socket.onclose = function() { 
  };

  socket.onopen = function() { 
    netSendViewRect(socket, 0, 0, app.screen.width, app.screen.height);
  };

  await app.init({ background: "#FFFFFF", resizeTo: window });

  // Append the application canvas to the document body
  document.getElementById("pixi-container")!.appendChild(app.canvas);

  // Load the bunny texture
  //const texture = await Assets.load("/assets/bunny.png");

  // Create a bunny Sprite
  //const bunny = new Sprite(texture);

  // Center the sprite's anchor point
  //bunny.anchor.set(0.5);

  // Move the sprite to the center of the screen
  //bunny.position.set(app.screen.width / 2, app.screen.height / 2);

  // Add the bunny to the stage
  //app.stage.addChild(bunny);

  // Listen for animate update
  //app.ticker.add((time) => {


  //  // Just for fun, let's rotate mr rabbit a little.
  //  // * Delta is 1 if running at 100% performance *
  //  // * Creates frame-independent transformation *
  //  bunny.rotation += 0.1 * time.deltaTime;
  //});
})();
