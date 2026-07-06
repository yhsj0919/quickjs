import { Column, Text } from 'quickjs_ui';

export function PackageSummary(props) {
  return Column({
    crossAxisAlignment: 'stretch',
    gap: 4,
    children: [
      Text(`package: ${props.id}`),
      Text(`version: ${props.version}`),
      Text(`modules: ${props.modules}`),
      Text(`resources: ${props.resources}`)
    ]
  });
}
