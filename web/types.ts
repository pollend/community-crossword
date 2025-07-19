export enum Direction {
  Horizontal = 0,
  Vertical = 1,
}

export enum MouseState {
  None,
  Dragging,
  Clicking,
}
export interface Clue {
  x: number;
  y: number;
  dir: number; // 0 = horizontal, 1 = vertical
  text: string;
}

export interface NetSyncBlock {
  x: number;
  y: number;
  block: number[];
  clues: Clue[]
}

export interface NetReady {
  board_width: number;
  board_height: number;
}


