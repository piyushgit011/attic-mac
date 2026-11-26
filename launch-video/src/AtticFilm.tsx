// The Attic film: an Apple-style product film (16:9, 66 s). Every product shot is a real recording of Attic
// running on a made-up demo library (branding/demo); type, motion and the end card are composed here.
import React from "react";
import { AbsoluteFill, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Audio, Video } from "@remotion/media";
import { CLAMP, E, FPS, INTER, prog, sec } from "./theme";
import { BEAT, BEATS, Beat, Clip, FILM_TOTAL, MONTAGE, S } from "./film";

const DISPLAY = `"SF Pro Display", -apple-system, BlinkMacSystemFont, "${INTER}", system-ui, sans-serif`;
const TEXT = `"SF Pro Text", -apple-system, BlinkMacSystemFont, "${INTER}", system-ui, sans-serif`;
const INK = "#1d1d1f";
const PAPER = "#fbfbfd";
const DIM = "#6e6e73";
const GRAD = "linear-gradient(100deg, #ffa24a 0%, #ff6b4a 45%, #e8396b 100%)";

const gradText: React.CSSProperties = { backgroundImage: GRAD, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent" };

/** Fade a whole scene in and out over a few frames. */
const useSceneFade = (dur: number, fadeIn = 9, fadeOut = 9) => {
  const f = useCurrentFrame();
  return Math.min(prog(f, 0, fadeIn, E.out), 1 - prog(f, dur - fadeOut, dur, E.in));
};

/** Apple-style reveal: each word rises, sharpens and fades in. */
const Words: React.FC<{ text: string; at: number; size: number; weight?: number; color?: string; grad?: boolean; stagger?: number; tracking?: number }> =
  ({ text, at, size, weight = 600, color = INK, grad = false, stagger = 3, tracking = -0.035 }) => {
    const f = useCurrentFrame();
    return (
      <span style={{ display: "inline-flex", flexWrap: "wrap", columnGap: size * 0.24 }}>
        {text.split(" ").map((w, i) => {
          const p = prog(f, at + i * stagger, at + i * stagger + 16, E.outQuint);
          return (
            <span key={i} style={{ fontFamily: DISPLAY, fontWeight: weight, fontSize: size, letterSpacing: `${tracking}em`, lineHeight: 1.05,
              opacity: p, transform: `translateY(${(1 - p) * size * 0.28}px)`, filter: p < 1 ? `blur(${(1 - p) * 12}px)` : undefined,
              ...(grad ? gradText : { color }) }}>{w}</span>
          );
        })}
      </span>
    );
  };

/** A window recording with rounded corners and a soft studio shadow, optionally in 3D. */
const AppWindow: React.FC<{ clip?: Clip; img?: string; width: number; rotX?: number; rotY?: number; scale?: number; dark?: boolean }> =
  ({ clip, img, width, rotX = 0, rotY = 0, scale = 1, dark = false }) => (
    <div style={{ width, height: width * 0.625, borderRadius: width * 0.0125, overflow: "hidden", background: "#f2f2f4",
      transform: `perspective(2600px) rotateX(${rotX}deg) rotateY(${rotY}deg) scale(${scale})`,
      boxShadow: dark ? "0 50px 140px rgba(255,120,80,0.16), 0 0 0 1px rgba(255,255,255,0.10)"
        : "0 60px 140px rgba(30,20,40,0.22), 0 12px 30px rgba(30,20,40,0.10), 0 0 0 1px rgba(0,0,0,0.06)" }}>
      {clip ? (
        <Video src={staticFile(clip.file)} muted trimBefore={Math.round(clip.from * FPS)} trimAfter={Math.round(clip.to * FPS)}
          style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
      ) : img ? (
        <Img src={staticFile(img)} style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
      ) : null}
    </div>
  );

// ── 1. Open: two quiet lines on black ─────────────────────────────────────────────────────────────────
const Open: React.FC = () => {
  const dur = sec(S.open[1] - S.open[0]);
  const fade = useSceneFade(dur, 1, 12);
  return (
    <AbsoluteFill style={{ background: "#000", alignItems: "center", justifyContent: "center", opacity: fade }}>
      <div style={{ textAlign: "center" }}>
        <div><Words text="Every file you’ve ever kept." at={sec(0.4)} size={84} color="#f5f5f7" /></div>
        <div style={{ marginTop: 18 }}><Words text="Somewhere on your Mac." at={sec(1.9)} size={84} color="#86868b" /></div>
      </div>
    </AbsoluteFill>
  );
};

// ── 2. Reveal: the icon in a bloom of light ───────────────────────────────────────────────────────────
const RevealScene: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const dur = sec(S.reveal[1] - S.reveal[0]);
  const s = spring({ frame: f - 4, fps, config: { damping: 18, mass: 1.1, stiffness: 90 } });
  const bloom = prog(f, 0, sec(1.6), E.out);
  const whiteOut = prog(f, dur - 10, dur, E.in);
  const sweep = interpolate(f, [sec(1.0), sec(2.2)], [-120, 120], CLAMP);
  return (
    <AbsoluteFill style={{ background: "#000", alignItems: "center", justifyContent: "center" }}>
      <AbsoluteFill style={{ background: `radial-gradient(42% 38% at 50% 40%, rgba(255,140,70,${0.42 * bloom}) 0%, rgba(232,57,107,${0.22 * bloom}) 45%, transparent 75%)` }} />
      <div style={{ position: "relative", width: 300, height: 300, transform: `scale(${0.7 + s * 0.3}) translateY(${(1 - s) * 40}px)`, opacity: Math.min(1, s * 1.4), marginTop: -120 }}>
        <Img src={staticFile("attic-icon.png")} style={{ width: 300, height: 300, filter: "drop-shadow(0 30px 60px rgba(232,57,107,0.45))" }} />
        <div style={{ position: "absolute", inset: 30, borderRadius: 64, overflow: "hidden", mixBlendMode: "screen", pointerEvents: "none" }}>
          <div style={{ position: "absolute", top: -40, bottom: -40, width: 70, left: `${50 + sweep / 2}%`, transform: "rotate(18deg)",
            background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.55), transparent)", filter: "blur(6px)" }} />
        </div>
      </div>
      <div style={{ position: "absolute", top: 640, width: "100%", textAlign: "center" }}>
        <Words text="Attic" at={sec(1.2)} size={150} weight={700} color="#f5f5f7" tracking={-0.045} />
      </div>
      <div style={{ position: "absolute", top: 830, width: "100%", textAlign: "center" }}>
        <Words text="The Finder alternative." at={sec(2.3)} size={56} weight={500} color="#a1a1a6" stagger={4} tracking={-0.02} />
      </div>
      <AbsoluteFill style={{ background: PAPER, opacity: whiteOut }} />
    </AbsoluteFill>
  );
};

// ── 3. Hero: the window rises in 3D on white ──────────────────────────────────────────────────────────
const Hero: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const dur = sec(S.hero[1] - S.hero[0]);
  const rise = spring({ frame: f - 6, fps, config: { damping: 22, mass: 1.2, stiffness: 70 } });
  const push = interpolate(f, [0, dur], [0, 1], CLAMP);
  const fade = useSceneFade(dur, 1, 10);
  return (
    <AbsoluteFill style={{ background: PAPER, alignItems: "center", opacity: fade }}>
      <div style={{ marginTop: 92, textAlign: "center" }}>
        <Words text="Your files." at={sec(0.5)} size={76} />
        <span style={{ display: "inline-block", width: 22 }} />
        <Words text="Finally easy to see." at={sec(0.9)} size={76} grad />
      </div>
      <div style={{ marginTop: 56, transform: `translateY(${(1 - rise) * 380}px)`, opacity: Math.min(1, rise * 1.5) }}>
        <AppWindow clip={{ file: "rec/home.mp4", from: 0.3, to: 6.3 }} width={1400}
          rotX={(1 - rise) * 34 + 3} scale={0.9 + rise * 0.1 + push * 0.05} />
      </div>
    </AbsoluteFill>
  );
};

// ── 4. Feature beats ──────────────────────────────────────────────────────────────────────────────────
const FeatureBeat: React.FC<{ b: Beat }> = ({ b }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const dur = sec(b.end - b.start);
  const fade = useSceneFade(dur, 8, 8);
  const enter = spring({ frame: f - 3, fps, config: { damping: 20, mass: 1, stiffness: 80 } });
  const drift = interpolate(f, [0, dur], [0, 1], CLAMP);
  const bg = b.dark ? "#000" : PAPER;
  const ink = b.dark ? "#f5f5f7" : INK;
  const sub = b.dark ? "#a1a1a6" : DIM;

  if (b.side === "center") {
    // Two words take turns over one window: "Playful." then "Or Minimal."
    const swap = sec((b.end - b.start) * 0.46);
    const first = 1 - prog(f, swap - 6, swap + 2, E.in);
    return (
      <AbsoluteFill style={{ background: bg, alignItems: "center", opacity: fade }}>
        <div style={{ position: "relative", height: 150, marginTop: 70, width: "100%", textAlign: "center" }}>
          <div style={{ position: "absolute", inset: 0, opacity: first }}><Words text={b.lines[0]} at={sec(0.2)} size={96} grad /></div>
          {f >= swap - 2 && <div style={{ position: "absolute", inset: 0 }}><Words text={b.lines[1]} at={swap} size={96} color={ink} /></div>}
        </div>
        <div style={{ marginTop: 30, transform: `translateY(${(1 - enter) * 160}px) scale(${1.0 + drift * 0.04})`, opacity: enter }}>
          <AppWindow clip={b.clip} width={1340} rotX={4} />
        </div>
      </AbsoluteFill>
    );
  }

  const left = b.side === "left";
  const windowW = 1180;
  return (
    <AbsoluteFill style={{ background: bg, opacity: fade, flexDirection: left ? "row" : "row-reverse", alignItems: "center" }}>
      {b.dark && <AbsoluteFill style={{ background: "radial-gradient(50% 60% at 72% 50%, rgba(255,120,80,0.18), transparent 70%)" }} />}
      <div style={{ width: 640, padding: left ? "0 0 0 120px" : "0 120px 0 0", boxSizing: "content-box", position: "relative" }}>
        {b.lines.map((l, i) => (
          <div key={i} style={{ marginTop: i ? 6 : 0 }}>
            <Words text={l} at={sec(0.25 + i * 0.35)} size={b.lines.some((x) => x.length > 18) ? 70 : 84} color={ink} grad={i === b.accent} />
          </div>
        ))}
        {b.sub && (
          <div style={{ marginTop: 30, fontFamily: TEXT, fontSize: 30, lineHeight: 1.35, color: sub, maxWidth: 560,
            opacity: prog(f, sec(1.0), sec(1.5)), transform: `translateY(${(1 - prog(f, sec(1.0), sec(1.5))) * 14}px)` }}>{b.sub}</div>
        )}
      </div>
      <div style={{ position: "relative", marginLeft: left ? 30 : -260, marginRight: left ? -260 : 30,
        transform: `translateX(${(1 - enter) * (left ? 260 : -260)}px)`, opacity: Math.min(1, enter * 1.4) }}>
        <AppWindow clip={b.clip} width={windowW} dark={b.dark}
          rotY={(left ? -1 : 1) * (14 - enter * 6 - drift * 3)} scale={0.98 + drift * 0.03} />
      </div>
    </AbsoluteFill>
  );
};

// ── 5. Montage: one screen per beat ───────────────────────────────────────────────────────────────────
const Montage: React.FC = () => {
  const f = useCurrentFrame();
  const per = sec(BEAT);
  const i = Math.min(MONTAGE.length - 1, Math.floor(f / per));
  const local = f - i * per;
  const pop = prog(local, 0, 8, E.outQuint);
  const dark = i % 2 === 1;
  return (
    <AbsoluteFill style={{ background: dark ? "#000" : PAPER, alignItems: "center", justifyContent: "center" }}>
      <div style={{ transform: `scale(${1.06 - pop * 0.06})`, opacity: 0.4 + pop * 0.6 }}>
        <AppWindow img={MONTAGE[i]} width={1500} dark={dark} />
      </div>
    </AbsoluteFill>
  );
};

// ── 6. End card ───────────────────────────────────────────────────────────────────────────────────────
const End: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const dur = sec(S.end[1] - S.end[0]);
  const s = spring({ frame: f - 4, fps, config: { damping: 16, mass: 1, stiffness: 90 } });
  const out = prog(f, dur - sec(1.4), dur, E.in);
  return (
    <AbsoluteFill style={{ background: "#000", alignItems: "center", justifyContent: "center" }}>
      <AbsoluteFill style={{ background: "radial-gradient(40% 36% at 50% 34%, rgba(255,140,70,0.26), transparent 72%)", opacity: s }} />
      <div style={{ textAlign: "center", opacity: 1 - out, marginTop: -40 }}>
        <Img src={staticFile("attic-icon.png")} style={{ width: 210, height: 210, transform: `scale(${0.75 + s * 0.25})`, opacity: s,
          filter: "drop-shadow(0 26px 50px rgba(232,57,107,0.4))" }} />
        <div style={{ marginTop: 26 }}><Words text="Attic" at={sec(0.6)} size={124} weight={700} color="#f5f5f7" tracking={-0.045} /></div>
        <div style={{ marginTop: 18 }}><Words text="The Finder alternative that frees up your Mac." at={sec(1.3)} size={44} weight={500} color="#a1a1a6" stagger={2} tracking={-0.015} /></div>
        <div style={{ marginTop: 44 }}><Words text="Free and open source." at={sec(2.4)} size={60} weight={600} grad stagger={3} /></div>
        <div style={{ marginTop: 40, fontFamily: TEXT, fontSize: 30, color: "#86868b", letterSpacing: "-0.01em",
          opacity: prog(f, sec(3.4), sec(4.0)) }}>github.com/piyushgit011/attic-mac</div>
      </div>
    </AbsoluteFill>
  );
};

export const AtticFilm: React.FC = () => {
  const at = (s: number) => sec(s);
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <Sequence from={at(S.open[0])} durationInFrames={at(S.open[1] - S.open[0])}><Open /></Sequence>
      <Sequence from={at(S.reveal[0])} durationInFrames={at(S.reveal[1] - S.reveal[0])}><RevealScene /></Sequence>
      <Sequence from={at(S.hero[0])} durationInFrames={at(S.hero[1] - S.hero[0])}><Hero /></Sequence>
      {BEATS.map((b) => (
        <Sequence key={b.id} from={at(b.start)} durationInFrames={at(b.end - b.start)}><FeatureBeat b={b} /></Sequence>
      ))}
      <Sequence from={at(S.montage[0])} durationInFrames={at(S.montage[1] - S.montage[0])}><Montage /></Sequence>
      <Sequence from={at(S.end[0])} durationInFrames={at(S.end[1] - S.end[0])}><End /></Sequence>
      <Audio src={staticFile("music/attic-film.mp3")}
        volume={(f) => interpolate(f, [0, 10, FILM_TOTAL - sec(2.2), FILM_TOTAL], [0, 0.9, 0.9, 0], CLAMP)} />
    </AbsoluteFill>
  );
};
