import { Rectangle } from "pixi.js";
import { Clue, NetSyncBlock } from "./types";
import { GRID_SIZE } from "./constants";

const lastSyncedView = new Rectangle(0, 0, 0, 0);

export enum MessageID {
  ready = 0, 
  set_view = 1, 
  sync_block = 2,
  sync_input_cell = 3,
}

export enum Value {
  empty, // empty cell
  dash, // space/dash
  black, // black cell
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

export function isBlocked(value: number): boolean {
  return value & 0x80 ? true : false;
}

export function cellToValue(value: number) : Value{
  return value & 0x7F;
}
export function valueToChar(value: Value): string {
  switch (value) {
    case Value.dash: return '-';
    case Value.empty: return ' ';
    case Value.a: return 'a';
    case Value.b: return 'b';
    case Value.c: return 'c';
    case Value.d: return 'd';
    case Value.e: return 'e';
    case Value.f: return 'f';
    case Value.g: return 'g';
    case Value.h: return 'h';
    case Value.i: return 'i';
    case Value.j: return 'j';
    case Value.k: return 'k';
    case Value.l: return 'l';
    case Value.m: return 'm';
    case Value.n: return 'n';
    case Value.o: return 'o';
    case Value.p: return 'p';
    case Value.q: return 'q';
    case Value.r: return 'r';
    case Value.s: return 's';
    case Value.t: return 't';
    case Value.u: return 'u';
    case Value.v: return 'v';
    case Value.w: return 'w';
    case Value.x: return 'x';
    case Value.y: return 'y';
    case Value.z: return 'z';
  }
  throw new Error(`Unknown value ${value}`);
}

export function charToValue(c: string): Value | undefined {
  switch (c) {
   case '-': return Value.dash;
   case ' ': return Value.empty;
   case 'A': case 'a': return Value.a;
   case 'B': case 'b': return Value.b;
   case 'C': case 'c': return Value.c;
   case 'D': case 'd': return Value.d;
   case 'E': case 'e': return Value.e;
   case 'F': case 'f': return Value.f;
   case 'G': case 'g': return Value.g;
   case 'H': case 'h': return Value.h;
   case 'I': case 'i': return Value.i;
   case 'J': case 'j': return Value.j;
   case 'K': case 'k': return Value.k;
   case 'L': case 'l': return Value.l;
   case 'M': case 'm': return Value.m;
   case 'N': case 'n': return Value.n;
   case 'O': case 'o': return Value.o;
   case 'P': case 'p': return Value.p;
   case 'Q': case 'q': return Value.q;
   case 'R': case 'r': return Value.r;
   case 'S': case 's': return Value.s;
   case 'T': case 't': return Value.t;
   case 'U': case 'u': return Value.u;
   case 'V': case 'v': return Value.v;
   case 'W': case 'w': return Value.w;
   case 'X': case 'x': return Value.x;
   case 'Y': case 'y': return Value.y;
   case 'Z': case 'z': return Value.z;
  }
  return undefined;
}

export function netParseCell(view: DataView, offset: number) {
  const x = view.getUint32(offset, true);
  offset += 4;
  const y = view.getUint32(offset, true);
  offset += 4;
  const cell = view.getUint8(offset);
  offset += 1;
  return {
    x: x,
    y: y,
    value: cell,
  }
}

export function netParseReady(view: DataView, offset: number){
  const width = view.getUint32(offset, true);
  offset += 4;
  const height = view.getUint32(offset, true);
  offset += 4;
  return {
    board_width: width,
    board_height: height,
  }
}

export function netParseSyncChunk(
  view: DataView,
  offset: number,
): NetSyncBlock {
  const x = view.getUint32(offset, true);
  offset += 4;
  const y = view.getUint32(offset, true);
  offset += 4;
  const block: number[] = [];
  for (let i = 0; i < GRID_SIZE * GRID_SIZE; i++) {
    block.push(view.getUint8(offset));
    offset += 1;
  }
  const numClues = view.getUint16(offset, true);
  let clues: Clue[] = [];
  offset += 2;
  for (let i = 0; i < numClues; i++) {
    const x = view.getUint8(offset);
    offset += 1;
    const y = view.getUint8(offset);
    offset += 1;
    const dir = view.getUint8(offset);
    offset += 1;
    const clueLength = view.getUint16(offset, true);
    offset += 2;
    let tex: string = ""
    for(let j = 0; j < clueLength; j++) {
      const ch = view.getUint8(offset);
      offset += 1;
      tex += String.fromCharCode(ch);
    }
    clues.push({
      x: x,
      y: y,
      dir: dir,
      text: tex,
    })
  }
  return { x, y, block, clues };
}

export function netSendCell(
  ws: WebSocket,
  x: number,
  y: number,
  value: Value,
) {
  // 1 byte for ID, 4 bytes for x, 4 bytes for y, 1 byte for value
  const buffer = new ArrayBuffer(1 + 4 + 4 + 1);
  let offset = 0;
  const view = new DataView(buffer);
  view.setUint8(offset, MessageID.sync_input_cell );
  offset += 1;
  view.setUint32(offset, x, true);
  offset += 4;
  view.setUint32(offset, y, true);
  offset += 4;
  view.setUint8(offset, value);
  ws.send(buffer);
}


export function netSendViewRect(
  ws: WebSocket,
  x: number,
  y: number,
  width: number,
  height: number,
) {
  if (
    lastSyncedView.x === x &&
    lastSyncedView.y === y &&
    lastSyncedView.width === width &&
    lastSyncedView.height === height
  ) {
    return;
  }

  lastSyncedView.set(x, y, width, height);

  // 1 byte for ID, 4 bytes each for x, y, width, height
  const buffer = new ArrayBuffer(1 + 4 + 4 + 4 + 4);
  let offset = 0;
  const view = new DataView(buffer);
  view.setUint8(offset, MessageID.set_view);
  offset += 1;
  view.setUint32(offset, Math.max(0, x), true);
  offset += 4;
  view.setUint32(offset, Math.max(0, y), true);
  offset += 4;
  view.setUint32(offset, Math.max(0, width), true);
  offset += 4;
  view.setUint32(offset, Math.max(0, height), true);
  ws.send(buffer);
}
