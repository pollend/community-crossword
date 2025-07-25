import { Container, Graphics, Point, Pool, Text, TextStyle } from "pixi.js";
import { cellToValue, isBlocked, Value, valueToChar } from "./net";
import { Clue } from "./types";
import { GRID_CELL_PX, GRID_SIZE } from "./constants";

const defaultStyle = new TextStyle({
  fontFamily: "Arial",
  fontSize: 36,
});

const correctStyle = new TextStyle({
  fontFamily: "Arial",
  fontSize: 36,
  fill: 0x666666,
});

const clueNumberStyle = new TextStyle({
  fontFamily: "Arial",
  fontSize: 18,
});

const textPool = new Pool<Text>(Text);

export class Quad {
  public container: Container = new Container();
  public graphic: Graphics = new Graphics();

  public clueNumbers: number[] = new Array(GRID_SIZE * GRID_SIZE).fill(0);

  constructor(
    public readonly pos: Point,
    public readonly clues: Clue[],
    public readonly cells: number[],
  ) {}

  getCell(pos: Point): number {
    const x = pos.x;
    const y = pos.y;
    if (x < 0 || x >= GRID_SIZE || y < 0 || y >= GRID_SIZE) {
      return -1;
    }
    return y * GRID_SIZE + x;
  }

  destroy() {
    for (const c of this.container.children) {
      if (c instanceof Text) {
        textPool.return(c);
      }
    }
    this.container.removeChildren();
    this.container.destroy(true);
    this.graphic.destroy(true);
  }

  //reset() {
  //  for(const c of this.container.children) {
  //    if(c instanceof Text) {
  //      textPool.return(c);
  //    }
  //  }
  //  this.container.removeChildren()
  //  this.container.addChild(this.graphic);
  //}

  //addChildCellNumber(x: number, y: number, value: number) {
  // //   this.clueNumbers[y * GRID_SIZE + x] = value;

  //    const tex = textPool.get();
  //    tex.anchor.set(0, 1);
  //    tex.style = clueNumberStyle;
  //    tex.text = value + "";
  //    tex.x = x * GRID_CELL_PX;
  //    tex.y = y * GRID_CELL_PX + GRID_CELL_PX;
  //    this.container.addChild(tex);
  //}

  update() {
    for (const c of this.container.children) {
      if (c instanceof Text) {
        textPool.return(c);
      }
    }
    this.container.removeChildren();
    this.container.addChild(this.graphic);
    this.container.pivot.set(
      -this.pos.x * GRID_CELL_PX * GRID_SIZE,
      -this.pos.y * GRID_CELL_PX * GRID_SIZE,
    );
    for (let i = 0; i < this.cells.length; i++) {
      const px = i % GRID_SIZE;
      const py = Math.floor(i / GRID_SIZE);
      const cellNumber = this.clueNumbers[i];
      if (cellNumber >= 0) {
        const tex = textPool.get();
        tex.anchor.set(0, 1);
        tex.style = clueNumberStyle;
        tex.text = cellNumber + 1 + "";
        tex.x = px * GRID_CELL_PX;
        tex.y = py * GRID_CELL_PX + GRID_CELL_PX;
        this.container.addChild(tex);
      }
      const value = this.cells[i];
      const val = cellToValue(value);
      let style = defaultStyle;
      if (isBlocked(value)) {
        style = correctStyle;
        //this.graphic.
        //  rect(px * GRID_CELL_PX, py * GRID_CELL_PX, GRID_CELL_PX, GRID_CELL_PX)
        //  .fill({
        //    color: "0x2ffd9",
        //    opacity: 0.5,
        //  });
      }
      switch (val) {
        case Value.empty:
          break;
        case Value.black:
          this.graphic
            .rect(
              px * GRID_CELL_PX,
              py * GRID_CELL_PX,
              GRID_CELL_PX,
              GRID_CELL_PX,
            )
            .fill(0x000000);
          break;
        default: {
          const c = valueToChar(val);
          const tex = textPool.get();
          tex.anchor.set(0.5, 0.5);
          tex.style = style;
          tex.text = c;
          tex.x = px * GRID_CELL_PX + GRID_CELL_PX / 2;
          tex.y = py * GRID_CELL_PX + GRID_CELL_PX / 2;
          this.container.addChild(tex);
          break;
        }
      }
    }
  }
}
