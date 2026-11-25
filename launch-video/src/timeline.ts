// Scene timing (seconds) matched to the music's sections: Tension 0–4, Reveal 4–7, Groove 7–39, Lift 39–48, Outro 48–54.
import { FPS } from "./theme";

export const TOTAL = Math.round(54 * FPS);

export type Clip = { file: string; from: number; to: number; rate: number; tag?: string };

export type Feature = {
  start: number;
  end: number;
  kicker: string;
  icon: string; // emoji-free glyph drawn as text
  title: string;
  sub: string;
  /** One clip, or several played back to back (e.g. normal speed, then a sped-up wait, then the result). */
  clip: Clip | Clip[];
  /** Camera push-in: zoom to `z` around (x%, y%) of the window. */
  focus?: { x: number; y: number; z: number };
};

export const T = {
  coldOpen: [0, 4],
  reveal: [4, 7],
  montage: [43.5, 48],
  end: [48, 54],
} as const;

/** Recordings live in public/rec (made by branding/demo/run-tour.sh, then scripts/prep-clips.sh). */
export const FEATURES: Feature[] = [
  {
    start: 7, end: 15, kicker: "Plain-English search", icon: "⌕",
    title: "Search the way\nyou talk.",
    sub: "Even the words inside your screenshots.",
    clip: { file: "rec/search.mp4", from: 0.9, to: 14.1, rate: 1.65 },
    focus: { x: 78, y: 18, z: 1.32 },
  },
  {
    start: 15, end: 21.5, kicker: "Clean Up", icon: "✦",
    title: "Find the gigabytes\nyou forgot about.",
    sub: "Old downloads, installers, duplicates. You review first.",
    clip: { file: "rec/cleanup.mp4", from: 0.4, to: 8.9, rate: 1.3 },
    focus: { x: 62, y: 22, z: 1.24 },
  },
  {
    start: 21.5, end: 26, kicker: "Deep Clean", icon: "⚒",
    title: "node_modules, Xcode builds,\ncaches. Gone.",
    sub: "Everything here rebuilds itself when you need it.",
    clip: { file: "rec/cleanup.mp4", from: 8.9, to: 15.4, rate: 1.43 },
    focus: { x: 60, y: 18, z: 1.3 },
  },
  {
    start: 26, end: 31, kicker: "Memory & Swap", icon: "▦",
    title: "Swap is eating\nyour disk.",
    sub: "See which apps to quit, and get those gigabytes back.",
    clip: { file: "rec/memory.mp4", from: 0.3, to: 7.4, rate: 1.42 },
    focus: { x: 58, y: 28, z: 1.28 },
  },
  {
    start: 31, end: 39, kicker: "Offload", icon: "☁",
    title: "Big files live in\nthe cloud now.",
    sub: "Cloudflare R2 or iCloud Drive. A placeholder stays behind; double-click to bring it back.",
    clip: [
      { file: "rec/offload.mp4", from: 4.3, to: 8.3, rate: 1.4 },
      { file: "rec/offload.mp4", from: 8.3, to: 56.8, rate: 18, tag: "real upload · 18× speed" },
      { file: "rec/offload.mp4", from: 56.8, to: 63.2, rate: 2.5 },
    ],
    focus: { x: 56, y: 16, z: 1.34 },
  },
  {
    start: 39, end: 43.5, kicker: "Quick Search", icon: "⌘",
    title: "⇧⌘Space.\nFrom any app.",
    sub: "Find any file without leaving what you're doing.",
    clip: { file: "rec/quicksearch.mp4", from: 0.6, to: 9.2, rate: 1.9 },
    focus: { x: 52, y: 18, z: 1.36 },
  },
];

/** Where sound effects land (seconds). */
export const SFX: { at: number; name: string; volume?: number }[] = [
  { at: 0.35, name: "tick", volume: 0.5 },
  { at: 1.35, name: "tick", volume: 0.5 },
  { at: 2.35, name: "tick", volume: 0.55 },
  { at: 3.3, name: "riser", volume: 0.35 },
  { at: 4.0, name: "shimmer", volume: 0.6 },
  { at: 4.05, name: "impact-soft", volume: 0.5 },
  ...FEATURES.map((f) => ({ at: f.start - 0.05, name: "whoosh", volume: 0.45 })),
  { at: 7.7, name: "typing", volume: 0.25 },
  { at: 36.6, name: "chime", volume: 0.45 },
  { at: 43.45, name: "swipe", volume: 0.45 },
  { at: 48.0, name: "impact-soft", volume: 0.55 },
  { at: 48.05, name: "shimmer", volume: 0.5 },
];
