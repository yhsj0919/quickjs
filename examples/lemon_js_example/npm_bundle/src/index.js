import deepEqual from 'fast-deep-equal';

export const bundledDependency = 'fast-deep-equal';

export function compareValues(left, right) {
  return deepEqual(left, right);
}
