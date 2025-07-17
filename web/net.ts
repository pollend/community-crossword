import { Rectangle } from "pixi.js";
import { GRID_SIZE } from "./state";

const lastSyncedView = new Rectangle(0, 0, 0, 0);

export enum MessageID {
  ready,
  set_view,
  sync_block,
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

export interface NetSyncBlock {
  x: number;
  y: number;
  block: number[];
}

export function netParseSyncBlock(
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
  return { x, y, block };
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
