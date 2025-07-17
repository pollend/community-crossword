import { Application, Graphics, GraphicsContext, Text } from "pixi.js";
import { app } from "./main";

const blockPool: Block[] = [];
const blocks: { [key: string]: Block } = {};

export const GRID_SIZE = 32; // Size of each grid block in pixels
export const GRID_LEN = GRID_SIZE * GRID_SIZE;
export const CELL_PX_SIZE = 40;
export const CELL_PX_PADDING = 1;

enum Character {
  none = 0, // empty cell
  dash = 1, // space/dash
  a,
  b,
  c,
  d,
  e,
  f,
  g,
  h,
  i,
  j,
  k,
  l,
  m,
  n,
  o,
  p,
  q,
  r,
  s,
  t,
  u,
  v,
  w,
  x,
  y,
  z,
}

const blkGridCtx: GraphicsContext = (() => {
  const ctx = new GraphicsContext();
  for (let x = 0; x < GRID_SIZE; x++) {
    ctx.moveTo(x * CELL_PX_SIZE, 0);
  }
  for (let y = 0; y < GRID_SIZE; y++) {}
  return ctx;
})();

function toCellChar(value: number): string {
  switch (value & 0x7f) {
    case Character.none:
      return " ";
    case Character.dash:
      return "-";
    case Character.a:
      return "a";
    case Character.b:
      return "b";
    case Character.c:
      return "c";
    case Character.d:
      return "d";
    case Character.e:
      return "e";
    case Character.f:
      return "f";
    case Character.g:
      return "g";
    case Character.h:
      return "h";
    case Character.i:
      return "i";
    case Character.j:
      return "j";
    case Character.k:
      return "k";
    case Character.l:
      return "l";
    case Character.m:
      return "m";
    case Character.n:
      return "n";
    case Character.o:
      return "o";
    case Character.p:
      return "p";
    case Character.q:
      return "q";
    case Character.r:
      return "r";
    case Character.s:
      return "s";
    case Character.t:
      return "t";
    case Character.u:
      return "u";
    case Character.v:
      return "v";
    case Character.w:
      return "w";
    case Character.x:
      return "x";
    case Character.y:
      return "y";
    case Character.z:
      return "z";
  }
  return "";
}

function toCellEnum(value: number): Character {
  return value & 0x7f;
}

export class Block {
  data: number[] = [];
  y: number = 0;
  x: number = 0;
  ctx: GraphicsContext | undefined;
  constructor() {}

  refresh(app: Application) {
    this.ctx = new GraphicsContext();
    // const test = new Text({
    //     text: 'Hello PixiJS!',
    //     style: {
    //       fill: '#ffffff',
    //       fontSize: 36,
    //       fontFamily: 'MyFont',
    //     },
    //     anchor: 0.5
    // });
    for (let i = 0; i < this.data.length; i++) {
      const value = this.data[i];
      const x = this.x * GRID_SIZE + (i % GRID_SIZE) + this.x * GRID_SIZE;
      const y =
        this.y * GRID_SIZE + Math.floor(i / GRID_SIZE) + this.y * GRID_SIZE;
      const v = toCellEnum(value);
      switch (v) {
        case Character.none:
          const blockedCell = new Graphics()
            .rect(
              x * CELL_PX_SIZE,
              y * CELL_PX_SIZE,
              CELL_PX_SIZE - CELL_PX_PADDING,
              CELL_PX_SIZE - CELL_PX_PADDING,
            )
            .fill(0x000000);

          app.stage.addChild(blockedCell);
          break;
        case Character.dash:
          //this.ctx.lineStyle(1, 0x000000, 1);
          //this.ctx.moveTo(x, y);
          //this.ctx.lineTo(x + GRID_SIZE, y + GRID_SIZE);
          //this.ctx.moveTo(x + GRID_SIZE, y);
          //this.ctx.lineTo(x, y + GRID_SIZE);
          break;
        default:
        // Draw a character
        //test.text = String.fromCharCode(v + 96); // 'a' is 97 in ASCII
        //test.position.set(x, y);
        //app.stage.addChild(test);
      }
    }
    //app.stage.addChild(test);
  }

  set(x: number, y: number, data: number[]) {
    this.x = x;
    this.y = y;
    this.data = data;
  }
}

function toGridBlock(x: number, y: number): string {
  return `${x} ${y}`;
}

export function setBlock(x: number, y: number, data: number[]) {
  const key = toGridBlock(x, y);
  if (!blocks[key]) {
    blocks[key] = new Block();
  }
  blocks[key].set(x, y, data);
  blocks[key].refresh(app);
}

export function getBlock(x: number, y: number): Block | undefined {
  return blocks[toGridBlock(x, y)];
}
