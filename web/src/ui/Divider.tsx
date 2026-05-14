import styles from './Divider.module.css'
export function Divider({ inset = false }: { inset?: boolean }) {
  return <hr className={`${styles.div} ${inset ? styles.inset : ''}`} />
}
