// @ts-check
import antfu from '@antfu/eslint-config';

export default antfu(
  {
    type: 'lib',
    pnpm: true,
    stylistic: {
      semi: true,
    },
    rules: {
      'node/prefer-global/process': 'off',
    },
  },
);
