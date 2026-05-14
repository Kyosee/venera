import { ReactNode } from 'react'
import { Ripple } from './Ripple'
import styles from './NaviPane.module.css'

export type PaneItem<K extends string> = {
  key: K; label: string; icon: ReactNode; activeIcon?: ReactNode
}
export type PaneAction = { icon: ReactNode; label: string; onClick: () => void }

export function NaviPane<K extends string>({
  items, actions, current, onChange, children,
}: {
  items: PaneItem<K>[]; actions?: PaneAction[]
  current: K; onChange: (k: K) => void; children: ReactNode
}) {
  return (
    <div className={styles.layout}>
      <aside className={styles.rail}>
        {items.map((it) => (
          <button key={it.key} className={`${styles.item} ${it.key === current ? styles.on : ''}`}
            onClick={() => onChange(it.key)}>
            <Ripple><span className={styles.icon}>
              {it.key === current ? (it.activeIcon ?? it.icon) : it.icon}
            </span></Ripple>
            <span className={styles.label}>{it.label}</span>
          </button>
        ))}
        {actions && <div className={styles.actions}>
          {actions.map((a, i) => (
            <button key={i} className={styles.item} onClick={a.onClick}>
              <Ripple><span className={styles.icon}>{a.icon}</span></Ripple>
              <span className={styles.label}>{a.label}</span>
            </button>
          ))}
        </div>}
      </aside>
      <main className={styles.main}>{children}</main>
      <nav className={styles.bottom}>
        {items.map((it) => (
          <button key={it.key} className={`${styles.bitem} ${it.key === current ? styles.bon : ''}`}
            onClick={() => onChange(it.key)}>
            <span className={styles.bicon}>
              {it.key === current ? (it.activeIcon ?? it.icon) : it.icon}
            </span>
            <span className={styles.blabel}>{it.label}</span>
          </button>
        ))}
      </nav>
    </div>
  )
}
