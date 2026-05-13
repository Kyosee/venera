export const COLOR_PRESETS = {
  red:    '#F44336',
  pink:   '#E91E63',
  purple: '#9C27B0',
  green:  '#4CAF50',
  orange: '#FF9800',
  blue:   '#2196F3',
  yellow: '#FFEB3B',
  cyan:   '#00BCD4',
} as const

export type ColorPresetKey = keyof typeof COLOR_PRESETS

export function resolveSeedColor(setting: string): string {
  if (setting === 'system') return COLOR_PRESETS.blue
  if (setting in COLOR_PRESETS) return COLOR_PRESETS[setting as ColorPresetKey]
  return COLOR_PRESETS.blue
}
