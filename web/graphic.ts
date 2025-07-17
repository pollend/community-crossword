import { Graphics, Rectangle } from "pixi.js";

export function graphicDrawRect(graphics: Graphics, rect: Rectangle) {
  return graphics
    .moveTo(rect.x, rect.y)
    .lineTo(rect.x + rect.width, rect.y)
    .lineTo(rect.x + rect.width, rect.y + rect.height)
    .lineTo(rect.x, rect.y + rect.height)
    .lineTo(rect.x, rect.y)
    .lineTo(rect.x, rect.y);
}
