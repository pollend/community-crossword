import { Container, Graphics, GraphicsContext, Point , Pool, Text, TextStyle} from "pixi.js";
import global, { GRID_CELL_PX, GRID_SIZE } from "./state";
import { cellToValue, Clue, isBlocked, Value, valueToChar } from "./net";

const style = new TextStyle({
  fontFamily: 'Arial',
  fontSize: 36,
});

const clueNumberStyle = new TextStyle({
  fontFamily: 'Arial',
  fontSize: 10,
});

const textPool = new Pool<Text>(Text);

export class GraphicQuad {
  public container: Container = new Container();
  public graphic: Graphics = new Graphics();
  public characters: Text[] = [];
  public data: number[] = [];
  constructor() {
  }
  update(pos: Point, data: number[]) {
    for(const tex of this.characters) {
      textPool.return(tex);
    }
    this.data = data;
    this.characters = [];

    this.container.removeChildren()
    this.container.pivot.set(-pos.x * GRID_CELL_PX * GRID_SIZE, -pos.y * GRID_CELL_PX * GRID_SIZE);
    this.container.addChild(this.graphic);
    this.graphic.clear();

    for(let i = 0; i < data.length; i++) {
      const px = (i % GRID_SIZE);
      const py = Math.floor(i / GRID_SIZE);

      let index = global.clues.findIndex((clue) => clue && clue.pos.x === (px + pos.x) && clue.pos.y === (py + pos.y))
      const value = data[i];
      const cellValue = cellToValue(value);
      if(isBlocked(value)) {
        this.graphic.
          rect(px * GRID_CELL_PX, py * GRID_CELL_PX, GRID_CELL_PX, GRID_CELL_PX)
          .fill(0x2ffd9);
        continue;
      }
      switch(cellValue) {
        case Value.empty:
          break;
        case Value.black:
          this.graphic.
            rect(px * GRID_CELL_PX, py * GRID_CELL_PX, GRID_CELL_PX, GRID_CELL_PX)
            .fill(0x000000);
          break
        default:
          const c = valueToChar(value);
          const tex = textPool.get()
          tex.anchor.set(0.5, 0.5);
          tex.style = style;
          tex.text = c;
          tex.x = px * GRID_CELL_PX + GRID_CELL_PX / 2;
          tex.y = py * GRID_CELL_PX + GRID_CELL_PX / 2;
          this.container.addChild(tex);
          this.characters.push(tex);
          break;
      }
      if(index !== -1) {
        const tex = textPool.get();
        tex.anchor.set(0, 1);
        tex.style = clueNumberStyle;
        tex.text = index + "";
        tex.x = px * GRID_CELL_PX;
        tex.y = py * GRID_CELL_PX + GRID_CELL_PX;
        this.container.addChild(tex);
        this.characters.push(tex);
      
      }
    }
  }
}
