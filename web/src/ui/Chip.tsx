import { HTMLAttributes, ReactNode } from 'react'
import styles from './Chip.module.css'
export function Chip({ selected, leading, children, className, ...rest }:
  HTMLAttributes<HTMLButtonElement> & { selected?: boolean; leading?: ReactNode; children: ReactNode }) {
  return (
    <button type="button" {...(rest as any)} className={`${styles.chip} ${selected ? styles.on : ''} ${className ?? ''}`}>
      {leading && <span className={styles.icon}>{leading}</span>}
      <span>{children}</span>
    </button>
  )
}
