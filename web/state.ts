import { writable, Writable } from "svelte/store";
import { HighscoreTable } from "./highscoreTable";
import { Value } from "./net";
import { ProfileSession } from "./profile";
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
  public profile: ProfileSession | null = null;

  public nick: Writable<string> = writable("");
  public num_clues: Writable<number> = writable(0);
  public score: Writable<number> = writable(0);
  public words_solved: Writable<Solves[]> = writable([]);
  private uid: number = 0;

  initialize(uid: number) {
    this.uid = uid;
    const old_uid = Number(window.localStorage.getItem(`uid-${UNIQUE_STR}`) || "0");
    if(this.uid !== old_uid) {
      window.localStorage.setItem("uid", String(this.uid));
      window.localStorage.setItem("words_solved", "[]");
      this.words_solved.set([]); // Reset the words solved for the new user
    }
    this.nick.subscribe((nick) => {
      window.localStorage.setItem(`nick-${UNIQUE_STR}`, nick);
    })
    this.words_solved.set(
      JSON.parse(window.localStorage.getItem(`words_solved-${UNIQUE_STR}`) || "[]"),
    );
    this.words_solved.subscribe((solves) => {
      window.localStorage.setItem("words_solved", JSON.stringify(solves));
    });
  }
}
