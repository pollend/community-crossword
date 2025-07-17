import { Container, Point, Rectangle } from "pixi.js";
import { GraphicQuad } from "./graphic_quad";

export const GRID_CELL_PX = 40; // Size of each grid block in pixels
export const GRID_SIZE = 32; // Size of each grid block in pixels
export const GRID_LEN = GRID_SIZE * GRID_SIZE;

export const PLAYFIELD_PADDING = 40;
export const SIDEBAR_PADDING = 40;

export function expect<T>(value: T | null): T {
  if (value === null) {
    throw new Error("Expected value to be non-null");
  }
  return value;
}

class Global {
  public mainContainer: Container = new Container();
  public sideBarContainer: Container = new Container();
  public playFieldContainer: Container = new Container();

  public socket: WebSocket | null = null;

  public topLeftPosition = new Point(0, 0);

  public dragStartPosition = new Point(0, 0);
  public stageDragPosition = new Point(0, 0);

  public quads: { [key: string]: GraphicQuad  } = {};

  public gamePosition() {
    return new Point(
      Math.max(0, this.topLeftPosition.x + this.stageDragPosition.x),
      Math.max(0, this.topLeftPosition.y + this.stageDragPosition.y),
    );
  }

  public setGamePosition(x: number, y: number) {
    this.topLeftPosition.set(Math.max(0, x), Math.max(0, y));
  }

  public getViewRect(): Rectangle {
    const size = this.mainContainer.getSize();
    return new Rectangle(
      this.topLeftPosition.x + this.stageDragPosition.x,
      this.topLeftPosition.y + this.stageDragPosition.y,
      size.width,
      size.height,
    );
  }
}

const global = new Global();
export default global;
