// Timeline for the Attic film (Apple-style, 66 s at 30 fps). Music is composed to these sections
// (scripts/generate-film-audio.mjs), at 90 BPM so the montage cuts land on the beat.
import { sec } from "./theme";

export const FILM_SECONDS = 66;
export const FILM_TOTAL = sec(FILM_SECONDS);
export const BEAT = 60 / 90; // seconds

export type Clip = { file: string; from: number; to: number };

export type Beat = {
  id: string;
  start: number; // seconds
  end: number;
  lines: string[]; // headline, one entry per line
  accent?: number; // which line gets the gradient
  sub?: string;
  clip: Clip;
  side: "left" | "right" | "center";
  dark?: boolean;
};

export const S = {
  open: [0, 4.5],
  reveal: [4.5, 9],
  hero: [9, 15],
  montage: [52, 56],
  end: [56, 66],
} as const;

export const BEATS: Beat[] = [
  { id: "folders", start: 15, end: 21.5, lines: ["Every folder.", "Finally clear."], accent: 1, side: "left",
    sub: "Big thumbnails, folder sizes and a path you can click.", clip: { file: "rec/folders.mp4", from: 1.2, to: 7.9 } },
  { id: "search", start: 21.5, end: 28, lines: ["Find anything.", "Just say it."], accent: 1, side: "right",
    sub: "Plain English. Even the words inside your screenshots.", clip: { file: "rec/search.mp4", from: 0.8, to: 7.5 } },
  { id: "looks", start: 28, end: 33, lines: ["Playful.", "Or Minimal."], accent: 0, side: "center",
    clip: { file: "rec/looks.mp4", from: 0.4, to: 5.6 } },
  { id: "cleanup", start: 33, end: 39.5, lines: ["Gigabytes back.", "Safely."], accent: 1, side: "left",
    sub: "Clean Up, Duplicates and Deep Clean. Everything goes to the Trash first.", clip: { file: "rec/cleanup.mp4", from: 0.3, to: 7.0 } },
  { id: "offload", start: 39.5, end: 46, lines: ["Big files.", "Your cloud."], accent: 1, side: "right",
    sub: "Cloudflare R2 or iCloud Drive. A placeholder stays behind.", clip: { file: "rec/offload.mp4", from: 1.0, to: 7.7 } },
  { id: "ai", start: 46, end: 52, lines: ["Intelligence.", "On your Mac."], accent: 1, side: "left", dark: true,
    sub: "Apple Intelligence and Apple Vision run on device. Nothing is uploaded.", clip: { file: "rec/ai.mp4", from: 4.9, to: 10.9 } },
];

export const MONTAGE = ["shots/home.jpg", "shots/folder-downloads.jpg", "shots/screenshots.jpg", "shots/duplicates.jpg",
  "shots/deep-clean.jpg", "shots/home-minimal.jpg"];
