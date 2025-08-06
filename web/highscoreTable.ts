import { writable, Writable } from "svelte/store";
import { HIGHSCORE_MAGIC_NUMBER } from "./constants";
import { Value } from "./net";

export interface HighscoreEntry {
  nick: string;
  lastWord: Value[];
  score: number;
  numWordsSolved: number;
}

export const enum HighscoreVersion {
  unknown = 0,
  v0000 = 1, // Initial version
}

export class HighscoreTable {
  public entries: Writable<HighscoreEntry[]> = writable([]);

  constructor(private readonly base: string) {
  }

  public async refresh() {
    try {
      const response = await fetch(
        `${import.meta.env.VITE_APP_S3}/${this.base}.highscore`,
      );
      
      if (!response.ok) {
        console.warn(`Failed to fetch highscores: ${response.status} ${response.statusText}`);
        return;
      }

      this.entries.set([]); 
      const data = await response.arrayBuffer();
      const view = new DataView(data);
      let offset = 0;

      // Read magic number
      const magic = view.getUint32(offset, true); // little endian
      offset += 4;
      
      if (magic !== HIGHSCORE_MAGIC_NUMBER) {
        console.error('Invalid highscore file magic number');
        return [];
      }

      // Read version
      const version = view.getUint16(offset, true);
      offset += 2;

      if (version !== HighscoreVersion.v0000) {
        console.error(`Unsupported highscore version: ${version}`);
        return [];
      }

      // Read number of entries
      const numEntries = view.getUint16(offset, true);
      offset += 2;

      for (let i = 0; i < numEntries; i++) {
        // Read nick length and nick
        const nickLen = view.getUint16(offset, true);
        offset += 2;
        const nick = new TextDecoder().decode(data.slice(offset, offset + nickLen));
        offset += nickLen;

        // Read last word length and last word
        const lastWordLen = view.getUint16(offset, true);
        offset += 2;
        let lastWord: Value[] = [];
        for( let j = 0; j < lastWordLen; j++) {
          lastWord.push(view.getUint8(offset));
          offset += 1;
        }

        const score = view.getUint32(offset, true);
        offset += 4;
        const numWordsSolved = view.getUint32(offset, true);
        offset += 4;
        this.entries.update((en) => {
          en.push({
            nick,
            lastWord,
            score,
            numWordsSolved,
          });
          return en;
        }) 
      }
    } catch (error) {
      console.error('Error loading highscores:', error);
    }
  }
}
