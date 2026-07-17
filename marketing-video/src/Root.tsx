import React from 'react';
import {Composition} from 'remotion';
import {Promo30s} from './Promo';
import {promoConfig} from './config';

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="Promo30s"
      component={Promo30s}
      durationInFrames={900}
      fps={30}
      width={1920}
      height={1080}
      defaultProps={promoConfig}
    />
  );
};
