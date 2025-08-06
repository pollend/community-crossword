import { writable, Writable } from "svelte/store";
import { PROFILE_MAGIC } from "./constants";
import { Value } from "./net";

interface Solves {
  timestamp: Date; // UTC timestamp in seconds
  word: Value[];
  clue: string;
  score: number;
}

export const enum ProfileVersion {
  unknown = 0,
  v0000 = 1, // Initial version
}

export function wordValue(c: Value): number {
  switch (c) {
    case Value.a:
    case Value.e:
    case Value.i:
    case Value.o:
    case Value.u:
    case Value.l:
    case Value.n:
    case Value.s:
    case Value.t:
    case Value.r:
      return 1;
    case Value.d:
    case Value.g:
      return 2;
    case Value.b:
    case Value.c:
    case Value.m:
    case Value.p:
      return 3;
    case Value.f:
    case Value.h:
    case Value.v:
    case Value.w:
    case Value.y:
      return 4;
    case Value.k:
      return 5;
    case Value.j:
    case Value.x:
      return 8;
    case Value.q:
    case Value.z:
      return 10;
  }
  return 0;
}

function calculateScore(word: Value[]): number {
  let score = 0;
  for (let i = 0; i < word.length; i++) {
    score += wordValue(word[i]) || 0;
  }
  return score;
}

export class ProfileSession {
  private id: string | undefined = undefined;
  public timestamp: Writable<number> = writable(Date.now());
  public nick: Writable<string> = writable("");
  public num_clues: Writable<number> = writable(0);
  public score: Writable<number> = writable(0);
  public words_solved: Writable<Solves[]> = writable([]);
  public loaded: Writable<boolean> = writable(false);
  public last_updated: Writable<Date | undefined> = writable(undefined);

  constructor() {}

  public async refresh() {
    if (!this.id) {
      throw new Error("Session ID is not set");
    }
    await this.load(this.id);
  }

  public push(word: Value[], clue: string) {
    this.words_solved.update((solves) => {
      solves.push({
        timestamp: new Date(),
        word: word,
        clue: clue,
        score: calculateScore(word),
      });
      return solves;
    });
  }

  public async load(session: string) {
    this.words_solved.set([]);
    this.loaded.set(false);
    this.id = session;
    const response = await fetch(
      `${import.meta.env.VITE_APP_S3}/profile/${session}.profile`,
    );
    if (response.ok) {
      const data = await response.arrayBuffer();
      const view = new DataView(data);
      let offset = 0;
      const magic = view.getUint32(offset, true);
      if (magic !== PROFILE_MAGIC) return;
      offset += 4;
      const version = view.getUint16(offset, true);
      offset += 2;
      switch (version) {
        case ProfileVersion.v0000: {
          const last_update = view.getBigInt64(offset, true);
          this.last_updated.set(new Date(Number(last_update) * 1000));
          offset += 8;
          const nick_len = view.getUint16(offset, true);
          offset += 2;
          this.nick.set(
            new TextDecoder().decode(data.slice(offset, offset + nick_len)),
          );
          offset += nick_len;
          this.num_clues.set(view.getUint32(offset, true));
          offset += 4;
          this.score.set(view.getUint32(offset, true));
          offset += 4;
          const num_solves = view.getUint16(offset, true);
          offset += 2;
          for (let i = 0; i < num_solves; i++) {
            const utc = view.getBigInt64(offset, true);
            offset += 8;
            const word_len = view.getUint16(offset, true);
            offset += 2;
            const word: Value[] = []; //data.slice(offset, offset + word_len);
            for (let j = 0; j < word_len; j++) {
              word.push(view.getUint8(offset));
              offset += 1;
            }
            const clue_len = view.getUint16(offset, true);
            offset += 2;
            const clue = new TextDecoder().decode(
              data.slice(offset, offset + clue_len),
            );
            offset += clue_len;
            this.words_solved.update((solves) => {
              solves.push({
                timestamp: new Date(Number(utc) * 1000),
                word: word,
                clue: clue,
                score: calculateScore(word),
              });
              return solves;
            });
          }
          break;
        }
        default:
          console.error(`Unknown profile version: ${version}`);
          return;
      }
      this.loaded.set(true);
    }
  }
}
