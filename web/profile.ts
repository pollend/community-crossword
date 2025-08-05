import { writable, Writable } from "svelte/store";
import { PROFILE_MAGIC } from "./constants";

interface Solves {
  timestamp: Date; // UTC timestamp in seconds 
  word: string;
  clue: string;
}

export const enum ProfileVersion{
  unknown = 0,
  v0000 = 1, // Initial version
}

export class ProfileSession {
  private id: string;
  public timestamp: Writable<number> = writable(Date.now());
  public nick: Writable<string> = writable("");
  public num_clues: Writable<number> = writable(0);
  public score: Writable<number> = writable(0);
  public words_solved: Writable<Solves[]> = writable([]);
  public loaded: Writable<boolean> = writable(false);
  public last_updated: Writable<Date | undefined> = writable(undefined);

  constructor() {

  }

  public async refresh() {

  }

  public async load(session: string){
    this.id = session;
    const response = await fetch(`${import.meta.env.VITE_APP_S3}/profile/${session}.profile`)
    if(response.ok) {
      const data = await response.arrayBuffer();
      const view = new DataView(data);
      let offset = 0;
      const magic = view.getUint32(offset, true);
      if( magic !== PROFILE_MAGIC) return;
      offset += 4;
      const version = view.getUint16(offset, true);
      offset += 2;
      switch(version) {
        case ProfileVersion.v0000:
          let last_update = view.getBigInt64(offset, true);
          this.last_updated.set(new Date(Number(last_update)));
          offset += 8;
          var nick_len = view.getUint16(offset, true);
          offset += 2;
          this.nick.set(new TextDecoder().decode(data.slice(offset, offset + nick_len)));
          offset += nick_len;
          this.num_clues.set(view.getUint32(offset, true));
          offset += 4;
          this.score.set(view.getUint32(offset, true));
          offset += 4;
          const num_solves = view.getUint16(offset, true);
          offset += 2;
          for(let i = 0; i < num_solves; i++) {
            const utc = view.getBigInt64(offset, true);
            offset += 8;
            const word_len = view.getUint16(offset, true);
            offset += 2;
            const word = new TextDecoder().decode(data.slice(offset, offset + word_len));
            offset += word_len;
            const clue_len = view.getUint16(offset, true);
            offset += 2;
            const clue = new TextDecoder().decode(data.slice(offset, offset + clue_len));
            offset += clue_len;
            this.words_solved.update((solves) => {
              solves.push({ timestamp: new Date(Number(utc)), word: word, clue: clue });
              return solves;
            });    
          }
          break;
        default:
          console.error(`Unknown profile version: ${version}`);
          return;
      }
      this.loaded.set(true);
    }
    //const response = await fetch(`/api/profile/session/${session}`);
    //if (!response.ok) {
    //  throw new Error(`Failed to fetch session: ${response.statusText}`);
    //}
    //const data = await response.json();
    //return new ProfileSession(data);
  }

} 
