import { Point, Rectangle } from "pixi.js";
import { Clue, Direction, NetSyncBlock } from "./types";
import { GRID_SIZE, GRID_CELL_PX, SESSION_ID_LENGTH } from "./constants";
import pako from "pako";

const lastSyncedView = new Rectangle(0, 0, 0, 0);
const lastCursorPosition = new Point(0, 0);
export const enum MessageID {
  ready = 0,
  set_view = 1,
  sync_block = 2,
  input_or_sync_cell = 3,
  sync_cursors = 4,
  sync_cursors_delete = 5,
  broadcast_game_state = 6,
  update_nick = 7,
  solved_clue = 8,
}

export const enum Value {
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

export function cellToValue(value: number): Value {
  return value & 0x7f;
}
export function valueToChar(value: Value): string {
  switch (value & 0x7f) {
    case Value.dash:
      return "-";
    case Value.empty:
      return " ";
    case Value.a:
      return "A";
    case Value.b:
      return "B";
    case Value.c:
      return "C";
    case Value.d:
      return "D";
    case Value.e:
      return "E";
    case Value.f:
      return "F";
    case Value.g:
      return "G";
    case Value.h:
      return "H";
    case Value.i:
      return "I";
    case Value.j:
      return "J";
    case Value.k:
      return "K";
    case Value.l:
      return "L";
    case Value.m:
      return "M";
    case Value.n:
      return "N";
    case Value.o:
      return "O";
    case Value.p:
      return "P";
    case Value.q:
      return "Q";
    case Value.r:
      return "R";
    case Value.s:
      return "S";
    case Value.t:
      return "T";
    case Value.u:
      return "U";
    case Value.v:
      return "V";
    case Value.w:
      return "W";
    case Value.x:
      return "X";
    case Value.y:
      return "Y";
    case Value.z:
      return "Z";
  }
  throw new Error(`Unknown value ${value}`);
}

export function isEmptyValue(value: Value): boolean {
  return value === Value.empty || value === Value.dash;
}

export function charToValue(c: string): Value | undefined {
  switch (c) {
    case "-":
      return Value.dash;
    case " ":
      return Value.empty;
    case "A":
    case "a":
      return Value.a;
    case "B":
    case "b":
      return Value.b;
    case "C":
    case "c":
      return Value.c;
    case "D":
    case "d":
      return Value.d;
    case "E":
    case "e":
      return Value.e;
    case "F":
    case "f":
      return Value.f;
    case "G":
    case "g":
      return Value.g;
    case "H":
    case "h":
      return Value.h;
    case "I":
    case "i":
      return Value.i;
    case "J":
    case "j":
      return Value.j;
    case "K":
    case "k":
      return Value.k;
    case "L":
    case "l":
      return Value.l;
    case "M":
    case "m":
      return Value.m;
    case "N":
    case "n":
      return Value.n;
    case "O":
    case "o":
      return Value.o;
    case "P":
    case "p":
      return Value.p;
    case "Q":
    case "q":
      return Value.q;
    case "R":
    case "r":
      return Value.r;
    case "S":
    case "s":
      return Value.s;
    case "T":
    case "t":
      return Value.t;
    case "U":
    case "u":
      return Value.u;
    case "V":
    case "v":
      return Value.v;
    case "W":
    case "w":
      return Value.w;
    case "X":
    case "x":
      return Value.x;
    case "Y":
    case "y":
      return Value.y;
    case "Z":
    case "z":
      return Value.z;
  }
  return undefined;
}

export function netParseSolveClue(
  view: DataView,
  offset: number,
): {
  owner: boolean;
  x: number;
  y: number;
  dir: Direction;
  values: Value[];
} {
  const flags = view.getUint8(offset);
  offset += 1;
  const dir: Direction = flags & 0x3; // 0 = horizontal, 1 = vertical
  const owner: boolean = (flags & 0x8) > 0;
  const x = view.getUint32(offset, true);
  offset += 4;
  const y = view.getUint32(offset, true);
  offset += 4;
  const values: Value[] = [];
  while (offset < view.byteLength) {
    values.push(view.getUint8(offset));
    offset += 1;
  }
  return {
    owner: owner,
    x: x,
    y: y,
    dir: dir,
    values: values,
  };
}

export function netParseGameState(
  view: DataView,
  offset: number,
): {
  progress: number;
} {
  const percent = view.getFloat32(offset, true);
  offset += 4;
  return {
    progress: percent,
  };
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
  };
}

export interface TrackedCursor {
  clientId: number;
  pos: Point;
}

export function netParseSyncCursors(
  view: DataView,
  offset: number,
  delete_cursors: boolean,
): {
  del: number[];
  new: TrackedCursor[];
} {
  const del: number[] = [];
  if (delete_cursors) {
    const num = view.getUint16(offset, true);
    offset += 2;
    for (let i = 0; i < num; i++) {
      del.push(view.getUint32(offset, true));
      offset += 4;
    }
  }

  const quadX = view.getUint16(offset, true);
  offset += 2;
  const quadY = view.getUint16(offset, true);
  offset += 2;

  const cursors: TrackedCursor[] = [];
  const quadPosX = quadX * GRID_SIZE * GRID_CELL_PX;
  const quadPosY = quadY * GRID_SIZE * GRID_CELL_PX;
  while (offset < view.byteLength) {
    const clientId = view.getUint32(offset, true);
    offset += 4;
    const relativeX = view.getInt16(offset, true);
    offset += 2;
    const relativeY = view.getInt16(offset, true);
    offset += 2;
    cursors.push({
      clientId,
      pos: new Point(quadPosX + relativeX, quadPosY + relativeY),
    });
  }

  return {
    del: del,
    new: cursors,
  };
}

export function netParseReady(view: DataView, offset: number) {
  const width = view.getUint32(offset, true);
  offset += 4;
  const height = view.getUint32(offset, true);
  offset += 4;
  const num_cluse_solved = view.getUint32(offset, true);
  offset += 4;
  const score = view.getUint32(offset, true);
  offset += 4;
  const uid = view.getUint32(offset, true);
  offset += 4;
  return {
    num_clues_solved: num_cluse_solved,
    score: score,
    board_width: width,
    board_height: height,
    uid: uid,
  };
}

export function netParseSyncChunk(
  compressed_view: DataView,
  offset: number,
): NetSyncBlock {
  const view = new DataView(
    pako.ungzip(compressed_view.buffer.slice(offset)).buffer,
  );
  offset = 0;
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
  const clues: Clue[] = [];
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
    let tex: string = "";
    for (let j = 0; j < clueLength; j++) {
      const ch = view.getUint8(offset);
      offset += 1;
      tex += String.fromCharCode(ch);
    }
    clues.push({
      x: x,
      y: y,
      dir: dir,
      text: tex,
    });
  }
  return { x, y, block, clues };
}

export function netSendCell(ws: WebSocket, x: number, y: number, value: Value) {
  // 1 byte for ID, 4 bytes for x, 4 bytes for y, 1 byte for value
  const buffer = new ArrayBuffer(1 + 4 + 4 + 1);
  let offset = 0;
  const view = new DataView(buffer);
  view.setUint8(offset, MessageID.input_or_sync_cell);
  offset += 1;
  view.setUint32(offset, x, true);
  offset += 4;
  view.setUint32(offset, y, true);
  offset += 4;
  view.setUint8(offset, value);
  ws.send(buffer);
}

export function netParseNick(view: DataView, offset: number): string {
  let nick = "";
  while (offset < view.byteLength) {
    nick += String.fromCharCode(view.getUint8(offset));
    offset += 1;
  }
  return nick;
}

export function netParseSessionNegotiation(
  view: DataView,
  offset: number,
): {
  session: string;
  nick: string;
} {
  let session = "";
  let nick = "";
  for (let i = 0; i < SESSION_ID_LENGTH; i++) {
    const c = String.fromCharCode(view.getUint8(offset));
    offset += 1;
    session += c;
  }
  const nick_length = view.getUint8(offset);
  offset += 1;
  for (let i = 0; i < nick_length; i++) {
    const c = String.fromCharCode(view.getUint8(offset));
    offset += 1;
    nick += c;
  }
  return {
    session: session,
    nick: nick,
  };
}

export function netSendNick(ws: WebSocket, nick: string) {
  const buffer = new ArrayBuffer(1 + nick.length);
  let offset = 0;
  const view = new DataView(buffer);
  view.setUint8(offset, MessageID.update_nick);
  offset += 1;
  for (const c of nick) {
    view.setUint8(offset, c.charCodeAt(0));
    offset += 1;
  }
  ws.send(buffer);
}
//
//export function netSendSessionNegotiation(ws: WebSocket, session: string) {
//  const buffer = new ArrayBuffer(1 + session.length);
//  let offset = 0;
//  const view = new DataView(buffer);
//  view.setUint8(offset, MessageID.session_negotiation);
//  offset += 1;
//  for (const c of session) {
//    view.setUint8(offset, c.charCodeAt(0));
//    offset += 1;
//  }
//  ws.send(buffer);
//}

export function netSendViewRect(
  ws: WebSocket,
  x: number,
  y: number,
  width: number,
  height: number,
  cursor: Point,
) {
  if (
    lastSyncedView.x === x &&
    lastSyncedView.y === y &&
    lastSyncedView.width === width &&
    lastSyncedView.height === height &&
    lastCursorPosition.x === cursor.x &&
    lastCursorPosition.y === cursor.y
  ) {
    return;
  }
  lastSyncedView.set(x, y, width, height);
  lastCursorPosition.set(cursor.x, cursor.y);

  // 1 byte for ID, 4 bytes each for x, y, width, height
  const buffer = new ArrayBuffer(1 + 2 + 2 + 2 + 2 + 4 + 4);
  let offset = 0;
  const view = new DataView(buffer);
  view.setUint8(offset, MessageID.set_view);
  offset += 1;
  view.setUint16(offset, Math.max(0, x), true);
  offset += 2;
  view.setUint16(offset, Math.max(0, y), true);
  offset += 2;
  view.setUint16(offset, Math.max(0, width), true);
  offset += 2;
  view.setUint16(offset, Math.max(0, height), true);
  offset += 2;
  view.setUint32(offset, Math.max(cursor.x, 0), true);
  offset += 4;
  view.setUint32(offset, Math.max(cursor.y, 0), true);
  offset += 4;
  ws.send(buffer);
}
