import React from "react";
import { Composition } from "remotion";
import { AtticFilm } from "./AtticFilm";
import { AtticLaunch } from "./AtticLaunch";
import { FILM_TOTAL } from "./film";
import { FPS, H, W } from "./theme";
import { TOTAL } from "./timeline";

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="AtticFilm" component={AtticFilm} durationInFrames={FILM_TOTAL} fps={FPS} width={W} height={H} />
    <Composition id="AtticLaunch" component={AtticLaunch} durationInFrames={TOTAL} fps={FPS} width={W} height={H} />
  </>
);
