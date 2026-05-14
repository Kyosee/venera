import { ReactNode } from 'react'
import styles from './ComicGrid.module.css'
export function ComicGrid({ children }: { children: ReactNode }) {
  return <div className={styles.grid}>{children}</div>
}
