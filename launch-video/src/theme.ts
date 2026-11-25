import { loadFont as loadJakarta } from "@remotion/google-fonts/PlusJakartaSans";
import { loadFont as loadInter } from "@remotion/google-fonts/Inter";
import { Easing, interpolate } from "remotion";

export const JAKARTA = loadJakarta("normal", { weights: ["600", "700", "800"], subsets: ["latin"] }).fontFamily;
export const INTER = loadInter("normal", { weights: ["400", "500", "600"], subsets: ["latin"] }).fontFamily;

export const FPS = 30;
export const W = 1920;
export const H = 1080;

export const C = {
  bg: "#0D090C",
  ink: "#FFFFFF",
  dim: "rgba(255,255,255,0.62)",
  faint: "rgba(255,255,255,0.10)",
  amber: "#FFC04D",
  orange: "#FF7E45",
  coral: "#F2466B",
  pink: "#EE4472",
  cyan: "#5CD6E8",
  red: "#FF453A",
};

export const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const E = {
  out: Easing.out(Easing.cubic),
  outQuint: Easing.out(Easing.poly(5)),
  inOut: Easing.inOut(Easing.cubic),
  in: Easing.in(Easing.cubic),
  back: Easing.out(Easing.back(1.6)),
};

/** 0 → 1 between frames a and b. */
export const prog = (f: number, a: number, b: number, easing = E.out) => interpolate(f, [a, b], [0, 1], { ...CLAMP, easing });
export const sec = (s: number) => Math.round(s * FPS);
