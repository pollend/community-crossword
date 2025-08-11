import { writable, Writable } from "svelte/store";
import { Value } from "./net";

interface Solves {
  timestamp: number; // UTC timestamp in seconds
  word: Value[];
  clue: string;
  score: number;
}

export const enum ProfileVersion {
  unknown = 0,
  v0000 = 1, // Initial version
}

export class ProfileSession {
  public nick: Writable<string> = writable("");
  public num_clues: Writable<number> = writable(0);
  public score: Writable<number> = writable(0);
  public words_solved: Writable<Solves[]> = writable([]);
  //public last_updated: Writable<Date | undefined> = writable(undefined);

  constructor() {
    this.words_solved.set(
      JSON.parse(window.localStorage.getItem("words_solved") || "[]"),
    );
    this.words_solved.subscribe((solves) => {
      window.localStorage.setItem("words_solved", JSON.stringify(solves));
    });
  }

  //  public push(word: Value[], clue: string) {
  //    this.words_solved.update((solves) => {
  //      solves.push({
  //        timestamp: new Date().getUTCSeconds(),
  //        word: word,
  //        clue: clue,
  //        score: calculateScore(word),
  //      });
  //      return solves;
  //    });
  //  }

  //public async load(session: string) {
  //  this.words_solved.set([]);
  //  this.loaded.set(false);
  //  this.id = session;
  //  const response = await fetch(
  //    `${import.meta.env.VITE_APP_S3}/profile/${session}.profile`,
  //  );
  //  if (response.ok) {
  //    const data = await response.arrayBuffer();
  //    const view = new DataView(data);
  //    let offset = 0;
  //    const magic = view.getUint32(offset, true);
  //    if (magic !== PROFILE_MAGIC) return;
  //    offset += 4;
  //    const version = view.getUint16(offset, true);
  //    offset += 2;
  //    switch (version) {
  //      case ProfileVersion.v0000: {
  //        const last_update = view.getBigInt64(offset, true);
  //        this.last_updated.set(new Date(Number(last_update) * 1000));
  //        offset += 8;
  //        const nick_len = view.getUint16(offset, true);
  //        offset += 2;
  //        this.nick.set(
  //          new TextDecoder().decode(data.slice(offset, offset + nick_len)),
  //        );
  //        offset += nick_len;
  //        this.num_clues.set(view.getUint32(offset, true));
  //        offset += 4;
  //        this.score.set(view.getUint32(offset, true));
  //        offset += 4;
  //        const num_solves = view.getUint16(offset, true);
  //        offset += 2;
  //        for (let i = 0; i < num_solves; i++) {
  //          const utc = view.getBigInt64(offset, true);
  //          offset += 8;
  //          const word_len = view.getUint16(offset, true);
  //          offset += 2;
  //          const word: Value[] = []; //data.slice(offset, offset + word_len);
  //          for (let j = 0; j < word_len; j++) {
  //            word.push(view.getUint8(offset));
  //            offset += 1;
  //          }
  //          const clue_len = view.getUint16(offset, true);
  //          offset += 2;
  //          const clue = new TextDecoder().decode(
  //            data.slice(offset, offset + clue_len),
  //          );
  //          offset += clue_len;
  //          this.words_solved.update((solves) => {
  //            solves.push({
  //              timestamp: new Date(Number(utc) * 1000),
  //              word: word,
  //              clue: clue,
  //              score: calculateScore(word),
  //            });
  //            return solves;
  //          });
  //        }
  //        break;
  //      }
  //      default:
  //        console.error(`Unknown profile version: ${version}`);
  //        return;
  //    }
  //    this.loaded.set(true);
  //  }
  //}
}
