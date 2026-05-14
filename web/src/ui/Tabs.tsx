import { ReactNode } from 'react'
import styles from './Tabs.module.css'
export function Tabs<T extends string>({ value, onChange, items }:
  { value: T; onChange: (v: T) => void; items: { value: T; label: ReactNode }[] }) {
  return (
    <div role="tablist" className={styles.row}>
      {items.map((it) => (
        <button key={it.value} role="tab" aria-selected={it.value === value}
          className={`${styles.tab} ${it.value === value ? styles.on : ''}`}
          onClick={() => onChange(it.value)}>{it.label}</button>
      ))}
    </div>
  )
}
