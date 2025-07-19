export class Debounce {
  private timeoutId: ReturnType<typeof setTimeout> | null = null;
  constructor(
    private readonly delay: number,
    private readonly handler: () => void,
  ) {}

  public trigger(): void {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId);
    }
    this.timeoutId = setTimeout(() => {
      this.handler();
      this.timeoutId = null;
    }, this.delay);
  }
}

export class Throttle {
  private lastExecution: number = 0;
  private timeoutID: ReturnType<typeof setTimeout> | null = null;
  constructor(
    private readonly delay: number,
    private readonly handler: () => void,
  ) {}

  public trigger(): void {
    let now = Date.now();
    if (now - this.lastExecution >= this.delay) {
      this.handler();
      this.lastExecution = now;
      return;
    }
    if (this.timeoutID) {
      clearTimeout(this.timeoutID);
    }
    this.timeoutID = setTimeout(() => {
      this.handler();
      now = Date.now();
      if(now - this.lastExecution >= this.delay) {
        this.trigger();
      } else {
        this.lastExecution = Date.now();
      }
      this.timeoutID = null;
    }, now - this.lastExecution);
  }
}
