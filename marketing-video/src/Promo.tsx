import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  interpolate,
  OffthreadVideo,
  Sequence,
  staticFile,
  useCurrentFrame,
} from 'remotion';
import type {Feature, PromoConfig} from './config';

const FONT =
  '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Noto Sans SC", sans-serif';
const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const fadeUp = (frame: number, delay = 0, distance = 28) => {
  const progress = interpolate(frame, [delay, delay + 18], [0, 1], {
    ...clamp,
    easing: easeOut,
  });

  return {
    opacity: progress,
    transform: `translateY(${(1 - progress) * distance}px)`,
  };
};

const Background: React.FC<{colors: PromoConfig['colors']}> = ({colors}) => {
  return (
    <AbsoluteFill
      style={{
        background: `
          radial-gradient(circle at 82% 18%, rgba(63, 174, 201, 0.18), transparent 36%),
          radial-gradient(circle at 18% 88%, rgba(21, 119, 125, 0.2), transparent 40%),
          linear-gradient(145deg, ${colors.background}, #071925 58%, #061018)
        `,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: 0.11,
          backgroundImage:
            'linear-gradient(rgba(124,220,255,.35) 1px, transparent 1px), linear-gradient(90deg, rgba(124,220,255,.35) 1px, transparent 1px)',
          backgroundSize: '180px 180px',
        }}
      />
    </AbsoluteFill>
  );
};

const SceneLayer: React.FC<{
  children: React.ReactNode;
  colors: PromoConfig['colors'];
  fade?: boolean;
}> = ({children, colors, fade = true}) => {
  const frame = useCurrentFrame();
  const opacity = fade
    ? interpolate(frame, [0, 6], [0, 1], {...clamp, easing: easeOut})
    : 1;

  return (
    <AbsoluteFill style={{opacity, fontFamily: FONT, color: colors.text}}>
      <Background colors={colors} />
      {children}
    </AbsoluteFill>
  );
};

const Eyebrow: React.FC<{
  children: React.ReactNode;
  color: string;
  style?: React.CSSProperties;
}> = ({children, color, style}) => (
  <div
    style={{
      color,
      fontSize: 28,
      fontWeight: 700,
      letterSpacing: '0.1em',
      textTransform: 'uppercase',
      ...style,
    }}
  >
    {children}
  </div>
);

const Subtitle: React.FC<{
  text: string;
  colors: PromoConfig['colors'];
  delay?: number;
}> = ({text, colors, delay = 12}) => {
  const frame = useCurrentFrame();
  const style = fadeUp(frame, delay, 18);

  return (
    <div
      style={{
        position: 'absolute',
        left: 240,
        right: 240,
        bottom: 62,
        height: 74,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '0 44px',
        borderRadius: 38,
        background: 'rgba(3, 14, 22, 0.78)',
        border: '1px solid rgba(125, 220, 255, 0.22)',
        boxShadow: '0 24px 70px rgba(0,0,0,.22)',
        backdropFilter: 'blur(18px)',
        fontSize: 32,
        fontWeight: 560,
        letterSpacing: '0.025em',
        color: colors.text,
        textAlign: 'center',
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        ...style,
      }}
    >
      {text}
    </div>
  );
};

const HookScene: React.FC<PromoConfig> = (config) => {
  const frame = useCurrentFrame();
  const reveal = interpolate(frame, [22, 70], [0, 100], {
    ...clamp,
    easing: easeInOut,
  });
  const copy = fadeUp(frame, 8, 26);

  return (
    <SceneLayer colors={config.colors} fade={false}>
      <OffthreadVideo
        src={staticFile('generated/run-before.mp4')}
        muted
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
        }}
      />
      <AbsoluteFill style={{clipPath: `inset(0 ${100 - reveal}% 0 0)`}}>
        <OffthreadVideo
          src={staticFile('generated/run-after.mp4')}
          muted
          style={{width: '100%', height: '100%', objectFit: 'cover'}}
        />
      </AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: `${reveal}%`,
          top: 0,
          bottom: 0,
          width: 3,
          background: config.colors.cyan,
          boxShadow: '0 0 28px rgba(91,226,245,.55)',
          transform: 'translateX(-1.5px)',
          opacity: interpolate(frame, [20, 28, 72, 82], [0, 1, 1, 0], clamp),
        }}
      />
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(90deg, rgba(3,12,19,.72) 0%, rgba(3,12,19,.18) 50%, transparent 76%), linear-gradient(0deg, rgba(3,12,19,.62), transparent 48%)',
        }}
      />
      <div style={{position: 'absolute', left: 94, top: 86, ...copy}}>
        <Eyebrow color={config.colors.cyan}>BEFORE / AFTER</Eyebrow>
        <div
          style={{
            marginTop: 22,
            width: 980,
            fontSize: 78,
            lineHeight: 1.08,
            fontWeight: 760,
            letterSpacing: '-0.04em',
            whiteSpace: 'nowrap',
            textShadow: '0 12px 45px rgba(0,0,0,.35)',
          }}
        >
          {config.hook}
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          right: 86,
          top: 76,
          padding: '14px 22px',
          borderRadius: 999,
          background: reveal > 55 ? 'rgba(33,166,173,.82)' : 'rgba(4,16,25,.72)',
          border: '1px solid rgba(255,255,255,.18)',
          fontSize: 24,
          fontWeight: 700,
          letterSpacing: '.08em',
        }}
      >
        {reveal > 55 ? '数据层开启' : '原始视频'}
      </div>
    </SceneLayer>
  );
};

const BrandScene: React.FC<PromoConfig> = (config) => {
  const frame = useCurrentFrame();
  const local = Math.max(0, frame - 6);
  const title = fadeUp(local, 4, 34);
  const image = fadeUp(local, 14, 38);
  const drift = interpolate(local, [0, 150], [1.025, 1.065], {
    ...clamp,
    easing: easeInOut,
  });

  return (
    <SceneLayer colors={config.colors}>
      <div style={{position: 'absolute', left: 94, top: 158, width: 680, ...title}}>
        <Eyebrow color={config.colors.cyan}>MACOS · VIDEO DATA OVERLAYS</Eyebrow>
        <div
          style={{
            marginTop: 22,
            fontSize: 76,
            fontWeight: 780,
            letterSpacing: '-0.045em',
            lineHeight: 0.98,
            whiteSpace: 'nowrap',
          }}
        >
          {config.productName}
        </div>
        <div
          style={{
            marginTop: 38,
            maxWidth: 620,
            fontSize: 42,
            lineHeight: 1.38,
            fontWeight: 620,
            color: config.colors.text,
          }}
        >
          {config.taglineZh}
        </div>
        <div
          style={{
            marginTop: 18,
            maxWidth: 610,
            color: config.colors.muted,
            fontSize: 25,
            lineHeight: 1.45,
          }}
        >
          {config.tagline}
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          right: -30,
          top: 116,
          width: 1160,
          height: 776,
          borderRadius: 34,
          overflow: 'hidden',
          border: '1px solid rgba(125,220,255,.22)',
          background: '#15191d',
          boxShadow: '0 44px 110px rgba(0,0,0,.48)',
          ...image,
        }}
      >
        <Img
          src={staticFile('generated/editor.webp')}
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            objectPosition: '50% 50%',
            transform: `scale(${drift})`,
          }}
        />
        <div
          style={{
            position: 'absolute',
            inset: 0,
            boxShadow: 'inset 0 0 90px rgba(3,12,19,.3)',
          }}
        />
      </div>
    </SceneLayer>
  );
};

type FeatureSceneProps = PromoConfig & {
  feature: Feature;
  sourceStart: number;
  focus: 'timeline' | 'components' | 'export';
};

const focusRects = {
  timeline: {left: 64, top: 388, width: 990, height: 150, origin: '54% 80%'},
  components: {left: 160, top: 12, width: 170, height: 350, origin: '18% 48%'},
  export: {left: 350, top: 92, width: 520, height: 390, origin: '52% 45%'},
};

const FeatureScene: React.FC<FeatureSceneProps> = ({
  feature,
  sourceStart,
  focus,
  ...config
}) => {
  const frame = useCurrentFrame();
  const local = Math.max(0, frame - 6);
  const copy = fadeUp(local, 5, 28);
  const media = fadeUp(local, 10, 30);
  const focusRect = focusRects[focus];
  const zoom = interpolate(local, [0, 145], [1.015, 1.075], {
    ...clamp,
    easing: easeInOut,
  });
  const ringOpacity =
    focus === 'components'
      ? interpolate(local, [10, 18, 112, 138], [0, 1, 1, 0], clamp)
      : interpolate(local, [22, 34, 112, 138], [0, 0.8, 0.8, 0], clamp);

  return (
    <SceneLayer colors={config.colors}>
      <div style={{position: 'absolute', left: 92, top: 202, width: 520, ...copy}}>
        <Eyebrow color={config.colors.cyan}>{feature.eyebrow}</Eyebrow>
        <div
          style={{
            marginTop: 24,
            fontSize: 68,
            lineHeight: 1.08,
            fontWeight: 760,
            letterSpacing: '-0.035em',
          }}
        >
          {feature.title}
        </div>
        <div
          style={{
            marginTop: 26,
            color: config.colors.muted,
            fontSize: 29,
            lineHeight: 1.55,
            maxWidth: 500,
          }}
        >
          {feature.description}
        </div>
        <div style={{display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 32}}>
          {feature.tags.map((tag, index) => (
            <div
              key={tag}
              style={{
                ...(focus === 'components'
                  ? {opacity: 1, transform: 'translateY(0)'}
                  : fadeUp(local, 22 + index * 3, 12)),
                padding: '10px 16px',
                borderRadius: 999,
                border: '1px solid rgba(125,220,255,.24)',
                background: 'rgba(15,47,60,.62)',
                color: config.colors.cyanSoft,
                fontSize: 22,
                fontWeight: 650,
              }}
            >
              {tag}
            </div>
          ))}
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          right: 66,
          top: 188,
          width: 1200,
          height: 580,
          borderRadius: 30,
          overflow: 'hidden',
          background: '#10171d',
          border: '1px solid rgba(125,220,255,.22)',
          boxShadow: '0 42px 100px rgba(0,0,0,.45)',
          ...media,
        }}
      >
        <OffthreadVideo
          src={staticFile('generated/app-demo.mp4')}
          trimBefore={sourceStart * 30}
          muted
          style={{
            width: '100%',
            height: '100%',
            objectFit: 'cover',
            transform: `scale(${zoom})`,
            transformOrigin: focusRect.origin,
          }}
        />
        <div
          style={{
            position: 'absolute',
            left: focusRect.left,
            top: focusRect.top,
            width: focusRect.width,
            height: focusRect.height,
            borderRadius: focus === 'components' ? 12 : 18,
            border:
              focus === 'components'
                ? '3px solid rgba(91,226,245,.98)'
                : '2px solid rgba(91,226,245,.78)',
            boxShadow:
              focus === 'components'
                ? '0 0 0 999px rgba(3,13,21,.14), 0 0 34px rgba(91,226,245,.42)'
                : '0 0 0 999px rgba(3,13,21,.08), 0 0 30px rgba(91,226,245,.18)',
            opacity: ringOpacity,
          }}
        />
      </div>
      <Subtitle text={feature.description} colors={config.colors} delay={16} />
    </SceneLayer>
  );
};

const FinalEffectScene: React.FC<PromoConfig> = (config) => {
  const frame = useCurrentFrame();
  const local = Math.max(0, frame - 6);
  const scale = interpolate(local, [0, 120], [1, 1.045], {
    ...clamp,
    easing: easeInOut,
  });
  const copy = fadeUp(local, 10, 26);

  return (
    <SceneLayer colors={config.colors}>
      <OffthreadVideo
        src={staticFile('generated/run-after.mp4')}
        trimBefore={10}
        muted
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: `scale(${scale})`,
        }}
      />
      <AbsoluteFill
        style={{
          background:
            'linear-gradient(0deg, rgba(2,10,16,.82) 0%, rgba(2,10,16,.22) 42%, transparent 72%)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 90,
          right: 90,
          bottom: 160,
          textAlign: 'center',
          ...copy,
        }}
      >
        <div
          style={{
            fontSize: 58,
            lineHeight: 1.2,
            fontWeight: 740,
            letterSpacing: '-0.025em',
            textShadow: '0 12px 50px rgba(0,0,0,.45)',
          }}
        >
          {config.finalStatement}
        </div>
        <div
          style={{
            marginTop: 14,
            color: config.colors.cyanSoft,
            fontSize: 25,
            letterSpacing: '.03em',
          }}
        >
          {config.tagline}
        </div>
      </div>
    </SceneLayer>
  );
};

const CtaScene: React.FC<PromoConfig> = (config) => {
  const frame = useCurrentFrame();
  const local = Math.max(0, frame - 6);
  const icon = fadeUp(local, 2, 24);
  const copy = fadeUp(local, 8, 28);
  const price = fadeUp(local, 15, 22);

  return (
    <SceneLayer colors={config.colors}>
      <div
        style={{
          position: 'absolute',
          left: 148,
          top: 194,
          display: 'flex',
          alignItems: 'center',
          gap: 42,
          ...icon,
        }}
      >
        <Img
          src={staticFile('generated/app-icon.png')}
          style={{
            width: 174,
            height: 174,
            borderRadius: 42,
            boxShadow: '0 36px 90px rgba(0,0,0,.38)',
          }}
        />
        <div style={{...copy}}>
          <Eyebrow color={config.colors.cyan}>AVAILABLE NOW</Eyebrow>
          <div
            style={{
              marginTop: 10,
              fontSize: 76,
              lineHeight: 1,
              fontWeight: 780,
              letterSpacing: '-0.035em',
              whiteSpace: 'nowrap',
            }}
          >
            {config.productName}
          </div>
        </div>
      </div>

      <div
        style={{
          position: 'absolute',
          left: 148,
          right: 148,
          top: 472,
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: 28,
          ...price,
        }}
      >
        <div
          style={{
            height: 252,
            padding: '36px 44px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 72,
            borderRadius: 30,
            border: '1px solid rgba(125,220,255,.22)',
            background: 'rgba(12,38,52,.7)',
            boxShadow: '0 34px 90px rgba(0,0,0,.25)',
          }}
        >
          <div
            style={{
              color: config.colors.cyan,
              fontSize: 62,
              lineHeight: 1,
              fontWeight: 780,
              letterSpacing: '0.04em',
              whiteSpace: 'nowrap',
              textShadow: '0 0 36px rgba(91,226,245,.42)',
            }}
          >
            {config.priceLabel}
          </div>
          <div
            style={{
              color: config.colors.text,
              fontSize: 96,
              lineHeight: 1,
              fontWeight: 780,
              letterSpacing: '-0.045em',
            }}
          >
            {config.price}
          </div>
        </div>
        <div
          style={{
            height: 252,
            padding: '36px 44px',
            borderRadius: 30,
            background: config.colors.cyan,
            color: '#04131b',
            boxShadow: '0 34px 90px rgba(20,157,176,.24)',
          }}
        >
          <div style={{fontSize: 44, lineHeight: 1, fontWeight: 780}}>{config.cta} →</div>
          <div
            style={{
              marginTop: 48,
              fontSize: 36,
              fontWeight: 700,
              letterSpacing: '-0.015em',
              whiteSpace: 'nowrap',
            }}
          >
            {config.website}
          </div>
        </div>
      </div>
    </SceneLayer>
  );
};

const Soundtrack: React.FC = () => {
  return (
    <>
      <Audio src={staticFile('generated/music.wav')} volume={0.58} />
      {[84, 234, 384, 534, 684, 804].map((from) => (
        <Sequence key={from} from={from} durationInFrames={24}>
          <Audio src={staticFile('generated/whoosh.wav')} volume={0.2} />
        </Sequence>
      ))}
      <Sequence from={808} durationInFrames={18}>
        <Audio src={staticFile('generated/accent.wav')} volume={0.24} />
      </Sequence>
    </>
  );
};

export const Promo30s: React.FC<PromoConfig> = (config) => {
  return (
    <AbsoluteFill style={{background: config.colors.background}}>
      <Sequence from={0} durationInFrames={90}>
        <HookScene {...config} />
      </Sequence>
      <Sequence from={84} durationInFrames={156}>
        <BrandScene {...config} />
      </Sequence>
      <Sequence from={234} durationInFrames={156}>
        <FeatureScene
          {...config}
          feature={config.features[0]}
          sourceStart={20.5}
          focus="timeline"
        />
      </Sequence>
      <Sequence from={384} durationInFrames={156}>
        <FeatureScene
          {...config}
          feature={config.features[1]}
          sourceStart={34}
          focus="components"
        />
      </Sequence>
      <Sequence from={534} durationInFrames={156}>
        <FeatureScene
          {...config}
          feature={config.features[2]}
          sourceStart={39.5}
          focus="export"
        />
      </Sequence>
      <Sequence from={684} durationInFrames={126}>
        <FinalEffectScene {...config} />
      </Sequence>
      <Sequence from={804} durationInFrames={96}>
        <CtaScene {...config} />
      </Sequence>
      <Soundtrack />
    </AbsoluteFill>
  );
};
