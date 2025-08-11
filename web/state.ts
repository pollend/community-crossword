import { writable, Writable } from "svelte/store";
import { HighscoreTable } from "./highscoreTable";
import { calculateScore, Value } from "./net";
import { UNIQUE_STR } from "./constants";

interface Solves {
  timestamp: number; // UTC timestamp in seconds
  word: Value[];
  clue: string;
  score: number;
}

export class Global {
  public socket: WebSocket | null = null;
  public globalHighScore: HighscoreTable | null = null;

  public nick: Writable<string> = writable("");
  public num_clues: Writable<number> = writable(0);
  public score: Writable<number> = writable(0);
  public words_solved: Writable<Solves[]> = writable([]);

  update_clue(word: Value[], clue: string) {
    this.words_solved.update((solved) => {
      solved.push({
        timestamp: new Date().getUTCSeconds(),
        word: word,
        clue: clue,
        score: calculateScore(word),
      });
      return solved;
    });
    this.num_clues.update((n) => n + 1);
    this.score.update((s) => s + calculateScore(word));
  }

  initialize(session_id: number) {
    const current_session_uid = Number(
      window.localStorage.getItem(`uid-${UNIQUE_STR}`) || "0",
    );
    if (current_session_uid !== session_id) {
      window.localStorage.setItem(`uid-${UNIQUE_STR}`, String(session_id));
      window.localStorage.setItem(`words_solved-${UNIQUE_STR}`, "[]");
      this.words_solved.set([]);
    }
    this.nick.subscribe((nick) => {
      window.localStorage.setItem(`nick-${UNIQUE_STR}`, nick);
    });
    this.words_solved.set(
      JSON.parse(
        window.localStorage.getItem(`words_solved-${UNIQUE_STR}`) || "[]",
      ),
    );
    this.words_solved.subscribe((solves) => {
      window.localStorage.setItem(
        `words_solved-${UNIQUE_STR}`,
        JSON.stringify(solves),
      );
    });
  }
}
