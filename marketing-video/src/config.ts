export type Feature = {
  eyebrow: string;
  title: string;
  description: string;
  tags: string[];
};

export type PromoConfig = {
  productName: string;
  tagline: string;
  taglineZh: string;
  hook: string;
  finalStatement: string;
  priceLabel: string;
  price: string;
  website: string;
  cta: string;
  features: [Feature, Feature, Feature];
  colors: {
    background: string;
    panel: string;
    cyan: string;
    cyanSoft: string;
    text: string;
    muted: string;
  };
};

// 修改标题、卖点、价格或网址，只需编辑此文件。
export const promoConfig: PromoConfig = {
  productName: 'DataLayer Studio',
  tagline: 'Turn every workout into a story worth watching.',
  taglineZh: '让每一次训练，都成为值得回看的故事。',
  hook: '训练，不只是一段视频。',
  finalStatement: '让数据进入画面，让观众读懂每一次突破。',
  priceLabel: '早鸟价',
  price: '¥68',
  website: 'datalayer-studio.ligh-t-ouch.com',
  cta: '立即了解',
  features: [
    {
      eyebrow: '01 · 自动同步',
      title: '视频与训练数据精准对齐',
      description: '导入 FIT / GPX 运动文件，自动读取时间、路线和训练指标。',
      tags: ['FIT / GPX', '时间轴', '自动读取'],
    },
    {
      eyebrow: '02 · 动态数据层',
      title: '把每项指标变成专业画面',
      description: '自由组合配速、心率、功率、步频、海拔、速度等动态组件。',
      tags: ['配速', '心率', '功率', '步频', '海拔', '速度'],
    },
    {
      eyebrow: '03 · 一键工作流',
      title: '继续在剪辑软件中自由创作',
      description: '导出透明 Alpha 数据层，无缝进入 DaVinci Resolve 等专业时间线。',
      tags: ['DaVinci Resolve', 'Final Cut Pro', 'Premiere Pro'],
    },
  ],
  colors: {
    background: '#06131d',
    panel: '#0d2432',
    cyan: '#5be2f5',
    cyanSoft: '#7ddcff',
    text: '#f4f8fb',
    muted: '#9ab0bd',
  },
};
