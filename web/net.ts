
export enum MessageID {
  SetView = 0,
  SyncBlock = 1,
}

export function netSendViewRect(ws: WebSocket, x: number, y: number, width: number, height: number) {
  // 1 byte for ID, 4 bytes each for x, y, width, height 
  const buffer = new ArrayBuffer(1 + 4 + 4 + 4 + 4); 
  let offset = 0;
  const view = new DataView(buffer);
  view.setUint8(offset, MessageID.SetView);
  offset += 1;
  view.setUint32(offset, x, true);
  offset += 4;
  view.setUint32(offset, y, true);
  offset += 4;
  view.setUint32(offset, width, true);
  offset += 4;
  view.setUint32(offset, height, true);
  ws.send(buffer);
}
