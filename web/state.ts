import { Container, Point, Rectangle } from "pixi.js";
import { GraphicQuad } from "./graphic_quad";
import { Clue, netSendViewRect } from "./net";
import { Throttle } from "./timing";

export const GRID_CELL_PX = 40; // Size of each grid block in pixels
export const GRID_SIZE = 32; // Size of each grid block in pixels
export const GRID_LEN = GRID_SIZE * GRID_SIZE;

export const PLAYFIELD_PADDING = 40;
export const SIDEBAR_PADDING = 40;
export const SPLIT_PERCENT = 0.65; // Percentage of the screen width for the playfield

export function expect<T>(value: T | null): T {
  if (value === null) {
    throw new Error("Expected value to be non-null");
  }
  return value;
}

export enum Direction {
  Horizontal = 0,
  Vertical = 1,
}

export enum MouseState {
  None,
  Dragging,
  Clicking,
}

class Global {
  public mainContainer: Container = new Container();
  public playFieldContainer: Container = new Container();

  public acrosssContainer: Container = new Container();
  public downContainer: Container = new Container();

  public syncViewThrottle = new Throttle(500,() => {
    const view = this.getViewRect();
    const x = Math.floor(view.x / GRID_CELL_PX);
    const y = Math.floor(view.y / GRID_CELL_PX);
    const width = Math.floor((view.width + view.x) / GRID_CELL_PX) - x;
    const height = Math.floor((view.height + view.y) / GRID_CELL_PX) - y;
    netSendViewRect(
      expect(global.socket),x,y,width,height
    );
  });

  public socket: WebSocket | null = null;

  public clues: ({
    pos: Point, 
    hor: Clue | undefined, 
    ver: Clue | undefined,
  } | undefined)[] = []; 

  public dirtyClues: boolean = false;

  public mouse: MouseState = MouseState.None;
  public topLeftPosition = new Point(0, 0);

  public dragStartPosition = new Point(0, 0);
  public stageDragPosition = new Point(0, 0);

  public boardSize = new Point(0, 0);

  public selection: {
    center: Point | undefined,
    dir: Direction, // 0 = horizontal, 1 = vertical
  } = {
    center: new Point(1, 1),
    dir: 0, // 0 = horizontal, 1 = vertical
  };

  public quads: { [key: number]: GraphicQuad  } = {};

  public gamePosition() {
    return new Point(
      Math.max(0, this.topLeftPosition.x + this.stageDragPosition.x),
      Math.max(0, this.topLeftPosition.y + this.stageDragPosition.y),
    );
  }

  get quadWidth(): number { return this.boardSize.x / GRID_SIZE; }
  get quadHeight(): number { return this.boardSize.y / GRID_SIZE; }

  public getCell(x: number, y: number): number {
    const quadIndex = this.quadIndex(Math.floor(x/GRID_SIZE), Math.floor(y/GRID_SIZE));
    const quad = this.quads[quadIndex];
    if (!quad) {
      return 0; // or some default value
    }
    const cellX = x % GRID_SIZE;
    const cellY = y % GRID_SIZE;
    return quad.data[cellY * GRID_SIZE + cellX];
  }


  public quadIndex(x: number, y: number): number {
    return (y * this.quadWidth) + x;
  }

  public setGamePosition(x: number, y: number) {
    this.topLeftPosition.set(Math.max(0, x), Math.max(0, y));
  }

  public getViewRect(): Rectangle {
    const size = this.mainContainer.getSize();
    return new Rectangle(
      Math.max(this.topLeftPosition.x + this.stageDragPosition.x, 0),
      Math.max(this.topLeftPosition.y + this.stageDragPosition.y,0),
      size.width,
      size.height,
    );
  }

  public getViewRectCells(): Rectangle {
    const view = this.getViewRect();
    return new Rectangle(
      Math.floor(view.x / GRID_CELL_PX),
      Math.floor(view.y / GRID_CELL_PX),
      Math.ceil(view.width / GRID_CELL_PX),
      Math.ceil(view.height / GRID_CELL_PX),
    );
  }
}

const global = new Global();
export default global;
