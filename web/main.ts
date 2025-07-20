import App from "./app.svelte";
import { mount } from "svelte";
import "./app.css";

mount(App, {
  target: document.getElementById("app")!,
});
