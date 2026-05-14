import { HTMLAttributes, ReactNode } from 'react'
import styles from './Card.module.css'
export function Card({ variant = 'filled', children, className, ...rest }:
  HTMLAttributes<HTMLDivElement> & { variant?: 'filled' | 'outlined' | 'elevated'; children: ReactNode }) {
  return <div {...rest} className={`${styles.card} ${styles[variant]} ${className ?? ''}`}>{children}</div>
}
