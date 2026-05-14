import { InputHTMLAttributes, ReactNode } from 'react'
import styles from './TextField.module.css'

export function TextField({ label, leading, trailing, error, helper, variant = 'outlined', className, ...rest }:
  InputHTMLAttributes<HTMLInputElement> & {
    label?: string; leading?: ReactNode; trailing?: ReactNode;
    error?: string; helper?: string; variant?: 'outlined' | 'filled'
  }) {
  return (
    <label className={`${styles.field} ${styles[variant]} ${error ? styles.errored : ''} ${className ?? ''}`}>
      {label && <span className={styles.label}>{label}</span>}
      <span className={styles.row}>
        {leading && <span className={styles.icon}>{leading}</span>}
        <input {...rest} className={styles.input} />
        {trailing && <span className={styles.icon}>{trailing}</span>}
      </span>
      {(error || helper) && <span className={styles.helper}>{error ?? helper}</span>}
    </label>
  )
}
