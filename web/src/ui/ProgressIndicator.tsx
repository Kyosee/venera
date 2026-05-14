import styles from './ProgressIndicator.module.css'
export function CircularProgress({ size = 24 }: { size?: number }) {
  return <span className={styles.circular} style={{ width: size, height: size }} />
}
export function LinearProgress({ value }: { value?: number }) {
  return value === undefined
    ? <span className={styles.linearIndeterminate}><span /></span>
    : <span className={styles.linearTrack}><span style={{ width: `${value * 100}%` }} /></span>
}
