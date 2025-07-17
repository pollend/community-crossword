import { Container, Graphics, GraphicsContext, Point , Pool, Text, TextStyle} from "pixi.js";
import { GRID_CELL_PX, GRID_SIZE } from "./state";
import { cellToValue, Value, valueToChar } from "./net";



const style = new TextStyle({
  fontFamily: 'Arial',
  fontSize: 36,
});

const textPool = new Pool<Text>(Text);

export class GraphicQuad {
  public container: Container = new Container();
  public graphic: Graphics = new Graphics();
  public characters: Text[] = [];
  constructor() {
  }
  update(pos: Point, data: number[]) {
    for(const tex of this.characters) {
      textPool.return(tex);
    }
    this.characters = [];

    this.container.removeChildren()
    this.container.pivot.set(-pos.x * GRID_CELL_PX * GRID_SIZE, -pos.y * GRID_CELL_PX * GRID_SIZE);
    this.container.addChild(this.graphic);
    this.graphic.clear();

    for(let i = 0; i < data.length; i++) {
      const px = (i % GRID_SIZE);
      const py = Math.floor(i / GRID_SIZE);
      const value = data[i];
      const cellValue = cellToValue(value);
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
      
    }
  }
}
