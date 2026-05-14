import { ReactNode } from 'react'
import styles from './AppBar.module.css'
export function AppBar({ leading, title, actions, variant = 'center' }:
  { leading?: ReactNode; title: ReactNode; actions?: ReactNode; variant?: 'small' | 'center' | 'medium' | 'large' }) {
  return (
    <header className={`${styles.bar} ${styles[variant]}`}>
      {leading && <div className={styles.leading}>{leading}</div>}
      <h1 className={styles.title}>{title}</h1>
      {actions && <div className={styles.actions}>{actions}</div>}
    </header>
  )
}
