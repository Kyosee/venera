import { ButtonHTMLAttributes, ReactNode } from 'react'
import { Ripple } from './Ripple'
import styles from './Button.module.css'

type Variant = 'filled' | 'tonal' | 'outlined' | 'text' | 'elevated'
type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant; leading?: ReactNode; trailing?: ReactNode
}

export function Button({
  variant = 'filled', leading, trailing, children, className, ...rest
}: Props) {
  return (
    <button {...rest} className={`${styles.btn} ${styles[variant]} ${className ?? ''}`}>
      <Ripple disabled={rest.disabled}>
        <span className={styles.label}>
          {leading && <span className={styles.icon}>{leading}</span>}
          {children}
          {trailing && <span className={styles.icon}>{trailing}</span>}
        </span>
      </Ripple>
    </button>
  )
}
