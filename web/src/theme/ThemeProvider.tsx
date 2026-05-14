import { ReactNode, useEffect, useMemo } from 'react'
import { fromSeeds, type ColorScheme } from './seed-scheme'
import { resolveSeedColor } from './color-presets'

type ThemeMode = 'light' | 'dark' | 'system'

export function ThemeProvider({
  colorSetting, themeMode, children,
}: { colorSetting: string; themeMode: ThemeMode; children: ReactNode }) {
  const seed = useMemo(() => resolveSeedColor(colorSetting), [colorSetting])

  useEffect(() => {
    const apply = (mode: 'light' | 'dark') => {
      const scheme: ColorScheme = fromSeeds({ primary: seed, brightness: mode })
      const root = document.documentElement
      for (const [k, v] of Object.entries(scheme)) {
        root.style.setProperty(`--md-sys-color-${kebab(k)}`, v)
      }
      root.dataset.theme = mode
      const meta = document.querySelector('meta[name="theme-color"]')
      if (meta) meta.setAttribute('content', scheme.surface)
    }
    if (themeMode === 'system') {
      const mq = window.matchMedia('(prefers-color-scheme: dark)')
      const handler = () => apply(mq.matches ? 'dark' : 'light')
      handler()
      mq.addEventListener('change', handler)
      return () => mq.removeEventListener('change', handler)
    }
    apply(themeMode)
  }, [seed, themeMode])

  return <>{children}</>
}

function kebab(s: string): string {
  return s.replace(/([A-Z])/g, '-$1').toLowerCase()
}
